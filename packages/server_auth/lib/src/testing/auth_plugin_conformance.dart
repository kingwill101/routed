import '../core/plugin.dart';
import '../core/rate_limit.dart';
import '../core/runtime.dart';

/// The result of running one plugin-composition conformance case.
final class AuthPluginConformanceResult {
  const AuthPluginConformanceResult.passed();

  /// Whether the composed plugin topology satisfied this case.
  bool get isPassed => true;
}

/// A failed plugin-composition conformance case.
final class AuthPluginConformanceFailure implements Exception {
  /// Creates a failure for [caseId] caused by [cause].
  const AuthPluginConformanceFailure({
    required this.caseId,
    required this.cause,
  });

  /// Stable identifier of the failed case.
  final String caseId;

  /// The failed expectation or plugin exception.
  final Object cause;

  @override
  String toString() => 'AuthPluginConformanceFailure($caseId): $cause';
}

/// One independently runnable plugin-composition conformance case.
final class AuthPluginConformanceCase {
  const AuthPluginConformanceCase._({
    required this.id,
    required this.description,
    required Future<AuthPluginConformanceResult> Function() run,
  }) : _run = run;

  /// Stable machine-readable case identifier.
  final String id;

  /// Human-readable behavior covered by this case.
  final String description;

  final Future<AuthPluginConformanceResult> Function() _run;

  /// Runs this case against the captured, immutable runtime topology.
  Future<AuthPluginConformanceResult> run() => _run();
}

/// Framework-neutral contract suite for a composed auth plugin topology.
///
/// The suite depends only on public `server_auth` contracts and does not
/// depend on a test framework. It snapshots a frozen [AuthRuntime], so cases
/// may be registered with any runner and executed independently.
final class AuthPluginConformanceSuite<TContext> {
  /// Creates a suite for the plugins composed into [runtime].
  ///
  /// Every public endpoint must have a matching client operation. Use
  /// [publicEndpointClientExceptions] only for deliberate protocol or
  /// discovery endpoints, with a non-empty explanation for each omission.
  AuthPluginConformanceSuite.fromRuntime(
    AuthRuntime<TContext> runtime, {
    Map<String, String> publicEndpointClientExceptions =
        const <String, String>{},
  }) : _plugins = List<AuthServerPlugin<TContext>>.unmodifiable(
         runtime.plugins,
       ),
       _endpoints = List<AuthEndpointDescriptor<TContext>>.unmodifiable(
         runtime.registry.endpoints,
       ),
       _clientOperations = List<AuthClientOperationDescriptor>.unmodifiable(
         runtime.registry.clientOperations,
       ),
       _rateLimitOperations = List<AuthRateLimitOperation>.unmodifiable(
         runtime.registry.rateLimitOperations,
       ),
       _publicEndpointClientExceptions = Map<String, String>.unmodifiable(
         publicEndpointClientExceptions,
       );

  final List<AuthServerPlugin<TContext>> _plugins;
  final List<AuthEndpointDescriptor<TContext>> _endpoints;
  final List<AuthClientOperationDescriptor> _clientOperations;
  final List<AuthRateLimitOperation> _rateLimitOperations;
  final Map<String, String> _publicEndpointClientExceptions;

  /// Independently runnable cases in stable registration order.
  late final List<AuthPluginConformanceCase> cases =
      List<AuthPluginConformanceCase>.unmodifiable(<AuthPluginConformanceCase>[
        _case(
          id: 'composition.identifiers',
          description: 'uses stable unique plugin identifiers',
          verify: _verifyPluginIdentifiers,
        ),
        _case(
          id: 'endpoints.identifiers',
          description: 'uses stable unique endpoint identifiers and routes',
          verify: _verifyEndpointIdentifiers,
        ),
        _case(
          id: 'endpoints.typed-contracts',
          description: 'publishes typed request and response contracts',
          verify: _verifyTypedContracts,
        ),
        _case(
          id: 'rate-limits.references',
          description: 'matches endpoint rate limits to declared operations',
          verify: _verifyRateLimitReferences,
        ),
        _case(
          id: 'clients.public-endpoints',
          description: 'matches client operations to public endpoints',
          verify: _verifyClientOperations,
        ),
        _case(
          id: 'endpoints.mutation-protection',
          description: 'declares safe mutation protection metadata',
          verify: _verifyMutationProtection,
        ),
      ]);

  /// Selects cases by stable ID while preserving registration order.
  ///
  /// When [include] is omitted every case is eligible. Unknown include or
  /// exclude IDs throw, preventing a misspelled filter from silently skipping
  /// a contract.
  List<AuthPluginConformanceCase> filtered({
    Iterable<String>? include,
    Iterable<String> exclude = const <String>[],
  }) {
    final known = cases.map((value) => value.id).toSet();
    final included = include?.toSet();
    final excluded = exclude.toSet();
    final unknown = <String>{
      if (included != null) ...included.difference(known),
      ...excluded.difference(known),
    };
    if (unknown.isNotEmpty) {
      final sorted = unknown.toList()..sort();
      throw ArgumentError.value(sorted, 'include/exclude', 'unknown case IDs');
    }
    return List<AuthPluginConformanceCase>.unmodifiable(
      cases.where(
        (value) =>
            (included == null || included.contains(value.id)) &&
            !excluded.contains(value.id),
      ),
    );
  }

