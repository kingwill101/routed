import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:server_auth/testing.dart';

const _disposablePrefix = 'routed-auth-conformance';

/// Identifies one D1 database returned by Cloudflare's control plane.
final class LiveD1DatabaseResource {
  const LiveD1DatabaseResource({required this.id, required this.name});

  final String id;
  final String name;
}

/// Proof that this process created a disposable D1 database.
final class LiveD1DatabaseOwnership {
  const LiveD1DatabaseOwnership({
    required this.accountId,
    required this.databaseId,
    required this.databaseName,
    required this.generatedNamePrefix,
  });

  final String accountId;
  final String databaseId;
  final String databaseName;
  final String generatedNamePrefix;
}

/// Selects either a newly created disposable database or an external target.
sealed class LiveD1Target {
  const LiveD1Target();
}

final class CreateDisposableLiveD1Target extends LiveD1Target {
  const CreateDisposableLiveD1Target({this.namePrefix = _disposablePrefix});

  final String namePrefix;
}

final class ExternalLiveD1Target extends LiveD1Target {
  const ExternalLiveD1Target({
    required this.databaseId,
    required this.databaseName,
  });

  final String databaseId;
  final String databaseName;
}

/// Validated configuration for one explicitly enabled live run.
final class LiveD1ConformanceConfig {
  LiveD1ConformanceConfig({required String accountId, required this.target})
    : accountId = validateCloudflareAccountId(accountId) {
    switch (target) {
      case CreateDisposableLiveD1Target(:final namePrefix):
        validateDisposableD1NamePrefix(namePrefix);
      case ExternalLiveD1Target(:final databaseId, :final databaseName):
        validateCloudflareD1DatabaseId(databaseId);
        validateCloudflareD1DatabaseName(databaseName);
    }
  }

  final String accountId;
  final LiveD1Target target;
}

String validateCloudflareAccountId(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'accountId',
      'must be the exact 32-character Cloudflare account identifier',
    );
  }
  return normalized;
}

String validateCloudflareD1DatabaseId(String value) {
  final normalized = value.trim();
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'databaseId',
      'must be the exact D1 database UUID',
    );
  }
  return normalized;
}

String validateCloudflareD1DatabaseName(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,62}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'databaseName',
      'must be an exact safe D1 database name of at most 63 characters',
    );
  }
  return normalized;
}

String validateDisposableD1NamePrefix(String value) {
  final normalized = value.trim();
  if (normalized.length > 33 ||
      !RegExp(
        r'^routed-auth-conformance(?:-[a-z0-9]+)*$',
      ).hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'namePrefix',
      'must start with routed-auth-conformance and contain only lowercase '
          'letters, digits, and hyphens',
    );
  }
  return normalized;
}

/// Generates a validated, collision-resistant disposable database name.
String generateDisposableD1DatabaseName({
  required String prefix,
  DateTime Function()? clock,
  Random? random,
}) {
  final validatedPrefix = validateDisposableD1NamePrefix(prefix);
  final now = (clock ?? DateTime.now)().toUtc();
  final source = random ?? Random.secure();
  final nonce = List<int>.generate(
    6,
    (_) => source.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${now.year.toString().padLeft(4, '0')}'
      '${two(now.month)}${two(now.day)}t'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}z';
  final name = '$validatedPrefix-$stamp-$nonce';
  validateCloudflareD1DatabaseName(name);
  return name;
}

/// Control-plane and host-neutral data-plane operations used by the harness.
abstract interface class LiveD1ControlPlane {
  Future<LiveD1DatabaseResource> createDatabase({
    required String accountId,
    required String name,
  });

  Future<LiveD1DatabaseResource?> getDatabase({
    required String accountId,
    required String databaseId,
  });

  CloudflareD1Database connect({
    required String accountId,
    required String databaseId,
  });

  /// Deletes only a database represented by creation-response ownership.
  Future<void> deleteOwnedDatabase(LiveD1DatabaseOwnership ownership);
}

final class LiveD1ConformanceCaseResult {
  const LiveD1ConformanceCaseResult({
    required this.id,
    required this.passed,
    this.skippedReason,
    this.error,
  });

  final String id;
  final bool passed;
  final String? skippedReason;
  final String? error;
}

final class LiveD1ConformanceReport {
  const LiveD1ConformanceReport(this.results);

  final List<LiveD1ConformanceCaseResult> results;
  bool get passed => results.every((result) => result.passed);
}

