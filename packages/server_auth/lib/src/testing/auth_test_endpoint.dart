import '../core/exceptions.dart';
import '../core/models.dart';
import '../core/plugin.dart';
import 'auth_test_http.dart';

/// Builds an invocation for one portable plugin endpoint request.
typedef AuthTestInvocationFactory<TContext> =
    AuthOperationInvocation<TContext> Function(AuthTestHttpRequest request);

/// Bridges real portable plugin descriptors to [AuthTestHttpClient].
///
/// The bridge performs no framework authentication, CSRF, origin, or
/// rate-limit enforcement. Those policies belong in adapter integration tests.
/// It invokes the endpoint's real request and response codecs, making it useful
/// for end-to-end tests shared by multiple framework adapters.
final class AuthPluginEndpointFixture<TContext> {
  /// Creates a bridge for [endpoints].
  AuthPluginEndpointFixture({
    required Iterable<AuthEndpointDescriptor<TContext>> endpoints,
    required this.invocation,
    this.basePath = '/auth',
    this.csrfToken = 'fixture-csrf-token',
  }) : _endpoints = List<AuthEndpointDescriptor<TContext>>.unmodifiable(
         endpoints,
       );

  final List<AuthEndpointDescriptor<TContext>> _endpoints;

  /// Supplies framework-neutral context, identity, and session control.
  final AuthTestInvocationFactory<TContext> invocation;

  /// Prefix expected before each portable endpoint path.
  final String basePath;

  /// Test-only CSRF value returned to clients that use mutating operations.
  final String csrfToken;

  /// Handles one request from [AuthTestHttpClient].
  Future<AuthTestHttpResponse> respond(AuthTestHttpRequest request) async {
    final prefix = _normalizeBasePath(basePath);
    if (request.method == 'GET' && request.uri.path == '$prefix/csrf') {
      return AuthTestHttpResponse.json(<String, dynamic>{
        'csrfToken': csrfToken,
      });
    }
    if (!request.uri.path.startsWith(prefix)) {
      return AuthTestHttpResponse.error('not_found', statusCode: 404);
    }
    final path = request.uri.path.substring(prefix.length);
    final endpoint = _endpoints.where((candidate) {
      return candidate.path == path &&
          candidate.method.name.toUpperCase() == request.method;
    }).firstOrNull;
    if (endpoint == null) {
      return AuthTestHttpResponse.error('not_found', statusCode: 404);
    }
    try {
      final result = await endpoint.invoke(
        invocation(request),
        request.jsonObject(),
      );
      if (result is AuthEndpointRedirect) {
        return AuthTestHttpResponse(
          statusCode: result.statusCode,
          body: '',
          headers: <String, String>{
            ...result.headers,
            'location': result.location.toString(),
          },
        );
      }
      if (result is AuthEndpointSessionResponse) {
        return AuthTestHttpResponse.json(<String, dynamic>{
          ...result.session.redacted().toJson(),
          ...result.metadata,
        });
      }
      return AuthTestHttpResponse.json(result);
    } on AuthFlowException catch (error) {
      return AuthTestHttpResponse.error(error.code);
    } on FormatException {
      return AuthTestHttpResponse.error('invalid_request');
    }
  }
}

/// Session control with deterministic timestamps for portable plugin tests.
final class AuthTestSessionControl implements AuthServerPluginSessionControl {
  /// Creates a session control using [clock] for issued expiration times.
  AuthTestSessionControl({
    required DateTime Function() clock,
    this.strategy = AuthSessionStrategy.session,
    this.maximumAge = const Duration(hours: 1),
    this.currentSessionId = 'fixture-session',
  }) : _clock = clock;

  final DateTime Function() _clock;

  @override
  final AuthSessionStrategy strategy;

  /// Default session lifetime for [replaceIdentity].
  final Duration maximumAge;

  @override
  final String? currentSessionId;

  /// Authentication methods issued in order.
  final List<String> authenticationMethods = <String>[];

  /// Sessions issued in order.
  final List<AuthSession> sessions = <AuthSession>[];

  /// Whether [signOut] was invoked.
  bool signedOut = false;

  @override
  Future<AuthSession> replaceIdentity(
    AuthUser user, {
    required String authenticationMethod,
    Duration? maximumAge,
    String? impersonatedBy,
  }) async {
    authenticationMethods.add(authenticationMethod);
    final session = AuthSession(
      user: user,
      expiresAt: _clock().toUtc().add(maximumAge ?? this.maximumAge),
      strategy: strategy,
    );
    sessions.add(session);
    return session;
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

String _normalizeBasePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') return '';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}';
}