  AuthPluginConformanceCase _case({
    required String id,
    required String description,
    required void Function() verify,
  }) {
    return AuthPluginConformanceCase._(
      id: id,
      description: description,
      run: () async {
        try {
          verify();
        } catch (error, stackTrace) {
          Error.throwWithStackTrace(
            AuthPluginConformanceFailure(caseId: id, cause: error),
            stackTrace,
          );
        }
        return const AuthPluginConformanceResult.passed();
      },
    );
  }

  void _verifyPluginIdentifiers() {
    _verifyStableUniqueIds(
      _plugins.map((plugin) => plugin.id),
      label: 'plugin',
    );
  }

  void _verifyEndpointIdentifiers() {
    _verifyStableUniqueIds(
      _endpoints.map((endpoint) => endpoint.id),
      label: 'endpoint',
    );
    _verifyUniqueOperationKeys(
      _endpoints.map(
        (endpoint) => _OperationKey(
          id: endpoint.id,
          method: endpoint.method,
          path: endpoint.path,
        ),
      ),
      label: 'endpoint',
    );
  }

  void _verifyTypedContracts() {
    for (final endpoint in _endpoints) {
      final AuthEndpointContractDescriptor contract;
      if (endpoint case final AuthEndpointContractDescriptor value) {
        contract = value;
      } else {
        _fail('Endpoint "${endpoint.id}" has no typed operation contract.');
      }
      _verifyContract(contract.requestCodec, '${endpoint.id} request');
      _verifyContract(contract.responseCodec, '${endpoint.id} response');
    }
  }

  void _verifyRateLimitReferences() {
    _verifyStableUniqueIds(
      _rateLimitOperations.map((operation) => operation.id),
      label: 'rate-limit operation',
    );
    final declared = <String, AuthRateLimitOperation>{
      for (final operation in _rateLimitOperations) operation.id: operation,
    };
    final referenced = <String>{};
    for (final endpoint in _endpoints) {
      final operation = endpoint.rateLimitOperation;
      if (operation == null) continue;
      referenced.add(operation.id);
      if (declared[operation.id] != operation) {
        _fail(
          'Endpoint "${endpoint.id}" references undeclared rate-limit '
          'operation "${operation.id}".',
        );
      }
    }
    final unused = declared.keys.toSet().difference(referenced);
    if (unused.isNotEmpty) {
      final sorted = unused.toList()..sort();
      _fail(
        'Declared rate-limit operations are not used: ${sorted.join(', ')}.',
      );
    }
  }

  void _verifyClientOperations() {
    _verifyStableUniqueIds(
      _clientOperations.map((operation) => operation.id),
      label: 'client operation',
    );
    _verifyUniqueOperationKeys(
      _clientOperations.map(
        (operation) => _OperationKey(
          id: operation.id,
          method: operation.method,
          path: operation.path,
        ),
      ),
      label: 'client operation',
    );
    final endpoints = <String, AuthEndpointDescriptor<TContext>>{
      for (final endpoint in _endpoints) endpoint.id: endpoint,
    };
    final clients = <String, AuthClientOperationDescriptor>{
      for (final operation in _clientOperations) operation.id: operation,
    };
    for (final entry in _publicEndpointClientExceptions.entries) {
      final endpoint = endpoints[entry.key];
      if (endpoint == null || endpoint.serverOnly) {
        _fail(
          'Client exception "${entry.key}" does not reference a public '
          'endpoint.',
        );
      }
      if (entry.value.trim().isEmpty) {
        _fail('Client exception "${entry.key}" must explain the omission.');
      }
      if (clients.containsKey(entry.key)) {
        _fail(
          'Client exception "${entry.key}" is stale because the operation is '
          'published.',
        );
      }
    }
    for (final operation in _clientOperations) {
      final endpoint = endpoints[operation.id];
      if (endpoint == null || endpoint.serverOnly) {
        _fail(
          'Client operation "${operation.id}" does not reference a public '
          'endpoint.',
        );
      }
      if (endpoint.method != operation.method ||
          _canonicalPath(endpoint.path) != _canonicalPath(operation.path)) {
        _fail(
          'Client operation "${operation.id}" does not match its endpoint '
          'method and path.',
        );
      }
    }
    for (final endpoint in _endpoints.where((value) => !value.serverOnly)) {
      if (!clients.containsKey(endpoint.id) &&
          !_publicEndpointClientExceptions.containsKey(endpoint.id)) {
        _fail(
          'Public endpoint "${endpoint.id}" has no matching client operation '
          'or documented exception.',
        );
      }
    }
  }