abstract interface class LiveD1ConformanceExecutor {
  Future<LiveD1ConformanceReport> run(CloudflareD1Database database);
}

/// Runs the public store contract plus D1-specific transaction probes.
final class DefaultLiveD1ConformanceExecutor
    implements LiveD1ConformanceExecutor {
  DefaultLiveD1ConformanceExecutor({DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random.secure();

  final DateTime Function() _clock;
  final Random _random;

  @override
  Future<LiveD1ConformanceReport> run(CloudflareD1Database database) async {
    final runId = _runIdentifier(_clock().toUtc(), _random);
    var fixtureIndex = 0;
    final activeSchemas = <CloudflareD1AuthSchema>{};

    Future<CloudflareD1AuthSchema> newSchema() async {
      final schema = CloudflareD1AuthSchema(
        tablePrefix: 'routed_auth_live_${runId}_${fixtureIndex++}',
      );
      activeSchemas.add(schema);
      await schema.migrate(database);
      return schema;
    }

    Future<void> disposeSchema(CloudflareD1AuthSchema schema) async {
      await schema.dropAll(database);
      activeSchemas.remove(schema);
    }

    final results = <LiveD1ConformanceCaseResult>[];
    LiveD1ConformanceReport? report;
    Object? executionFailure;
    StackTrace? executionStack;
    Object? cleanupFailure;
    StackTrace? cleanupStack;
    try {
      final suite = AuthStoreConformanceSuite(
        createFixture: () async {
          final schema = await newSchema();
          return AuthStoreConformanceFixture(
            store: CloudflareD1AuthStore(database, schema: schema),
            dispose: () => disposeSchema(schema),
          );
        },
      );
      for (final conformanceCase in suite.cases) {
        try {
          final result = await conformanceCase.run();
          results.add(
            LiveD1ConformanceCaseResult(
              id: conformanceCase.id,
              passed: true,
              skippedReason: result.skippedReason,
            ),
          );
        } catch (error) {
          results.add(
            LiveD1ConformanceCaseResult(
              id: conformanceCase.id,
              passed: false,
              error: _safeError(error),
            ),
          );
        }
      }

      final scimSuite = AuthScimConnectionStoreConformanceSuite(() async {
        final schema = await newSchema();
        final store = CloudflareD1AuthStore(database, schema: schema);
        return AuthScimConnectionStoreConformanceFixture(
          store: store.scimConnectionStore,
          dispose: () => disposeSchema(schema),
        );
      });
      for (final conformanceCase in scimSuite.cases) {
        final id = 'scim.${conformanceCase.id}';
        try {
          await conformanceCase.run();
          results.add(LiveD1ConformanceCaseResult(id: id, passed: true));
        } catch (error) {
          results.add(
            LiveD1ConformanceCaseResult(
              id: id,
              passed: false,
              error: _safeError(error),
            ),
          );
        }
      }

      final anonymousSuite = AuthAnonymousStoreConformanceSuite(() async {
        final schema = await newSchema();
        final store = CloudflareD1AuthStore(database, schema: schema);
        final plugin = AnonymousPlugin<Object>();
        plugin.configure(AuthServerPluginContext<Object>(store: store));
        store.bindUserDeletionPlanContributors([plugin]);
        return AuthAnonymousStoreConformanceFixture(
          store: store,
          mutations: store,
          faults: const _LiveD1AnonymousFaultController(),
          dispose: () => disposeSchema(schema),
        );
      });
      for (final conformanceCase in anonymousSuite.cases.where(
        (candidate) => !candidate.id.endsWith('_rollback'),
      )) {
        final id = 'anonymous.${conformanceCase.id}';
        try {
          await conformanceCase.run();
          results.add(LiveD1ConformanceCaseResult(id: id, passed: true));
        } catch (error) {
          results.add(
            LiveD1ConformanceCaseResult(
              id: id,
              passed: false,
              error: _safeError(error),
            ),
          );
        }
      }

      results.add(
        await _runAdapterCase('username.atomic', () async {
          final schema = await newSchema();
          try {
            await verifyAuthUsernameStoreConformance(
              AuthUsernameStoreConformanceFixture(
                store: CloudflareD1AuthStore(database, schema: schema),
              ),
            );
          } finally {
            await disposeSchema(schema);
          }
        }),
      );
      results.add(
        await _runAdapterCase('oauth.authorization-code-exchange', () async {
          await verifyOAuthAuthorizationCodeExchangeStoreConformance(() async {
            final schema = await newSchema();
            return CloudflareD1AuthStore(
              database,
              schema: schema,
            ).oauthAuthorizationCodeExchangeStore;
          });
        }),
      );

      results.add(
        await _runAdapterCase(
          'd1.batch-rollback',
          () => _verifyBatchRollback(database, newSchema, disposeSchema),
        ),
      );
      results.add(
        await _runAdapterCase(
          'd1.migration-prefix-isolation',
          () => _verifyMigrationIsolation(database, newSchema, disposeSchema),
        ),
      );
      report = LiveD1ConformanceReport(List.unmodifiable(results));
    } catch (error, stackTrace) {
      executionFailure = error;
      executionStack = stackTrace;
    } finally {
      for (final schema in activeSchemas.toList().reversed) {
        try {
          await schema.dropAll(database);
        } catch (error, stackTrace) {
          cleanupFailure ??= error;
          cleanupStack ??= stackTrace;
        }
      }
    }
    if (cleanupFailure != null) {
      Error.throwWithStackTrace(
        LiveD1ExecutorCleanupFailure(
          executionFailure: executionFailure,
          failedReport: report?.passed == false ? report : null,
          cleanupFailure: cleanupFailure,
        ),
        cleanupStack!,
      );
    }
    if (executionFailure != null) {
      Error.throwWithStackTrace(executionFailure, executionStack!);
    }
    return report!;
  }

  static Future<LiveD1ConformanceCaseResult> _runAdapterCase(
    String id,
    Future<void> Function() body,
  ) async {
    try {
      await body();
      return LiveD1ConformanceCaseResult(id: id, passed: true);
    } catch (error) {
      return LiveD1ConformanceCaseResult(
        id: id,
        passed: false,
        error: _safeError(error),
      );
    }
  }

  static Future<void> _verifyBatchRollback(
    CloudflareD1Database database,
    Future<CloudflareD1AuthSchema> Function() newSchema,
    Future<void> Function(CloudflareD1AuthSchema) disposeSchema,
  ) async {
    final schema = await newSchema();
    final table = schema.table('users');
    try {
      var rejected = false;
      try {
        final batch = await database.batch<Object?>([
          database
              .prepare(
                'INSERT INTO $table (id, email, payload) VALUES (?, ?, ?)',
              )
              .bind(['probe-user', 'probe-one@example.com', '{}']),
          database
              .prepare(
                'INSERT INTO $table (id, email, payload) VALUES (?, ?, ?)',
              )
              .bind(['probe-user', 'probe-two@example.com', '{}']),
        ]);
        rejected = batch.any((result) => !result.success);
      } catch (_) {
        rejected = true;
      }
      if (!rejected) {
        throw StateError('D1 accepted a transaction with a duplicate key.');
      }
      final result = await database
          .prepare('SELECT COUNT(*) AS row_count FROM $table')
          .all<int>(decode: (row) => (row['row_count'] as num).toInt());
      if (!result.success || result.results.single != 0) {
        throw StateError('D1 retained writes from a rejected batch.');
      }
    } finally {
      await disposeSchema(schema);
    }
  }

  static Future<void> _verifyMigrationIsolation(
    CloudflareD1Database database,
    Future<CloudflareD1AuthSchema> Function() newSchema,
    Future<void> Function(CloudflareD1AuthSchema) disposeSchema,
  ) async {
    final first = await newSchema();
    final second = await newSchema();
    try {
      await first.migrate(database);
      final firstStore = CloudflareD1AuthStore(database, schema: first);
      final secondStore = CloudflareD1AuthStore(database, schema: second);
      await firstStore.users.create(
        AuthUser(id: 'isolation-user', email: 'isolation@example.com'),
      );
      if (await secondStore.users.findById('isolation-user') != null) {
        throw StateError('D1 auth schema prefixes shared user rows.');
      }
    } finally {
      await disposeSchema(second);
      await disposeSchema(first);
    }
  }
}

final class _LiveD1AnonymousFaultController
    implements AuthAnonymousStoreConformanceFaultController {
  const _LiveD1AnonymousFaultController();

  @override
  void failNext(AuthAnonymousStoreConformanceFaultPoint point) {
    throw StateError('Live D1 rollback fault injection is not configured.');
  }
}

String _runIdentifier(DateTime now, Random random) {
  final seconds = now.microsecondsSinceEpoch.toRadixString(36);
  final nonce = List<int>.generate(
    4,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${seconds}_$nonce';
}

String _safeError(Object error) {
  final value = error.toString();
  return value.length <= 500 ? value : '${value.substring(0, 500)}...';
}

final class LiveD1ConformanceFailure implements Exception {
  const LiveD1ConformanceFailure(this.report);

  final LiveD1ConformanceReport report;

  @override
  String toString() => 'One or more live D1 conformance cases failed.';
}

/// A schema cleanup failure, kept distinct from conformance failures.
final class LiveD1ExecutorCleanupFailure implements Exception {
  const LiveD1ExecutorCleanupFailure({
    required this.cleanupFailure,
    this.executionFailure,
    this.failedReport,
  });

  final Object cleanupFailure;
  final Object? executionFailure;
  final LiveD1ConformanceReport? failedReport;

  @override
  String toString() => 'Live D1 test-table cleanup failed.';
}

final class LiveD1CleanupFailureGroup implements Exception {
  const LiveD1CleanupFailureGroup(this.failures);

  final List<Object> failures;

  @override
  String toString() => failures.map((failure) => failure.toString()).join('; ');
}

/// Preserves a test failure and a separately reportable cleanup failure.
final class LiveD1RunFailure implements Exception {
  const LiveD1RunFailure({this.testFailure, this.cleanupFailure});

  final Object? testFailure;
  final Object? cleanupFailure;

  @override
  String toString() {
    final parts = <String>[];
    if (testFailure != null) parts.add('test failure: $testFailure');
    if (cleanupFailure != null) parts.add('cleanup failure: $cleanupFailure');
    return 'LiveD1RunFailure(${parts.join(', ')})';
  }
}

/// Owns the create/verify/run/delete lifecycle for one live D1 run.
final class LiveD1ConformanceHarness {
  LiveD1ConformanceHarness({
    required LiveD1ControlPlane controlPlane,
    LiveD1ConformanceExecutor? executor,
    DateTime Function()? clock,
    Random? random,
  }) : _controlPlane = controlPlane,
       _executor = executor ?? DefaultLiveD1ConformanceExecutor(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final LiveD1ControlPlane _controlPlane;
  final LiveD1ConformanceExecutor _executor;
  final DateTime Function() _clock;
  final Random _random;

  Future<LiveD1ConformanceReport> run(LiveD1ConformanceConfig config) async {
    LiveD1DatabaseOwnership? ownership;
    LiveD1DatabaseResource resource;
    Object? testFailure;
    StackTrace? testStack;
    Object? executionCleanupFailure;
    LiveD1ConformanceReport? report;

    try {
      switch (config.target) {
        case CreateDisposableLiveD1Target(:final namePrefix):
          final name = generateDisposableD1DatabaseName(
            prefix: namePrefix,
            clock: _clock,
            random: _random,
          );
          resource = await _controlPlane.createDatabase(
            accountId: config.accountId,
            name: name,
          );
          if (resource.name != name) {
            throw StateError(
              'Cloudflare create response did not preserve the exact '
              'disposable database name.',
            );
          }
          validateCloudflareD1DatabaseId(resource.id);
          ownership = LiveD1DatabaseOwnership(
            accountId: config.accountId,
            databaseId: resource.id,
            databaseName: resource.name,
            generatedNamePrefix: namePrefix,
          );
        case ExternalLiveD1Target(:final databaseId, :final databaseName):
          final found = await _controlPlane.getDatabase(
            accountId: config.accountId,
            databaseId: databaseId,
          );
          if (found == null ||
              found.id != databaseId ||
              found.name != databaseName) {
            throw StateError(
              'The external D1 target did not match the exact configured '
              'database ID and name.',
            );
          }
          resource = found;
      }

      final database = _controlPlane.connect(
        accountId: config.accountId,
        databaseId: resource.id,
      );
      report = await _executor.run(database);
      if (!report.passed) throw LiveD1ConformanceFailure(report);
    } catch (error, stackTrace) {
      if (error is LiveD1ExecutorCleanupFailure) {
        executionCleanupFailure = error.cleanupFailure;
        testFailure = error.executionFailure;
        final failedReport = error.failedReport;
        if (testFailure == null && failedReport != null) {
          testFailure = LiveD1ConformanceFailure(failedReport);
        }
      } else {
        testFailure = error;
      }
      testStack = stackTrace;
    } finally {
      final cleanupFailures = <Object>[?executionCleanupFailure];
      StackTrace? cleanupStack;
      if (ownership != null) {
        try {
          await _controlPlane.deleteOwnedDatabase(ownership);
        } catch (error, stackTrace) {
          cleanupFailures.add(error);
          cleanupStack = stackTrace;
        }
      }
      final cleanupFailure = switch (cleanupFailures) {
        [] => null,
        [final failure] => failure,
        final failures => LiveD1CleanupFailureGroup(
          List<Object>.unmodifiable(failures),
        ),
      };
      if (testFailure != null || cleanupFailure != null) {
        final failure = LiveD1RunFailure(
          testFailure: testFailure,
          cleanupFailure: cleanupFailure,
        );
        Error.throwWithStackTrace(
          failure,
          cleanupStack ?? testStack ?? StackTrace.current,
        );
      }
    }
    return report!;
  }
}

final class LiveD1ApiResponse {
  const LiveD1ApiResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

abstract interface class LiveD1ApiTransport {
  Future<LiveD1ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  });
}

final class IoLiveD1ApiTransport implements LiveD1ApiTransport {
  IoLiveD1ApiTransport([HttpClient? client]) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<LiveD1ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });
    return LiveD1ApiResponse(
      statusCode: response.statusCode,
      body: responseBody,
      headers: responseHeaders,
    );
  }

  void close() => _client.close(force: true);
}

