import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/client.dart';
import '../core/plugin.dart';
import '../core/rate_limit.dart';
import '../core/runtime.dart';

/// One HTTP response used to exercise an installed client operation.
final class AuthClientConformanceResponse {
  /// Creates a JSON response.
  const AuthClientConformanceResponse.json(
    Object? body, {
    this.statusCode = 200,
    this.headers = const <String, String>{},
  }) : _jsonBody = body,
       _rawBody = null;

  /// Creates a raw response, useful for malformed-codec cases.
  const AuthClientConformanceResponse.raw(
    String body, {
    this.statusCode = 200,
    this.headers = const <String, String>{},
  }) : _rawBody = body,
       _jsonBody = null;

  final Object? _jsonBody;
  final String? _rawBody;

  /// HTTP status returned to the installed client operation.
  final int statusCode;

  /// HTTP response headers returned to the installed client operation.
  final Map<String, String> headers;

  String get _body => _rawBody ?? jsonEncode(_jsonBody);
}

/// Invokes one operation through the typed API installed by a client plugin.
typedef AuthInstalledClientOperationInvoker =
    FutureOr<Object?> Function(Object api);

/// Validates the value decoded by an installed client operation.
typedef AuthInstalledClientResponseVerifier = void Function(Object? value);

/// Executable conformance contract for one installed client operation.
///
/// Unlike [AuthClientOperationDescriptor], this contract does not trust a
/// server plugin's declaration as evidence that a client exists. The suite
/// installs [plugin] through [AuthClientPluginContext], calls [invoke] on the
/// resulting typed API, captures the real transport request, and feeds the
/// client both valid and malformed responses.
final class AuthInstalledClientOperationContract {
  const AuthInstalledClientOperationContract({
    required this.endpointId,
    required this.plugin,
    required this.invoke,
    required this.response,
    this.verifyResponse,
    this.malformedResponses = const <AuthClientConformanceResponse>[],
    this.sensitiveValues = const <String>[],
  });

  /// Server endpoint operation ID expected to own the client operation.
  final String endpointId;

  /// Independently selected client plugin that exposes the typed API.
  final AuthClientPlugin<Object> plugin;

  /// Representative call made against the installed typed API.
  final AuthInstalledClientOperationInvoker invoke;

  /// Successful response accepted by both server and client codecs.
  final AuthClientConformanceResponse response;

  /// Optional semantic check for the decoded public result.
  final AuthInstalledClientResponseVerifier? verifyResponse;

  /// Responses that the installed client codec must reject.
  final List<AuthClientConformanceResponse> malformedResponses;

