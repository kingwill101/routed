import 'dart:io';

import 'deployed_worker_auth_harness.dart';

typedef DeployedWorkerAuthRunnerFactory =
    DeployedWorkerAuthConformanceRunner Function(
      DeployedWorkerAuthConformanceConfig config,
    );

/// Typed command-line options for the deployed Worker auth harness.
final class DeployedWorkerAuthCliOptions {
  DeployedWorkerAuthCliOptions._({
    required this.run,
    required this.help,
    required this.origin,
    required this.originEnvironmentVariable,
    required this.tokenEnvironmentVariable,
    required this.timeout,
    required this.suites,
  });

  factory DeployedWorkerAuthCliOptions.parse(List<String> arguments) {
    var run = false;
    var help = false;
    String? origin;
    var originEnvironmentVariable = 'ROUTED_AUTH_WORKER_ORIGIN';
    var tokenEnvironmentVariable = 'ROUTED_AUTH_CONFORMANCE_TOKEN';
    var timeout = const Duration(seconds: 45);
    final suites = <DeployedWorkerAuthSuite>[];

    String valueAfter(int index, String option) {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw FormatException('$option requires a value.');
      }
      return arguments[index + 1];
    }

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      switch (argument) {
        case '--run':
          run = true;
        case '--help' || '-h':
          help = true;
        case '--origin':
          origin = valueAfter(index, argument);
          index++;
        case '--origin-env':
          originEnvironmentVariable = valueAfter(index, argument);
          index++;
        case '--token-env':
          tokenEnvironmentVariable = valueAfter(index, argument);
          index++;
        case '--timeout-seconds':
          final raw = valueAfter(index, argument);
          final seconds = int.tryParse(raw);
          if (seconds == null || seconds < 1 || seconds > 300) {
            throw const FormatException(
              '--timeout-seconds must be an integer from 1 through 300.',
            );
          }
          timeout = Duration(seconds: seconds);
          index++;
        case '--suite':
          final raw = valueAfter(index, argument);
          final values = raw.split(',').map((value) => value.trim());
          if (values.any((value) => value.isEmpty)) {
            throw const FormatException('--suite values must not be empty.');
          }
          suites.addAll(values.map(DeployedWorkerAuthSuite.parse));
          index++;
        default:
          throw const FormatException('Unknown option.');
      }
    }

    _validateEnvironmentVariableName(originEnvironmentVariable, '--origin-env');
    _validateEnvironmentVariableName(tokenEnvironmentVariable, '--token-env');
    if (suites.toSet().length != suites.length) {
      throw const FormatException('--suite values must not be repeated.');
    }

    return DeployedWorkerAuthCliOptions._(
      run: run,
      help: help,
      origin: origin,
      originEnvironmentVariable: originEnvironmentVariable,
      tokenEnvironmentVariable: tokenEnvironmentVariable,
      timeout: timeout,
      suites: List<DeployedWorkerAuthSuite>.unmodifiable(
        suites.isEmpty ? DeployedWorkerAuthSuite.values : suites,
      ),
    );
  }

  final bool run;
  final bool help;
  final String? origin;
  final String originEnvironmentVariable;
  final String tokenEnvironmentVariable;
  final Duration timeout;
  final List<DeployedWorkerAuthSuite> suites;

  DeployedWorkerAuthConformanceConfig toConfig(Map<String, String> variables) {
    if (!run) throw StateError('A skipped invocation has no run config.');
    final rawOrigin = origin ?? variables[originEnvironmentVariable];
    if (rawOrigin == null || rawOrigin.isEmpty) {
      throw FormatException(
        'Set --origin or environment variable '
        '$originEnvironmentVariable.',
      );
    }
    final token = variables[tokenEnvironmentVariable];
    if (token == null || token.isEmpty) {
      throw FormatException(
        'Environment variable $tokenEnvironmentVariable is not set.',
      );
    }
    return DeployedWorkerAuthConformanceConfig(
      workerOrigin: parseDeployedWorkerOrigin(rawOrigin),
      token: token,
      timeout: timeout,
      suites: suites,
    );
  }
}