final class LiveD1ApiException implements Exception {
  const LiveD1ApiException({
    required this.operation,
    required this.statusCode,
    required this.message,
    required this.attempts,
  });

  final String operation;
  final int? statusCode;
  final String message;
  final int attempts;

  @override
  String toString() =>
      'LiveD1ApiException($operation, status: ${statusCode ?? 'network'}, '
      'attempts: $attempts): $message';
}

/// Non-interactive Cloudflare API client and D1 REST data-plane adapter.
final class CloudflareLiveD1ApiClient implements LiveD1ControlPlane {
  CloudflareLiveD1ApiClient({
    required String apiToken,
    LiveD1ApiTransport? transport,
    this.maxSafeAttempts = 3,
    this.maxRetryDelay = const Duration(seconds: 2),
    this.requestTimeout = const Duration(seconds: 30),
    Future<void> Function(Duration)? delay,
    Uri? apiBase,
  }) : _apiToken = _requireToken(apiToken),
       _transport = transport ?? IoLiveD1ApiTransport(),
       _delay = delay ?? Future<void>.delayed,
       _apiBase =
           apiBase ?? Uri.parse('https://api.cloudflare.com/client/v4/') {
    if (maxSafeAttempts < 1 || maxSafeAttempts > 5) {
      throw ArgumentError.value(
        maxSafeAttempts,
        'maxSafeAttempts',
        'must be between 1 and 5',
      );
    }
    if (maxRetryDelay < Duration.zero ||
        maxRetryDelay > const Duration(seconds: 10)) {
      throw ArgumentError.value(
        maxRetryDelay,
        'maxRetryDelay',
        'must be between zero and 10 seconds',
      );
    }
    if (requestTimeout < const Duration(seconds: 1) ||
        requestTimeout > const Duration(minutes: 2)) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be between one second and two minutes',
      );
    }
  }

  final String _apiToken;
  final LiveD1ApiTransport _transport;
  final Future<void> Function(Duration) _delay;
  final Uri _apiBase;
  final int maxSafeAttempts;
  final Duration maxRetryDelay;
  final Duration requestTimeout;

  void close() {
    final transport = _transport;
    if (transport is IoLiveD1ApiTransport) transport.close();
  }

  static String _requireToken(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty || RegExp(r'\s').hasMatch(normalized)) {
      throw ArgumentError(
        'apiToken must be non-empty and contain no whitespace.',
      );
    }
    return normalized;
  }

  @override
  Future<LiveD1DatabaseResource> createDatabase({
    required String accountId,
    required String name,
  }) async {
    final account = validateCloudflareAccountId(accountId);
    final exactName = validateCloudflareD1DatabaseName(name);
    final envelope = await _requestJson(
      operation: 'create D1 database',
      method: 'POST',
      path: 'accounts/$account/d1/database',
      body: {'name': exactName},
      retrySafe: false,
    );
    return _resource(envelope['result'], operation: 'create D1 database');
  }

  @override
  Future<LiveD1DatabaseResource?> getDatabase({
    required String accountId,
    required String databaseId,
  }) async {
    final account = validateCloudflareAccountId(accountId);
    final id = validateCloudflareD1DatabaseId(databaseId);
    final envelope = await _requestJson(
      operation: 'get D1 database',
      method: 'GET',
      path: 'accounts/$account/d1/database/$id',
      retrySafe: true,
      allowNotFound: true,
    );
    if (envelope.isEmpty) return null;
    return _resource(envelope['result'], operation: 'get D1 database');
  }

  @override
  CloudflareD1Database connect({
    required String accountId,
    required String databaseId,
  }) => _RestCloudflareD1Database(
    client: this,
    accountId: validateCloudflareAccountId(accountId),
    databaseId: validateCloudflareD1DatabaseId(databaseId),
  );

  @override
  Future<void> deleteOwnedDatabase(LiveD1DatabaseOwnership ownership) async {
    final account = validateCloudflareAccountId(ownership.accountId);
    final id = validateCloudflareD1DatabaseId(ownership.databaseId);
    final name = validateCloudflareD1DatabaseName(ownership.databaseName);
    final prefix = validateDisposableD1NamePrefix(
      ownership.generatedNamePrefix,
    );
    if (!name.startsWith('$prefix-')) {
      throw StateError(
        'Refusing D1 cleanup because the owned name no longer has the '
        'generated disposable prefix.',
      );
    }
    final current = await getDatabase(accountId: account, databaseId: id);
    if (current == null) return;
    if (current.id != id || current.name != name) {
      throw StateError(
        'Refusing D1 cleanup because the current resource does not match '
        'creation-response ownership.',
      );
    }
    await _requestJson(
      operation: 'delete owned D1 database',
      method: 'DELETE',
      path: 'accounts/$account/d1/database/$id',
      retrySafe: true,
      allowNotFound: true,
    );
  }

  Future<List<CloudflareD1Result<Map<String, Object?>>>> _query({
    required String accountId,
    required String databaseId,
    required List<_RestD1Statement> statements,
  }) async {
    final body = statements.length == 1
        ? statements.single.toJson()
        : {
            'batch': [for (final statement in statements) statement.toJson()],
          };
    final envelope = await _requestJson(
      operation: 'query D1 database',
      method: 'POST',
      path: 'accounts/$accountId/d1/database/$databaseId/query',
      body: body,
      retrySafe: false,
    );
    final rawResult = envelope['result'];
    if (rawResult is! List) {
      throw StateError('Cloudflare D1 query returned no result list.');
    }
    return [
      for (final value in rawResult)
        _decodeD1Result(value, operation: 'query D1 database'),
    ];
  }

  Future<Map<String, Object?>> _requestJson({
    required String operation,
    required String method,
    required String path,
    Object? body,
    required bool retrySafe,
    bool allowNotFound = false,
  }) async {
    final attempts = retrySafe ? maxSafeAttempts : 1;
    Object? lastError;
    int? lastStatus;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final response = await _transport
            .send(
              method: method,
              uri: _apiBase.resolve(path),
              headers: {
                HttpHeaders.authorizationHeader: 'Bearer $_apiToken',
                HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
                HttpHeaders.acceptHeader: ContentType.json.mimeType,
              },
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(requestTimeout);
        lastStatus = response.statusCode;
        if (allowNotFound && response.statusCode == HttpStatus.notFound) {
          return const {};
        }
        final decoded = _decodeEnvelope(response.body);
        final successful =
            response.statusCode >= 200 &&
            response.statusCode < 300 &&
            decoded['success'] == true;
        if (successful) return decoded;
        lastError = _apiErrorMessage(decoded, response.body);
        if (!retrySafe ||
            !_retryableStatus(response.statusCode) ||
            attempt == attempts) {
          throw LiveD1ApiException(
            operation: operation,
            statusCode: response.statusCode,
            message: redactLiveD1Secrets(lastError.toString(), [_apiToken]),
            attempts: attempt,
          );
        }
        await _delay(_retryDelay(response, attempt));
      } on LiveD1ApiException {
        rethrow;
      } on SocketException catch (error) {
        lastError = error.message;
        if (!retrySafe || attempt == attempts) {
          throw LiveD1ApiException(
            operation: operation,
            statusCode: null,
            message: redactLiveD1Secrets(error.message, [_apiToken]),
            attempts: attempt,
          );
        }
        await _delay(_boundedDelay(attempt));
      } on HttpException catch (error) {
        lastError = error.message;
        if (!retrySafe || attempt == attempts) {
          throw LiveD1ApiException(
            operation: operation,
            statusCode: null,
            message: redactLiveD1Secrets(error.message, [_apiToken]),
            attempts: attempt,
          );
        }
        await _delay(_boundedDelay(attempt));
      } on TimeoutException {
        lastError = 'Cloudflare API request timed out.';
        if (!retrySafe || attempt == attempts) {
          throw LiveD1ApiException(
            operation: operation,
            statusCode: null,
            message: lastError.toString(),
            attempts: attempt,
          );
        }
        await _delay(_boundedDelay(attempt));
      }
    }
    throw LiveD1ApiException(
      operation: operation,
      statusCode: lastStatus,
      message: redactLiveD1Secrets('$lastError', [_apiToken]),
      attempts: attempts,
    );
  }

  Duration _retryDelay(LiveD1ApiResponse response, int attempt) {
    final raw = response.headers['retry-after'];
    final seconds = raw == null ? null : int.tryParse(raw);
    if (seconds != null) {
      final requested = Duration(seconds: seconds);
      return requested > maxRetryDelay ? maxRetryDelay : requested;
    }
    return _boundedDelay(attempt);
  }

  Duration _boundedDelay(int attempt) {
    final milliseconds = 100 * (1 << (attempt - 1));
    final proposed = Duration(milliseconds: milliseconds);
    return proposed > maxRetryDelay ? maxRetryDelay : proposed;
  }

  static bool _retryableStatus(int status) =>
      status == HttpStatus.tooManyRequests ||
      status == HttpStatus.internalServerError ||
      status == HttpStatus.badGateway ||
      status == HttpStatus.serviceUnavailable ||
      status == HttpStatus.gatewayTimeout;
}

