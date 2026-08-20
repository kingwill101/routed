import 'dart:io';

import 'live_d1_harness.dart';

typedef LiveD1ControlPlaneFactory = LiveD1ControlPlane Function(String token);

final class LiveD1CliOptions {
  LiveD1CliOptions._({
    required this.live,
    required this.help,
    required this.accountId,
    required this.createDisposable,
    required this.databaseId,
    required this.databaseName,
    required this.namePrefix,
    required this.apiTokenEnvironmentVariable,
  });

  factory LiveD1CliOptions.parse(List<String> arguments) {
    var live = false;
    var help = false;
    var createDisposable = false;
    String? accountId;
    String? databaseId;
    String? databaseName;
    var namePrefix = 'routed-auth-conformance';
    var tokenEnvironment = 'CLOUDFLARE_API_TOKEN';

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
        case '--live':
          live = true;
        case '--help' || '-h':
          help = true;
        case '--create-disposable':
          createDisposable = true;
        case '--account-id':
          accountId = valueAfter(index, argument);
          index++;
        case '--database-id':
          databaseId = valueAfter(index, argument);
          index++;
        case '--database-name':
          databaseName = valueAfter(index, argument);
          index++;
        case '--name-prefix':
          namePrefix = valueAfter(index, argument);
          index++;
        case '--api-token-env':
          tokenEnvironment = valueAfter(index, argument);
          index++;
        default:
          throw FormatException('Unknown option: $argument');
      }
    }

    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tokenEnvironment)) {
      throw const FormatException(
        '--api-token-env must name one environment variable.',
      );
    }
    if (live && !help) {
      if (accountId == null) {
        throw const FormatException('--live requires --account-id.');
      }
      validateCloudflareAccountId(accountId);
      if (createDisposable) {
        if (databaseId != null || databaseName != null) {
          throw const FormatException(
            '--create-disposable cannot be combined with an external '
            '--database-id or --database-name.',
          );
        }
        validateDisposableD1NamePrefix(namePrefix);
      } else {
        if (databaseId == null || databaseName == null) {
          throw const FormatException(
            'External live runs require both --database-id and '
            '--database-name.',
          );
        }
        validateCloudflareD1DatabaseId(databaseId);
        validateCloudflareD1DatabaseName(databaseName);
      }
    }

    return LiveD1CliOptions._(
      live: live,
      help: help,
      accountId: accountId,
      createDisposable: createDisposable,
      databaseId: databaseId,
      databaseName: databaseName,
      namePrefix: namePrefix,
      apiTokenEnvironmentVariable: tokenEnvironment,
    );
  }

  final bool live;
  final bool help;
  final String? accountId;
  final bool createDisposable;
  final String? databaseId;
  final String? databaseName;
  final String namePrefix;
  final String apiTokenEnvironmentVariable;

  LiveD1ConformanceConfig toConfig() {
    if (!live) throw StateError('A non-live invocation has no live config.');
    return LiveD1ConformanceConfig(
      accountId: accountId!,
      target: createDisposable
          ? CreateDisposableLiveD1Target(namePrefix: namePrefix)
          : ExternalLiveD1Target(
              databaseId: databaseId!,
              databaseName: databaseName!,
            ),
    );
  }
}

const liveD1ConformanceUsage = '''
Cloudflare D1 auth conformance harness

This command is non-mutating unless --live is present. Live runs require an
API token in an environment variable; token values are never accepted as
arguments or printed.

Create and clean up a uniquely named disposable database:
  dart run tool/live_d1_conformance.dart --live \\
    --account-id "\$CLOUDFLARE_ACCOUNT_ID" --create-disposable \\
    --name-prefix routed-auth-conformance

Use an existing remote database without deleting it:
  dart run tool/live_d1_conformance.dart --live \\
    --account-id "\$CLOUDFLARE_ACCOUNT_ID" \\
    --database-id "\$CLOUDFLARE_D1_DATABASE_ID" \\
    --database-name "\$CLOUDFLARE_D1_DATABASE_NAME"

The token defaults to CLOUDFLARE_API_TOKEN. Select another environment
variable with --api-token-env NAME. Disposable mode needs D1 Read and D1
Write permissions. External mode mutates only uniquely prefixed test tables
and never deletes the database.
''';

Future<int> runLiveD1ConformanceCli(
  List<String> arguments, {
  Map<String, String>? environment,
  StringSink? output,
  StringSink? errorOutput,
  LiveD1ControlPlaneFactory? controlPlaneFactory,
}) async {
  final stdoutSink = output ?? stdout;
  final stderrSink = errorOutput ?? stderr;
  LiveD1CliOptions options;
  try {
    options = LiveD1CliOptions.parse(arguments);
  } catch (error) {
    stderrSink.writeln('Configuration error: $error');
    stderrSink.writeln(liveD1ConformanceUsage);
    return 64;
  }

  if (options.help || !options.live) {
    stdoutSink.writeln(liveD1ConformanceUsage);
    if (!options.live && !options.help) {
      stdoutSink.writeln(
        'No live flag supplied; no Cloudflare request was made.',
      );
    }
    return 0;
  }

  final variables = environment ?? Platform.environment;
  final token = variables[options.apiTokenEnvironmentVariable]?.trim();
  if (token == null || token.isEmpty) {
    stderrSink.writeln(
      'Configuration error: environment variable '
      '${options.apiTokenEnvironmentVariable} is not set.',
    );
    return 64;
  }

  final factory =
      controlPlaneFactory ??
      (secret) => CloudflareLiveD1ApiClient(apiToken: secret);
  LiveD1ControlPlane? controlPlane;
  try {
    controlPlane = factory(token);
    final report = await LiveD1ConformanceHarness(
      controlPlane: controlPlane,
    ).run(options.toConfig());
    for (final result in report.results) {
      final suffix = result.skippedReason == null
          ? ''
          : ' (skipped: ${result.skippedReason})';
      stdoutSink.writeln('PASS ${result.id}$suffix');
    }
    stdoutSink.writeln(
      options.createDisposable
          ? 'Live D1 conformance passed; the owned database was deleted.'
          : 'Live D1 conformance passed; the external database was retained.',
    );
    return 0;
  } on LiveD1RunFailure catch (error) {
    final testFailure = error.testFailure;
    if (testFailure is LiveD1ConformanceFailure) {
      for (final result in testFailure.report.results.where(
        (result) => !result.passed,
      )) {
        stderrSink.writeln(
          'FAIL ${result.id}: '
          '${redactLiveD1Secrets(result.error ?? 'unknown failure', [token])}',
        );
      }
    } else if (testFailure != null) {
      stderrSink.writeln(
        'Live test failure: '
        '${redactLiveD1Secrets(testFailure.toString(), [token])}',
      );
    }
    if (error.cleanupFailure != null) {
      stderrSink.writeln(
        'CLEANUP FAILURE: '
        '${redactLiveD1Secrets(error.cleanupFailure.toString(), [token])}',
      );
    }
    return error.cleanupFailure == null ? 1 : 2;
  } catch (error) {
    stderrSink.writeln(
      'Live D1 harness failure: '
      '${redactLiveD1Secrets(error.toString(), [token])}',
    );
    return 1;
  } finally {
    if (controlPlane is CloudflareLiveD1ApiClient) {
      controlPlane.close();
    }
  }
}
