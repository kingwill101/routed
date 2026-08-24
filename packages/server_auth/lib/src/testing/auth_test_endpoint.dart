import 'dart:convert';

import 'package:server_auth/src/core/exceptions.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/plugin.dart';
import 'package:server_auth/src/testing/auth_test_http.dart';

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
    final match = _endpoints
        .map(
          (candidate) => (candidate, _matchPath(candidate.path.template, path)),
        )
        .where(
          (entry) =>
              entry.$2 != null &&
              entry.$1.method.name.toUpperCase() == request.method,
        )
        .firstOrNull;
    if (match == null) {
      return AuthTestHttpResponse.error('not_found', statusCode: 404);
    }
    final endpoint = match.$1;
    try {
      final endpointRequest = AuthEndpointRequest(
        path: endpoint.path.bind(Map<String, Object?>.from(match.$2!)),
        query: Map<String, dynamic>.from(request.uri.queryParameters),
        body: request.jsonObject(),
        headers: request.headers,
      );
      final endpointInvocation = invocation(
        request,
      ).withRequest(endpointRequest);
      final result = await endpoint.invoke(endpointInvocation, endpointRequest);
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
      if (result is AuthEndpointAuthenticationIntent) {
        final control = endpointInvocation.sessionControl;
        if (control is! AuthTestSessionControl) {
          return AuthTestHttpResponse.error('authentication_host_unavailable');
        }
        final session = control.completeAuthentication(result);
        return AuthTestHttpResponse.json(
          await result.projectResponse(session.redacted().toJson()),
        );
      }
      if (result is AuthEndpointHttpResponse) {
        return AuthTestHttpResponse(
          statusCode: result.statusCode,
          body: result.body == null ? '' : jsonEncode(result.body),
          headers: <String, String>{
            if (result.body != null) 'content-type': 'application/json',
            ...result.headers,
          },
        );
      }
      return AuthTestHttpResponse.json(result);
    } on AuthFlowException catch (error) {
      return AuthTestHttpResponse.error(error.code);
    } on FormatException {
      final errorEndpoint =
          endpoint is AuthEndpointPublicErrorResponseDescriptor
          ? endpoint as AuthEndpointPublicErrorResponseDescriptor
          : null;
      if (errorEndpoint != null) {
        final response = errorEndpoint.createPublicErrorResponse(
          AuthEndpointPublicErrorKind.invalidRequest,
        );
        if (response != null) {
          return AuthTestHttpResponse(
            statusCode: response.statusCode,
            body: response.body == null ? '' : jsonEncode(response.body),
            headers: <String, String>{
              if (response.body != null) 'content-type': 'application/json',
              ...response.headers,
            },
          );
        }
      }
      return AuthTestHttpResponse.error('invalid_request');
    }
  }
}

Map<String, String>? _matchPath(String template, String actual) {
  final templateParts = template.split('/');
  final actualParts = actual.split('/');
  if (templateParts.length != actualParts.length) return null;
  final parameters = <String, String>{};
  for (var index = 0; index < templateParts.length; index++) {
    final expected = templateParts[index];
    final value = actualParts[index];
    if (expected.startsWith('{') && expected.endsWith('}')) {
      final name = expected.substring(1, expected.length - 1).trim();
      if (name.isEmpty || value.isEmpty) return null;
      parameters[name] = Uri.decodeComponent(value);
    } else if (expected != value) {
      return null;
    }
  }
  return parameters;
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

  /// Default session lifetime for [completeAuthentication].
  final Duration maximumAge;

  @override
  final String? currentSessionId;

  /// Authentication methods issued in order.
  final List<String> authenticationMethods = <String>[];

  /// Sessions issued in order.
  final List<AuthSession> sessions = <AuthSession>[];

  /// Whether [signOut] was invoked.
  bool signedOut = false;

  /// Completes one endpoint authentication intent for portable fixture tests.
  AuthSession completeAuthentication(AuthEndpointAuthenticationIntent intent) {
    authenticationMethods.add(intent.authenticationMethod);
    final session = AuthSession(
      user: intent.user,
      expiresAt: _clock().toUtc().add(intent.maximumAge ?? maximumAge),
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