Map<String, Object?> _decodeEnvelope(String body) {
  if (body.trim().isEmpty) return const {'success': true};
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Cloudflare API returned a non-object body.');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

String _apiErrorMessage(Map<String, Object?> envelope, String fallback) {
  final errors = envelope['errors'];
  if (errors is List && errors.isNotEmpty) {
    return errors
        .map((value) => value is Map ? value['message'] : value)
        .whereType<Object>()
        .join('; ');
  }
  return fallback.trim().isEmpty ? 'Cloudflare API request failed.' : fallback;
}

LiveD1DatabaseResource _resource(Object? value, {required String operation}) {
  if (value is! Map) {
    throw StateError('$operation returned no database resource.');
  }
  final id = value['uuid'];
  final name = value['name'];
  if (id is! String || name is! String) {
    throw StateError('$operation returned an incomplete database resource.');
  }
  return LiveD1DatabaseResource(
    id: validateCloudflareD1DatabaseId(id),
    name: validateCloudflareD1DatabaseName(name),
  );
}

CloudflareD1Result<Map<String, Object?>> _decodeD1Result(
  Object? value, {
  required String operation,
}) {
  if (value is! Map) throw StateError('$operation returned an invalid result.');
  final rows = value['results'];
  final meta = value['meta'];
  return CloudflareD1Result<Map<String, Object?>>(
    success: value['success'] == true,
    results: rows is List
        ? [
            for (final row in rows)
              if (row is Map)
                row.map((key, cell) => MapEntry(key.toString(), cell)),
          ]
        : const [],
    meta: meta is Map ? _decodeD1Meta(meta) : null,
    error: value['error'],
  );
}

CloudflareD1Meta _decodeD1Meta(Map<dynamic, dynamic> meta) => CloudflareD1Meta(
  duration: meta['duration'] as num?,
  rowsRead: (meta['rows_read'] as num?)?.toInt(),
  rowsWritten: (meta['rows_written'] as num?)?.toInt(),
  changes: (meta['changes'] as num?)?.toInt(),
  changedDb: meta['changed_db'] as bool?,
  sizeAfter: (meta['size_after'] as num?)?.toInt(),
  lastRowId: meta['last_row_id'],
  servedBy: meta['served_by'] as String?,
  servedByColo: meta['served_by_colo'] as String?,
  servedByPrimary: meta['served_by_primary'] as bool?,
  servedByRegion: meta['served_by_region'] as String?,
  servedByLocation: meta['served_by_location'] as String?,
  bookmark: meta['bookmark'] as String?,
);

String redactLiveD1Secrets(String value, Iterable<String> secrets) {
  var redacted = value.replaceAll(
    RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
    'Bearer [REDACTED]',
  );
  for (final secret in secrets) {
    final normalized = secret.trim();
    if (normalized.isNotEmpty) {
      redacted = redacted.replaceAll(normalized, '[REDACTED]');
    }
  }
  return redacted;
}

final class _RestD1Statement {
  const _RestD1Statement(this.sql, this.params);

  final String sql;
  final List<Object?> params;

  Map<String, Object?> toJson() => {'sql': sql, 'params': params};
}

final class _RestCloudflareD1Database implements CloudflareD1Database {
  const _RestCloudflareD1Database({
    required this.client,
    required this.accountId,
    required this.databaseId,
  });

  final CloudflareLiveD1ApiClient client;
  final String accountId;
  final String databaseId;

  @override
  CloudflareD1PreparedStatement prepare(String query) =>
      _RestCloudflareD1PreparedStatement(
        this,
        _RestD1Statement(query, const []),
      );

  @override
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    final typed = statements.toList(growable: false);
    if (typed.any(
      (statement) =>
          statement is! _RestCloudflareD1PreparedStatement ||
          !identical(statement.database, this),
    )) {
      throw ArgumentError('D1 batch statements must belong to this database.');
    }
    final results = await client._query(
      accountId: accountId,
      databaseId: databaseId,
      statements: [
        for (final statement
            in typed.cast<_RestCloudflareD1PreparedStatement>())
          statement.statement,
      ],
    );
    return [for (final result in results) _decodeResult(result, decode)];
  }

  @override
  Future<CloudflareD1ExecResult> exec(String query) async {
    final results = await client._query(
      accountId: accountId,
      databaseId: databaseId,
      statements: [_RestD1Statement(query, const [])],
    );
    return CloudflareD1ExecResult(
      count: results.length,
      duration: results.fold<num>(
        0,
        (total, result) => total + (result.meta?.duration ?? 0),
      ),
    );
  }

  @override
  Future<Uint8List> dump() => throw UnsupportedError(
    'D1 dump is not available through the conformance REST adapter.',
  );

  @override
  CloudflareD1DatabaseSession withSession({String? bookmark}) =>
      throw UnsupportedError(
        'D1 REST conformance runs do not emulate Worker binding sessions.',
      );
}

