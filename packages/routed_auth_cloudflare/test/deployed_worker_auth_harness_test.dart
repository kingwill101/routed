import 'dart:convert';
import 'dart:io';

import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/routed_node.dart' show FetchRuntimeExtension;
import 'package:test/test.dart';

import '../tool/deployed_worker/worker.dart' as worker;
import '../tool/src/deployed_worker_auth_cli.dart';
import '../tool/src/deployed_worker_auth_harness.dart';

void main() {
  group('deployed Worker configuration', () {
    test('accepts only a canonical HTTPS origin', () {
      expect(
        parseDeployedWorkerOrigin('https://auth-check.example.workers.dev'),
        Uri.parse('https://auth-check.example.workers.dev/'),
      );

      for (final value in <String>[
        'http://auth-check.example.workers.dev',
        'https://user:pass@auth-check.example.workers.dev',
        'https://auth-check.example.workers.dev:8443',
        'https://auth-check.example.workers.dev/path',
        'https://auth-check.example.workers.dev?query=yes',
        'https://auth-check.example.workers.dev/#fragment',
        'https://auth-check.example.workers.dev\n',
      ]) {
        expect(
          () => parseDeployedWorkerOrigin(value),
          throwsArgumentError,
          reason: value.replaceAll('\n', r'\n'),
        );
      }
    });

    test('redacts rejected tokens', () {
      const secret = 'secret-with-a-control\n';
      Object? failure;
      try {
        validateDeployedWorkerToken(secret);
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      expect('$failure', isNot(contains(secret.trim())));
    });

    test('redacts credentials from rejected origins', () {
      const password = 'do-not-print-this-password';
      Object? failure;
      try {
        validateDeployedWorkerOrigin(
          Uri.parse('https://user:$password@example.workers.dev'),
        );
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      expect('$failure', isNot(contains(password)));
    });

    test('parses every selectable suite and rejects duplicates', () {
      final options = DeployedWorkerAuthCliOptions.parse(<String>[
        '--run',
        '--suite',
        'session,jwt',
        '--suite',
        'plugins',
        '--suite',
        'external-providers,webauthn',
      ]);
      expect(options.suites, DeployedWorkerAuthSuite.values);
      expect(
        () => DeployedWorkerAuthCliOptions.parse(<String>[
          '--suite',
          'session',
          '--suite',
          'session',
        ]),
        throwsFormatException,
      );
      expect(
        () => DeployedWorkerAuthSuite.parse('not-a-suite'),
        throwsFormatException,
      );
    });

    test('validates environment names and timeout bounds', () {
      expect(
        () => DeployedWorkerAuthCliOptions.parse(<String>[
          '--token-env',
          'NOT-AN-ENV',
        ]),
        throwsFormatException,
      );
      for (final value in <String>['0', '301', 'not-a-number']) {
        expect(
          () => DeployedWorkerAuthCliOptions.parse(<String>[
            '--timeout-seconds',
            value,
          ]),
          throwsFormatException,
        );
      }
    });
  });

  group('opt-in CLI', () {
    test('skips safely without --run', () async {
      var createdRunner = false;
      final output = StringBuffer();
      final code = await runDeployedWorkerAuthConformanceCli(
        const <String>[],
        environment: const <String, String>{},
        output: output,
        errorOutput: StringBuffer(),
        runnerFactory: (config) {
          createdRunner = true;
          return _FakeRunner(const DeployedWorkerAuthConformanceReport([]));
        },
      );

      expect(code, 0);
      expect(createdRunner, isFalse);
      expect(output.toString(), contains('no network request was made'));
    });

    test('requires origin and token only for an enabled run', () async {
      final errors = StringBuffer();
      final code = await runDeployedWorkerAuthConformanceCli(
        const <String>['--run'],
        environment: const <String, String>{},
        output: StringBuffer(),
        errorOutput: errors,
        runnerFactory: (_) => throw StateError('must not create runner'),
      );

      expect(code, 64);
      expect(errors.toString(), contains('ROUTED_AUTH_WORKER_ORIGIN'));
    });

    test('passes typed config and closes the runner', () async {
      late DeployedWorkerAuthConformanceConfig captured;
      late _FakeRunner runner;
      final output = StringBuffer();
      final code = await runDeployedWorkerAuthConformanceCli(
        const <String>[
          '--run',
          '--suite',
          'session,webauthn',
          '--timeout-seconds',
          '12',
        ],
        environment: const <String, String>{
          'ROUTED_AUTH_WORKER_ORIGIN': 'https://auth-check.example.workers.dev',
          'ROUTED_AUTH_CONFORMANCE_TOKEN': 'test-only-token',
        },
        output: output,
        errorOutput: StringBuffer(),
        runnerFactory: (config) {
          captured = config;
          return runner = _FakeRunner(
            DeployedWorkerAuthConformanceReport(<DeployedWorkerAuthSuiteResult>[
              for (final suite in config.suites)
                DeployedWorkerAuthSuiteResult(suite: suite, passed: true),
            ]),
          );
        },
      );

      expect(code, 0);
      expect(captured.timeout, const Duration(seconds: 12));
      expect(captured.suites, <DeployedWorkerAuthSuite>[
        DeployedWorkerAuthSuite.session,
        DeployedWorkerAuthSuite.webAuthn,
      ]);
      expect(runner.closed, isTrue);
      expect(output.toString(), contains('PASS session'));
      expect(output.toString(), contains('PASS webauthn'));
      expect(output.toString(), isNot(contains('test-only-token')));
    });

    test('uses isolated requests for sequential suite calls', () async {
      final source = File(
        'tool/src/deployed_worker_auth_harness.dart',
      ).readAsStringSync();
      expect(source, contains('..persistentConnection = false'));
    });

    test('reports only stable failure identifiers', () async {
      final output = StringBuffer();
      final errors = StringBuffer();
      final code = await runDeployedWorkerAuthConformanceCli(
        const <String>['--run', '--suite', 'session'],
        environment: const <String, String>{
          'ROUTED_AUTH_WORKER_ORIGIN': 'https://auth-check.example.workers.dev',
          'ROUTED_AUTH_CONFORMANCE_TOKEN': 'never-print-this-token',
        },
        output: output,
        errorOutput: errors,
        runnerFactory: (_) => _FakeRunner(
          const DeployedWorkerAuthConformanceReport(
            <DeployedWorkerAuthSuiteResult>[
              DeployedWorkerAuthSuiteResult(
                suite: DeployedWorkerAuthSuite.session,
                passed: false,
                caseId: 'csrf.reject-invalid',
                errorCode: 'conformance_failed',
              ),
              DeployedWorkerAuthSuiteResult(
                suite: DeployedWorkerAuthSuite.jwt,
                passed: false,
                caseId: 'unsafe\nnever-print-this-token',
              ),
            ],
          ),
        ),
      );

      expect(code, 1);
      expect(output.toString(), contains('FAIL session csrf.reject-invalid'));
      expect(output.toString(), contains('FAIL jwt conformance_failed'));
      expect(output.toString(), isNot(contains('never-print-this-token')));
      expect(errors.toString(), isNot(contains('never-print-this-token')));
    });

    test('does not expose unexpected runner failures', () async {
      final errors = StringBuffer();
      final code = await runDeployedWorkerAuthConformanceCli(
        const <String>['--run'],
        environment: const <String, String>{
          'ROUTED_AUTH_WORKER_ORIGIN': 'https://auth-check.example.workers.dev',
          'ROUTED_AUTH_CONFORMANCE_TOKEN': 'never-print-this-token',
        },
        output: StringBuffer(),
        errorOutput: errors,
        runnerFactory: (_) =>
            _ThrowingRunner(StateError('/srv/secrets/cloudflare-token.txt')),
      );

      expect(code, 1);
      expect(errors.toString(), 'Harness failed: internal_error.\n');
    });
  });

  test('Worker artifacts expose a module wrapper without embedded secrets', () {
    final worker = File('tool/deployed_worker/worker.dart').readAsStringSync();
    final wrapper = File(
      'tool/deployed_worker/worker_wrapper.mjs',
    ).readAsStringSync();
    final config = File(
      'tool/deployed_worker/wrangler.jsonc',
    ).readAsStringSync();

    expect(worker, contains("import 'package:routed_auth/testing.dart';"));
    expect(worker, isNot(contains('package:web')));
    expect(worker, isNot(contains('dart:js_interop')));
    expect(worker, isNot(contains('package:routed_auth/src/')));
    expect(wrapper, contains('export default'));
    expect(wrapper, contains('__routed_fetch__'));
    expect(config, contains('"compatibility_date": "2026-08-20"'));
    expect(config, isNot(contains('ROUTED_AUTH_CONFORMANCE_TOKEN')));
  });

  test('Worker control endpoints require the secret text binding', () async {
    final engine = worker.createDeployedWorkerAuthConformanceEngine();
    await engine.initialize();
    addTearDown(engine.close);
    final origin = Uri.parse('https://auth-check.example.workers.dev');
    const environment = _FakeEnvironment(<String, Object?>{
      'ROUTED_AUTH_CONFORMANCE_TOKEN': 'dedicated-test-token',
    });

    Future<FetchResponseView> send({String? token, String? body}) {
      return dispatchFetchExchange(
        engine,
        _ControlRequest(
          origin: origin,
          path: body == null
              ? '/__routed_auth_conformance/health'
              : '/__routed_auth_conformance/run',
          method: body == null ? 'GET' : 'POST',
          token: token,
          bodyValue: body,
          environment: environment,
        ),
        runtime: const RoutedNodeRuntimeInfo(
          runtime: RoutedNodeRuntime.cloudflare,
          capabilities: cloudflareCapabilities,
        ),
      );
    }

    final missing = await send();
    expect(missing.statusCode, 401);
    expect(await utf8.decodeStream(missing.body), '{"error":"unauthorized"}');

    final health = await send(token: 'dedicated-test-token');
    expect(health.statusCode, 200);
    final healthBody = jsonDecode(await utf8.decodeStream(health.body)) as Map;
    expect(healthBody['protocolVersion'], deployedWorkerAuthProtocolVersion);
    expect(healthBody['suites'], <String>[
      for (final suite in DeployedWorkerAuthSuite.values) suite.id,
    ]);

    final run = await send(
      token: 'dedicated-test-token',
      body: jsonEncode(<String, Object?>{'suite': 'session'}),
    );
    expect(run.statusCode, 200);
    expect(jsonDecode(await utf8.decodeStream(run.body)), <String, Object?>{
      'suite': 'session',
      'passed': true,
    });
  });

  test(
    'every advertised Worker suite satisfies its public Routed contract',
    () async {
      final origin = Uri.parse('https://auth-check.example.workers.dev');
      for (final suite in DeployedWorkerAuthSuite.values) {
        await worker.runDeployedWorkerAuthSuite(suite, origin);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

final class _FakeRunner implements DeployedWorkerAuthConformanceRunner {
  _FakeRunner(this.report);

  final DeployedWorkerAuthConformanceReport report;
  bool closed = false;

  @override
  Future<DeployedWorkerAuthConformanceReport> run() async => report;

  @override
  void close() => closed = true;
}

final class _ThrowingRunner implements DeployedWorkerAuthConformanceRunner {
  _ThrowingRunner(this.error);

  final Object error;

  @override
  Future<DeployedWorkerAuthConformanceReport> run() => Future.error(error);

  @override
  void close() {}
}

final class _FakeEnvironment implements CloudflareEnvironment {
  const _FakeEnvironment(this.bindings);

  final Map<String, Object?> bindings;

  @override
  Object binding(String name) {
    final value = bindings[name];
    if (value == null) throw StateError('missing binding');
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused test binding: ${invocation.memberName}');
}

final class _ControlRequest implements FetchRequestView {
  _ControlRequest({
    required this.origin,
    required this.path,
    required this.method,
    required this.environment,
    this.token,
    this.bodyValue,
  });

  final Uri origin;
  final String path;
  @override
  final String method;
  final String? token;
  final String? bodyValue;
  final CloudflareEnvironment environment;

  @override
  String get url => origin.resolve(path).toString();

  @override
  Map<String, Object?> get rawHeaders => <String, Object?>{
    if (token != null) deployedWorkerAuthTokenHeader: token,
    if (bodyValue != null) 'content-type': 'application/json',
  };

  @override
  Stream<List<int>> get body => bodyValue == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(bodyValue!));

  @override
  String get remoteAddress => '127.0.0.1';

  @override
  RoutedNodeContext get hostContext => RoutedNodeContext(
    info: const RoutedNodeRuntimeInfo(
      runtime: RoutedNodeRuntime.cloudflare,
      capabilities: cloudflareCapabilities,
    ),
    extension: FetchRuntimeExtension(
      runtime: RoutedNodeRuntime.cloudflare,
      environment: environment,
    ),
  );
}
