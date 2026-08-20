import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

import '../tool/src/live_d1_cli.dart';
import '../tool/src/live_d1_harness.dart';
import 'support/fake_cloudflare_d1.dart';

const _accountId = '0123456789abcdef0123456789abcdef';
const _databaseId = '01234567-89ab-cdef-0123-456789abcdef';
const _databaseName = 'routed-auth-conformance-existing';

void main() {
  group('live D1 harness lifecycle', () {
    test('creates, migrates, tests, and deletes in order', () async {
      final events = <String>[];
      final controlPlane = _FakeControlPlane(events: events);
      final report =
          await LiveD1ConformanceHarness(
            controlPlane: controlPlane,
            executor: _RecordingExecutor(events),
            clock: () => DateTime.utc(2026, 8, 20, 12, 30),
            random: Random(7),
          ).run(
            LiveD1ConformanceConfig(
              accountId: _accountId,
              target: const CreateDisposableLiveD1Target(),
            ),
          );

      expect(
        report.passed,
        isTrue,
        reason: report.results
            .where((result) => !result.passed)
            .map((result) => '${result.id}: ${result.error}')
            .join('\n'),
      );
      expect(events, ['create', 'connect', 'migrate', 'test', 'delete']);
      expect(controlPlane.deletedOwnership, isNotNull);
      expect(
        controlPlane.deletedOwnership!.databaseName,
        startsWith('routed-auth-conformance-20260820t123000z-'),
      );
    });

    test('deletes an owned database when tests fail', () async {
      final events = <String>[];
      final controlPlane = _FakeControlPlane(events: events);

      await expectLater(
        LiveD1ConformanceHarness(
          controlPlane: controlPlane,
          executor: _ThrowingExecutor(events, StateError('test failed')),
          random: Random(4),
        ).run(
          LiveD1ConformanceConfig(
            accountId: _accountId,
            target: const CreateDisposableLiveD1Target(),
          ),
        ),
        throwsA(
          isA<LiveD1RunFailure>()
              .having((error) => error.testFailure, 'testFailure', isNotNull)
              .having(
                (error) => error.cleanupFailure,
                'cleanupFailure',
                isNull,
              ),
        ),
      );
      expect(events, ['create', 'connect', 'test', 'delete']);
    });

    test('retains external databases and validates exact identity', () async {
      final events = <String>[];
      final controlPlane = _FakeControlPlane(events: events);
      await LiveD1ConformanceHarness(
        controlPlane: controlPlane,
        executor: _RecordingExecutor(events),
      ).run(
        LiveD1ConformanceConfig(
          accountId: _accountId,
          target: const ExternalLiveD1Target(
            databaseId: _databaseId,
            databaseName: _databaseName,
          ),
        ),
      );

      expect(events, ['get', 'connect', 'migrate', 'test']);
      expect(controlPlane.deletedOwnership, isNull);
    });

    test('refuses a mismatched external database', () async {
      final events = <String>[];
      final controlPlane = _FakeControlPlane(
        events: events,
        externalResource: const LiveD1DatabaseResource(
          id: _databaseId,
          name: 'different-database',
        ),
      );

      await expectLater(
        LiveD1ConformanceHarness(
          controlPlane: controlPlane,
          executor: _RecordingExecutor(events),
        ).run(
          LiveD1ConformanceConfig(
            accountId: _accountId,
            target: const ExternalLiveD1Target(
              databaseId: _databaseId,
              databaseName: _databaseName,
            ),
          ),
        ),
        throwsA(
          isA<LiveD1RunFailure>().having(
            (error) => error.testFailure.toString(),
            'testFailure',
            contains('exact configured database ID and name'),
          ),
        ),
      );
      expect(events, ['get']);
    });

    test('surfaces cleanup failure separately from test failure', () async {
      final events = <String>[];
      final controlPlane = _FakeControlPlane(
        events: events,
        deleteFailure: StateError('cleanup failed'),
      );

      await expectLater(
        LiveD1ConformanceHarness(
          controlPlane: controlPlane,
          executor: _ThrowingExecutor(events, StateError('test failed')),
          random: Random(9),
        ).run(
          LiveD1ConformanceConfig(
            accountId: _accountId,
            target: const CreateDisposableLiveD1Target(),
          ),
        ),
        throwsA(
          isA<LiveD1RunFailure>()
              .having(
                (error) => error.testFailure.toString(),
                'testFailure',
                contains('test failed'),
              )
              .having(
                (error) => error.cleanupFailure.toString(),
                'cleanupFailure',
                contains('cleanup failed'),
              ),
        ),
      );
      expect(events, ['create', 'connect', 'test', 'delete']);
    });

    test('classifies external test-table cleanup separately', () async {
      final events = <String>[];
      final controlPlane = _FakeControlPlane(events: events);

      await expectLater(
        LiveD1ConformanceHarness(
          controlPlane: controlPlane,
          executor: _ExecutorCleanupFailure(events),
        ).run(
          LiveD1ConformanceConfig(
            accountId: _accountId,
            target: const ExternalLiveD1Target(
              databaseId: _databaseId,
              databaseName: _databaseName,
            ),
          ),
        ),
        throwsA(
          isA<LiveD1RunFailure>()
              .having((error) => error.testFailure, 'testFailure', isNull)
              .having(
                (error) => error.cleanupFailure.toString(),
                'cleanupFailure',
                contains('table cleanup failed'),
              ),
        ),
      );
      expect(events, ['get', 'connect', 'test']);
      expect(controlPlane.deletedOwnership, isNull);
    });
  });

  group('default executor', () {
    test(
      'runs public and adapter-specific cases against the local D1 fake',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);

        final report = await DefaultLiveD1ConformanceExecutor(
          clock: () => DateTime.utc(2026, 8, 20),
          random: Random(11),
        ).run(database);

        expect(
          report.passed,
          isTrue,
          reason: report.results
              .where((result) => !result.passed)
              .map((result) => '${result.id}: ${result.error}')
              .join('\n'),
        );
        expect(
          report.results.map((result) => result.id),
          containsAll([
            'users.create-find',
            'sessions.rotation-contention',
            'scim.create_replay',
            'scim.rotate_atomic',
            'username.atomic',
            'oauth.authorization-code-exchange',
            'd1.batch-rollback',
            'd1.migration-prefix-isolation',
          ]),
        );
      },
    );
  });

  group('validation and non-mutating CLI defaults', () {
    test('requires exact identifiers and a reserved disposable prefix', () {
      expect(
        () => LiveD1ConformanceConfig(
          accountId: 'short',
          target: const CreateDisposableLiveD1Target(),
        ),
        throwsArgumentError,
      );
      expect(
        () => LiveD1ConformanceConfig(
          accountId: _accountId,
          target: const ExternalLiveD1Target(
            databaseId: 'not-a-uuid',
            databaseName: _databaseName,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => LiveD1ConformanceConfig(
          accountId: _accountId,
          target: const CreateDisposableLiveD1Target(namePrefix: 'production'),
        ),
        throwsArgumentError,
      );
    });

    test('does not construct a control plane without --live', () async {
      var constructed = false;
      final output = StringBuffer();
      final code = await runLiveD1ConformanceCli(
        const [],
        output: output,
        errorOutput: StringBuffer(),
        controlPlaneFactory: (token) {
          constructed = true;
          return _FakeControlPlane(events: []);
        },
      );

      expect(code, 0);
      expect(constructed, isFalse);
      expect(output.toString(), contains('no Cloudflare request was made'));
      expect(output.toString(), contains('--live'));
    });

    test('never accepts an API token as a command argument', () {
      expect(
        () => LiveD1CliOptions.parse(const ['--api-token', 'secret']),
        throwsFormatException,
      );
    });
  });

  group('Cloudflare API safety', () {
    test('adapts REST query results to the host-neutral D1 API', () async {
      final transport = _QueuedTransport([
        LiveD1ApiResponse(
          statusCode: 200,
          body: jsonEncode({
            'success': true,
            'result': [
              {
                'success': true,
                'results': [
                  {'value': 42},
                ],
                'meta': {'rows_read': 1, 'changes': 0},
              },
            ],
          }),
        ),
      ]);
      final database = CloudflareLiveD1ApiClient(
        apiToken: 'secret',
        transport: transport,
      ).connect(accountId: _accountId, databaseId: _databaseId);

      final value = await database
          .prepare('SELECT ? AS value')
          .bind([42])
          .first<int>(column: 'value');

      expect(value, 42);
      expect(transport.calls, 1);
      expect(jsonDecode(transport.bodies.single!), {
        'sql': 'SELECT ? AS value',
        'params': [42],
      });
    });

    test(
      'sends host-neutral D1 batches through the REST batch shape',
      () async {
        final transport = _QueuedTransport([
          LiveD1ApiResponse(
            statusCode: 200,
            body: jsonEncode({
              'success': true,
              'result': [
                {'success': true, 'results': <Object?>[]},
                {'success': true, 'results': <Object?>[]},
              ],
            }),
          ),
        ]);
        final database = CloudflareLiveD1ApiClient(
          apiToken: 'secret',
          transport: transport,
        ).connect(accountId: _accountId, databaseId: _databaseId);

        final results = await database.batch<Object?>([
          database.prepare('INSERT INTO probe VALUES (?)').bind([1]),
          database.prepare('INSERT INTO probe VALUES (?)').bind([2]),
        ]);

        expect(results, hasLength(2));
        expect(jsonDecode(transport.bodies.single!), {
          'batch': [
            {
              'sql': 'INSERT INTO probe VALUES (?)',
              'params': [1],
            },
            {
              'sql': 'INSERT INTO probe VALUES (?)',
              'params': [2],
            },
          ],
        });
      },
    );

    test('redacts tokens from bounded retry errors', () async {
      const token = 'very-secret-token-value';
      final transport = _QueuedTransport([
        for (var i = 0; i < 3; i++)
          LiveD1ApiResponse(
            statusCode: 503,
            body: jsonEncode({
              'success': false,
              'errors': [
                {'message': 'upstream echoed $token'},
              ],
            }),
          ),
      ]);
      final client = CloudflareLiveD1ApiClient(
        apiToken: token,
        transport: transport,
        delay: (_) async {},
      );

      await expectLater(
        client.getDatabase(accountId: _accountId, databaseId: _databaseId),
        throwsA(
          isA<LiveD1ApiException>()
              .having((error) => error.attempts, 'attempts', 3)
              .having(
                (error) => error.toString(),
                'message',
                allOf(contains('[REDACTED]'), isNot(contains(token))),
              ),
        ),
      );
      expect(transport.calls, 3);
    });

    test(
      'does not retry database creation after an ambiguous failure',
      () async {
        final transport = _QueuedTransport([
          const LiveD1ApiResponse(
            statusCode: 503,
            body: '{"success":false,"errors":[{"message":"busy"}]}',
          ),
        ]);
        final client = CloudflareLiveD1ApiClient(
          apiToken: 'secret',
          transport: transport,
          delay: (_) async {},
        );

        await expectLater(
          client.createDatabase(accountId: _accountId, name: _databaseName),
          throwsA(
            isA<LiveD1ApiException>().having(
              (error) => error.attempts,
              'attempts',
              1,
            ),
          ),
        );
        expect(transport.calls, 1);
      },
    );

    test(
      'refuses deletion when current resource differs from ownership',
      () async {
        final transport = _QueuedTransport([
          LiveD1ApiResponse(
            statusCode: 200,
            body: _resourceEnvelope(
              id: _databaseId,
              name: 'routed-auth-conformance-other-resource',
            ),
          ),
        ]);
        final client = CloudflareLiveD1ApiClient(
          apiToken: 'secret',
          transport: transport,
          delay: (_) async {},
        );

        await expectLater(
          client.deleteOwnedDatabase(
            const LiveD1DatabaseOwnership(
              accountId: _accountId,
              databaseId: _databaseId,
              databaseName:
                  'routed-auth-conformance-20260820t123000z-001122334455',
              generatedNamePrefix: 'routed-auth-conformance',
            ),
          ),
          throwsA(isA<StateError>()),
        );
        expect(transport.methods, ['GET']);
      },
    );

    test('bounds delete retries and accepts eventual success', () async {
      const ownedName = 'routed-auth-conformance-20260820t123000z-001122334455';
      final transport = _QueuedTransport([
        LiveD1ApiResponse(
          statusCode: 200,
          body: _resourceEnvelope(id: _databaseId, name: ownedName),
        ),
        const LiveD1ApiResponse(statusCode: 503, body: '{"success":false}'),
        const LiveD1ApiResponse(statusCode: 503, body: '{"success":false}'),
        const LiveD1ApiResponse(statusCode: 200, body: '{"success":true}'),
      ]);
      final client = CloudflareLiveD1ApiClient(
        apiToken: 'secret',
        transport: transport,
        delay: (_) async {},
      );

      await client.deleteOwnedDatabase(
        const LiveD1DatabaseOwnership(
          accountId: _accountId,
          databaseId: _databaseId,
          databaseName: ownedName,
          generatedNamePrefix: 'routed-auth-conformance',
        ),
      );
      expect(transport.methods, ['GET', 'DELETE', 'DELETE', 'DELETE']);
    });
  });
}

String _resourceEnvelope({required String id, required String name}) =>
    jsonEncode({
      'success': true,
      'result': {'uuid': id, 'name': name},
    });

final class _FakeControlPlane implements LiveD1ControlPlane {
  _FakeControlPlane({
    required this.events,
    this.externalResource = const LiveD1DatabaseResource(
      id: _databaseId,
      name: _databaseName,
    ),
    this.deleteFailure,
  });

  final List<String> events;
  final LiveD1DatabaseResource externalResource;
  final Object? deleteFailure;
  final FakeCloudflareD1Database database = FakeCloudflareD1Database();
  LiveD1DatabaseOwnership? deletedOwnership;

  @override
  Future<LiveD1DatabaseResource> createDatabase({
    required String accountId,
    required String name,
  }) async {
    events.add('create');
    return LiveD1DatabaseResource(id: _databaseId, name: name);
  }

  @override
  Future<LiveD1DatabaseResource?> getDatabase({
    required String accountId,
    required String databaseId,
  }) async {
    events.add('get');
    return externalResource;
  }

  @override
  CloudflareD1Database connect({
    required String accountId,
    required String databaseId,
  }) {
    events.add('connect');
    return database;
  }

  @override
  Future<void> deleteOwnedDatabase(LiveD1DatabaseOwnership ownership) async {
    events.add('delete');
    deletedOwnership = ownership;
    if (deleteFailure case final failure?) throw failure;
    database.close();
  }
}

final class _RecordingExecutor implements LiveD1ConformanceExecutor {
  const _RecordingExecutor(this.events);
  final List<String> events;

  @override
  Future<LiveD1ConformanceReport> run(CloudflareD1Database database) async {
    const schema = CloudflareD1AuthSchema(tablePrefix: 'live_recording');
    events.add('migrate');
    await schema.migrate(database);
    try {
      events.add('test');
      final store = CloudflareD1AuthStore(database, schema: schema);
      await store.users.create(AuthUser(id: 'recording-user'));
      return const LiveD1ConformanceReport([
        LiveD1ConformanceCaseResult(id: 'recording', passed: true),
      ]);
    } finally {
      await schema.dropAll(database);
    }
  }
}

final class _ThrowingExecutor implements LiveD1ConformanceExecutor {
  const _ThrowingExecutor(this.events, this.failure);
  final List<String> events;
  final Object failure;

  @override
  Future<LiveD1ConformanceReport> run(CloudflareD1Database database) async {
    events.add('test');
    throw failure;
  }
}

final class _ExecutorCleanupFailure implements LiveD1ConformanceExecutor {
  const _ExecutorCleanupFailure(this.events);
  final List<String> events;

  @override
  Future<LiveD1ConformanceReport> run(CloudflareD1Database database) async {
    events.add('test');
    throw LiveD1ExecutorCleanupFailure(
      cleanupFailure: StateError('table cleanup failed'),
    );
  }
}

final class _QueuedTransport implements LiveD1ApiTransport {
  _QueuedTransport(this.responses);

  final List<LiveD1ApiResponse> responses;
  final List<String> methods = [];
  final List<String?> bodies = [];
  int calls = 0;

  @override
  Future<LiveD1ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    methods.add(method);
    bodies.add(body);
    if (calls >= responses.length) {
      throw StateError('Unexpected transport call ${calls + 1}.');
    }
    return responses[calls++];
  }
}