void _validateEnvironmentVariableName(String value, String option) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
    throw FormatException('$option must name one environment variable.');
  }
}

const deployedWorkerAuthConformanceUsage = r'''
Deployed Cloudflare Worker auth conformance harness

This command makes no request unless --run is present. It calls only an
already-deployed Worker over HTTPS; it never invokes Wrangler or a Cloudflare
control-plane API and never creates, changes, or deletes Cloudflare resources.

Usage:
  dart run tool/deployed_worker_auth_conformance.dart --run \
    --origin https://your-worker.example.workers.dev \
    [--suite session,jwt,plugins,external-providers,webauthn]

Configuration:
  --run                 Explicitly enable the remote run.
  --origin URL          HTTPS Worker origin. Alternatively set
                        ROUTED_AUTH_WORKER_ORIGIN.
  --origin-env NAME     Select another origin environment variable.
  --token-env NAME      Select the token environment variable. Defaults to
                        ROUTED_AUTH_CONFORMANCE_TOKEN.
  --suite ID[,ID...]    Select suites; repeatable. Defaults to every suite.
  --timeout-seconds N   Per-request timeout from 1 through 300 (default: 45).
  --help, -h            Show this help.

The token is accepted only through the selected environment variable and is
never printed. Configure the same value as the Worker's
ROUTED_AUTH_CONFORMANCE_TOKEN secret binding.
''';

Future<int> runDeployedWorkerAuthConformanceCli(
  List<String> arguments, {
  Map<String, String>? environment,
  StringSink? output,
  StringSink? errorOutput,
  DeployedWorkerAuthRunnerFactory? runnerFactory,
}) async {
  final stdoutSink = output ?? stdout;
  final stderrSink = errorOutput ?? stderr;
  DeployedWorkerAuthCliOptions options;
  try {
    options = DeployedWorkerAuthCliOptions.parse(arguments);
  } on FormatException catch (error) {
    stderrSink
      ..writeln('Configuration error: ${error.message}')
      ..writeln(deployedWorkerAuthConformanceUsage);
    return 64;
  }

  if (options.help || !options.run) {
    stdoutSink.writeln(deployedWorkerAuthConformanceUsage);
    if (!options.run && !options.help) {
      stdoutSink.writeln(
        'No --run flag supplied; no network request was made.',
      );
    }
    return 0;
  }

  DeployedWorkerAuthConformanceConfig config;
  try {
    config = options.toConfig(environment ?? Platform.environment);
  } on Object catch (error) {
    if (error case final FormatException formatError) {
      stderrSink.writeln('Configuration error: ${formatError.message}');
      return 64;
    }
    if (error is! ArgumentError) rethrow;
    stderrSink.writeln('Configuration error: invalid Worker origin or token.');
    return 64;
  }

  final createRunner =
      runnerFactory ?? HttpDeployedWorkerAuthConformanceRunner.new;
  DeployedWorkerAuthConformanceRunner? runner;
  try {
    runner = createRunner(config);
    final report = await runner.run();
    for (final result in report.results) {
      final status = result.passed ? 'PASS' : 'FAIL';
      final detail = result.passed
          ? ''
          : ' ${_safeResultIdentifier(result.caseId ?? result.errorCode)}';
      stdoutSink.writeln('$status ${result.suite.id}$detail');
    }
    if (report.passed) {
      stdoutSink.writeln('Deployed Worker auth conformance passed.');
      return 0;
    }
    stderrSink.writeln('Deployed Worker auth conformance failed.');
    return 1;
  } on DeployedWorkerAuthRequestFailure catch (error) {
    stderrSink.writeln('Harness request failed: ${error.code}.');
    return 69;
  } on Object {
    stderrSink.writeln('Harness failed: internal_error.');
    return 1;
  } finally {
    runner?.close();
  }
}

String _safeResultIdentifier(String? value) {
  if (value == null ||
      value.isEmpty ||
      value.length > 128 ||
      !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
    return 'conformance_failed';
  }
  return value;
}