  /// Secrets that must not appear in public result serialization or failures.
  final List<String> sensitiveValues;
}

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
    Iterable<AuthInstalledClientOperationContract> installedClientOperations =
        const <AuthInstalledClientOperationContract>[],
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
       ),
       _installedClientOperations =
           List<AuthInstalledClientOperationContract>.unmodifiable(
             installedClientOperations,
           );

  final List<AuthServerPlugin<TContext>> _plugins;
  final List<AuthEndpointDescriptor<TContext>> _endpoints;
  final List<AuthClientOperationDescriptor> _clientOperations;
  final List<AuthRateLimitOperation> _rateLimitOperations;
  final Map<String, String> _publicEndpointClientExceptions;
  final List<AuthInstalledClientOperationContract> _installedClientOperations;

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
          id: 'clients.installed-contracts',
          description: 'executes installed client operations and codecs',
          verify: _verifyInstalledClientOperations,
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
    required FutureOr<void> Function() verify,
  }) {
    return AuthPluginConformanceCase._(
      id: id,
      description: description,
      run: () async {
        try {
          await Future<void>.sync(verify);
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

  Future<void> _verifyInstalledClientOperations() async {
    _verifyStableUniqueIds(
      _installedClientOperations.map((operation) => operation.endpointId),
      label: 'installed client operation',
    );
    final endpoints = <String, AuthEndpointDescriptor<TContext>>{
      for (final endpoint in _endpoints) endpoint.id: endpoint,
    };
    for (final operation in _installedClientOperations) {
      final endpoint = endpoints[operation.endpointId];
      if (endpoint == null || endpoint.serverOnly) {
        _fail(
          'Installed client operation "${operation.endpointId}" does not '
          'reference a public endpoint.',
        );
      }
      final AuthEndpointContractDescriptor serverContract;
      if (endpoint case final AuthEndpointContractDescriptor value) {
        serverContract = value;
      } else {
        _fail(
          'Installed client operation "${operation.endpointId}" references '
          'an endpoint without codecs.',
        );
      }

      _verifySensitiveContractMetadata(operation);
      _verifyOmittedClientPlugin(operation.plugin);

      final successfulBody = _serverEncodedResponse(operation, serverContract);
      final _InstalledClientObservation observation;
      try {
        observation = await _invokeInstalledOperation(
          operation,
          response: AuthClientConformanceResponse.raw(
            successfulBody,
            statusCode: operation.response.statusCode,
            headers: operation.response.headers,
          ),
        );
      } catch (error) {
        _verifyFailureSecrets(operation, error);
        _fail(
          'Installed client operation "${operation.endpointId}" rejected its '
          'successful response with ${error.runtimeType}.',
        );
      }
      _verifyObservedRequest(endpoint, serverContract, observation.request);
      operation.verifyResponse?.call(observation.value);
      _verifyPublicResultSecrets(operation, observation.value);

      for (
        var index = 0;
        index < operation.malformedResponses.length;
        index++
      ) {
        try {
          await _invokeInstalledOperation(
            operation,
            response: operation.malformedResponses[index],
          );
        } on FormatException catch (error) {
          _verifyFailureSecrets(operation, error);
          continue;
        } on TypeError catch (error) {
          _verifyFailureSecrets(operation, error);
          continue;
        } catch (error) {
          _verifyFailureSecrets(operation, error);
          _fail(
            'Installed client operation "${operation.endpointId}" rejected '
            'malformed response $index with ${error.runtimeType}, not a codec '
            'failure.',
          );
        }
        _fail(
          'Installed client operation "${operation.endpointId}" accepted '
          'malformed response $index.',
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

void _verifySensitiveContractMetadata(
  AuthInstalledClientOperationContract operation,
) {
  final metadata = '${operation.plugin.id}:${operation.endpointId}';
  for (final secret in operation.sensitiveValues) {
    if (secret.isNotEmpty && metadata.contains(secret)) {
      _fail(
        'Installed client operation "${operation.endpointId}" exposes a '
        'secret in public contract metadata.',
      );
    }
  }
}

void _verifyOmittedClientPlugin(AuthClientPlugin<Object> plugin) {
  final transport = AuthClientTransport(
    baseUrl: Uri.parse('https://auth-conformance.invalid'),
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );
  final omitted = AuthClientPluginRegistry(
    context: AuthClientPluginContext(transport: transport),
  );
  if (omitted.ids.isNotEmpty || omitted.contains(plugin.id)) {
    _fail('Omitted client plugin "${plugin.id}" exposed an API.');
  }
  try {
    omitted.use<Object>(plugin);
  } on StateError {
    return;
  }
  _fail('Omitted client plugin "${plugin.id}" remained usable.');
}

String _serverEncodedResponse(
  AuthInstalledClientOperationContract operation,
  AuthEndpointContractDescriptor serverContract,
) {
  final rawBody = operation.response._rawBody;
  if (rawBody != null) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      _fail(
        'Successful response for "${operation.endpointId}" must be a JSON '
        'object.',
      );
    }
    return _roundTripServerResponse(
      operation.endpointId,
      serverContract,
      Map<String, dynamic>.from(decoded),
    );
  }
  final body = operation.response._jsonBody;
  if (body is! Map) {
    _fail(
      'Successful response for "${operation.endpointId}" must be a JSON '
      'object.',
    );
  }
  return _roundTripServerResponse(
    operation.endpointId,
    serverContract,
    Map<String, dynamic>.from(body),
  );
}

String _roundTripServerResponse(
  String endpointId,
  AuthEndpointContractDescriptor serverContract,
  Map<String, dynamic> response,
) {
  try {
    _verifyJsonShape(
      response,
      serverContract.responseCodec.schema,
      '$endpointId response',
    );
    return jsonEncode(response);
  } catch (_) {
    _fail(
      'Successful client response for "$endpointId" does not match the '
      'server response contract.',
    );
  }
}

Future<_InstalledClientObservation> _invokeInstalledOperation(
  AuthInstalledClientOperationContract operation, {
  required AuthClientConformanceResponse response,
}) async {
  http.Request? observed;
  final client = MockClient((request) async {
    if (request.url.path == '/auth/csrf') {
      return http.Response(jsonEncode({'csrfToken': 'conformance-csrf'}), 200);
    }
    if (observed != null) {
      _fail(
        'Installed client operation "${operation.endpointId}" issued more '
        'than one operation request.',
      );
    }
    observed = request;
    return http.Response.bytes(
      utf8.encode(response._body),
      response.statusCode,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        ...response.headers,
      },
    );
  });
  final transport = AuthClientTransport(
    baseUrl: Uri.parse('https://auth-conformance.invalid'),
    httpClient: client,
  );
  final registry = AuthClientPluginRegistry(
    context: AuthClientPluginContext(transport: transport),
    plugins: <AuthClientPlugin<Object>>[operation.plugin],
  );
  if (registry.ids.length != 1 || !registry.contains(operation.plugin.id)) {
    _fail('Client plugin "${operation.plugin.id}" was not installed alone.');
  }
  final api = registry.use<Object>(operation.plugin);
  final value = await operation.invoke(api);
  final request = observed;
  if (request == null) {
    _fail(
      'Installed client operation "${operation.endpointId}" issued no '
      'request.',
    );
  }
  return _InstalledClientObservation(request: request, value: value);
}

void _verifyObservedRequest<TContext>(
  AuthEndpointDescriptor<TContext> endpoint,
  AuthEndpointContractDescriptor serverContract,
  http.Request request,
) {
  final expectedMethod = endpoint.method == AuthOperationMethod.get
      ? 'GET'
      : 'POST';
  if (request.method != expectedMethod) {
    _fail(
      'Installed client operation "${endpoint.id}" uses ${request.method}, '
      'not $expectedMethod.',
    );
  }
  final actualPath = request.url.path.replaceFirst(RegExp(r'^/auth'), '');
  if (_canonicalPath(actualPath) != _canonicalPath(endpoint.path)) {
    _fail(
      'Installed client operation "${endpoint.id}" uses path '
      '"$actualPath", not "${endpoint.path}".',
    );
  }

  final input = <String, dynamic>{};
  if (request.url.queryParameters.isNotEmpty) {
    input.addAll(request.url.queryParameters);
  }
  if (request.body.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(request.body);
      if (decoded is! Map) {
        _fail(
          'Installed client operation "${endpoint.id}" sent non-object JSON.',
        );
      }
      input.addAll(Map<String, dynamic>.from(decoded));
    } catch (_) {
      _fail('Installed client operation "${endpoint.id}" sent invalid JSON.');
    }
  }
  input.remove('_csrf');
  try {
    final codec = serverContract.requestCodec as dynamic;
    codec.decode(input);
  } catch (_) {
    _fail(
      'Installed client operation "${endpoint.id}" request is rejected by '
      'the server request codec.',
    );
  }
}

void _verifyJsonShape(
  Map<String, dynamic> value,
  Map<String, Object?> schema,
  String label,
) {
  final required = schema['required'];
  if (required is List) {
    for (final key in required.whereType<String>()) {
      if (!value.containsKey(key)) _fail('$label is missing "$key".');
    }
  }
  final properties = schema['properties'];
  if (properties is Map && schema['additionalProperties'] == false) {
    final allowed = properties.keys.whereType<String>().toSet();
    final unknown = value.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) _fail('$label contains unknown properties.');
  }
}

void _verifyPublicResultSecrets(
  AuthInstalledClientOperationContract operation,
  Object? value,
) {
  String serialized;
  try {
    serialized = jsonEncode(value);
  } on JsonUnsupportedObjectError {
    return;
  }
  for (final secret in operation.sensitiveValues) {
    if (secret.isNotEmpty && serialized.contains(secret)) {
      _fail(
        'Installed client operation "${operation.endpointId}" serialized a '
        'secret in its public result.',
      );
    }
  }
}

void _verifyFailureSecrets(
  AuthInstalledClientOperationContract operation,
  Object error,
) {
  final message = error.toString();
  for (final secret in operation.sensitiveValues) {
    if (secret.isNotEmpty && message.contains(secret)) {
      _fail(
        'Installed client operation "${operation.endpointId}" exposed a '
        'secret in a codec failure.',
      );
    }
  }
}

final class _InstalledClientObservation {
  const _InstalledClientObservation({required this.request, this.value});

  final http.Request request;
  final Object? value;
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