  void _verifyMutationProtection() {
    for (final endpoint in _endpoints) {
      if (endpoint.method == AuthOperationMethod.get) {
        if (endpoint.csrfPolicy != AuthOperationCsrfPolicy.none) {
          _fail('GET endpoint "${endpoint.id}" must not require CSRF.');
        }
        continue;
      }

      final isBrowserProtected =
          endpoint.originPolicy == AuthOperationOriginPolicy.browser &&
          endpoint.csrfPolicy == AuthOperationCsrfPolicy.required;
      final isRateLimitedAnonymousBrowserMutation =
          endpoint.authentication == AuthOperationAuthentication.none &&
          endpoint.originPolicy == AuthOperationOriginPolicy.browser &&
          endpoint.csrfPolicy == AuthOperationCsrfPolicy.none &&
          endpoint.rateLimitOperation != null;
      final isNonBrowserMutation =
          endpoint.originPolicy == AuthOperationOriginPolicy.none &&
          endpoint.csrfPolicy == AuthOperationCsrfPolicy.none;
      if (!isBrowserProtected &&
          !isRateLimitedAnonymousBrowserMutation &&
          !isNonBrowserMutation) {
        _fail(
          'POST endpoint "${endpoint.id}" has inconsistent origin and CSRF '
          'metadata.',
        );
      }
      if (endpoint.serverOnly) continue;
      if (endpoint.authentication == AuthOperationAuthentication.session &&
          !isBrowserProtected) {
        _fail(
          'Session mutation "${endpoint.id}" must require browser origin and '
          'CSRF protection.',
        );
      }
      if (endpoint.authentication == AuthOperationAuthentication.none &&
          isNonBrowserMutation &&
          endpoint.rateLimitOperation == null) {
        _fail(
          'Anonymous mutation "${endpoint.id}" must declare a rate-limit '
          'operation when CSRF does not apply.',
        );
      }
    }
  }
}

void _verifyStableUniqueIds(Iterable<String> values, {required String label}) {
  final seen = <String>{};
  for (final value in values) {
    if (value != value.trim() || !_stableId.hasMatch(value)) {
      _fail('$label ID "$value" is not a stable identifier.');
    }
    if (!seen.add(value)) _fail('Duplicate $label ID "$value".');
  }
}

void _verifyUniqueOperationKeys(
  Iterable<_OperationKey> operations, {
  required String label,
}) {
  final seen = <String>{};
  for (final operation in operations) {
    final path = _canonicalPath(operation.path);
    if (operation.path != path) {
      _fail('$label "${operation.id}" path must be canonical: "$path".');
    }
    final key = '${operation.method.name}:$path';
    if (!seen.add(key)) _fail('Duplicate $label method and path "$key".');
  }
}

void _verifyContract(AuthOperationContract contract, String label) {
  final contentType = contract.contentType;
  if (contentType != contentType.trim() ||
      !contentType.contains('/') ||
      contentType.codeUnits.any((value) => value < 0x20 || value == 0x7f)) {
    _fail('$label has an invalid content type.');
  }
  _verifyJsonValue(contract.schema, '$label schema');
  final schema = contract.schema;
  if (schema.isEmpty) return;
  final type = schema['type'];
  if (type != null &&
      type is! String &&
      (type is! List ||
          type.isEmpty ||
          type.any((value) => value is! String))) {
    _fail('$label schema has an invalid "type".');
  }
  final required = schema['required'];
  if (required != null &&
      (required is! List || required.any((value) => value is! String))) {
    _fail('$label schema has an invalid "required" list.');
  }
  final properties = schema['properties'];
  if (properties != null && properties is! Map) {
    _fail('$label schema has invalid "properties".');
  }
}

void _verifyJsonValue(Object? value, String label) {
  if (value == null || value is bool || value is num || value is String) return;
  if (value is List) {
    for (var index = 0; index < value.length; index++) {
      _verifyJsonValue(value[index], '$label[$index]');
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) _fail('$label contains a non-string key.');
      _verifyJsonValue(entry.value, '$label.${entry.key}');
    }
    return;
  }
  _fail('$label contains non-JSON value ${value.runtimeType}.');
}

String _canonicalPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.contains('?') || trimmed.contains('#')) {
    _fail('Operation path "$value" must be an absolute path without a query.');
  }
  final body = trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
  return body.isEmpty ? '/' : '/$body';
}

Never _fail(String message) => throw _AuthPluginExpectationFailure(message);

final RegExp _stableId = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$');

final class _OperationKey {
  const _OperationKey({
    required this.id,
    required this.method,
    required this.path,
  });

  final String id;
  final AuthOperationMethod method;
  final String path;
}

final class _AuthPluginExpectationFailure implements Exception {
  const _AuthPluginExpectationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