final class _RestCloudflareD1PreparedStatement
    implements CloudflareD1PreparedStatement {
  const _RestCloudflareD1PreparedStatement(this.database, this.statement);

  final _RestCloudflareD1Database database;
  final _RestD1Statement statement;

  @override
  CloudflareD1PreparedStatement bind([Iterable<Object?> values = const []]) =>
      _RestCloudflareD1PreparedStatement(
        database,
        _RestD1Statement(statement.sql, values.toList(growable: false)),
      );

  Future<CloudflareD1Result<T>> _execute<T>(
    CloudflareD1RowDecoder<T>? decode,
  ) async {
    final results = await database.client._query(
      accountId: database.accountId,
      databaseId: database.databaseId,
      statements: [statement],
    );
    if (results.length != 1) {
      throw StateError('Cloudflare D1 returned an unexpected result count.');
    }
    return _decodeResult(results.single, decode);
  }

  @override
  Future<CloudflareD1Result<T>> all<T>({CloudflareD1RowDecoder<T>? decode}) =>
      _execute(decode);

  @override
  Future<T?> first<T>({
    String? column,
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    if (column == null) {
      final result = await _execute<T>(decode);
      return result.results.firstOrNull;
    }
    final result = await _execute<Map<String, Object?>>((row) => row);
    return result.results.firstOrNull?[column] as T?;
  }

  @override
  Future<List<T>> raw<T>({CloudflareD1RowDecoder<T>? decode}) async =>
      (await _execute<T>(decode)).results;

  @override
  Future<CloudflareD1Result<T>> run<T>({CloudflareD1RowDecoder<T>? decode}) =>
      _execute(decode);
}

CloudflareD1Result<T> _decodeResult<T>(
  CloudflareD1Result<Map<String, Object?>> result,
  CloudflareD1RowDecoder<T>? decode,
) => CloudflareD1Result<T>(
  success: result.success,
  results: [
    for (final row in result.results) decode == null ? row as T : decode(row),
  ],
  meta: result.meta,
  error: result.error,
);
