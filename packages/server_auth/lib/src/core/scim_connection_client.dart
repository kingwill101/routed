import 'dart:convert';

import 'package:server_auth/src/core/client.dart';
import 'package:server_auth/src/core/plugin.dart';
import 'package:server_auth/src/core/scim_connection_models.dart';
import 'package:server_auth/src/core/scim_models.dart';

/// Installs only the managed-SCIM connection API selected by the application.
final class AuthScimConnectionClientPlugin
    implements AuthClientPlugin<AuthScimConnectionClient> {
  /// Creates a client plugin for managed SCIM connections.
  const AuthScimConnectionClientPlugin();

  /// The stable managed-SCIM client plugin identifier.
  @override
  String get id => 'scim_connections';

  /// Installs the client using [context]'s transport.
  @override
  AuthScimConnectionClient install(AuthClientPluginContext context) =>
      AuthScimConnectionClient(transport: context.transport);
}

/// Typed client for the opt-in managed SCIM connection plugin.
final class AuthScimConnectionClient {
  /// Creates a client using [transport] for API requests.
  const AuthScimConnectionClient({required this.transport});

  /// Transport used to call the managed SCIM endpoints.
  final AuthClientTransport transport;

  /// Creates a managed SCIM connection and returns its one-time credential.
  Future<AuthScimConnectionCreation> create({
    required String organizationId,
    required String name,
    required String provisioningDomainId,
    required Iterable<AuthScimScope> scopes,
    required String credentialName,
    required String idempotencyKey,
    DateTime? expiresAt,
  }) async => AuthScimConnectionCreation.fromJson(
    await _post(
      const AuthRoutePath('/scim/connections/create'),
      <String, dynamic>{
        'organizationId': organizationId,
        'name': name,
        'provisioningDomainId': provisioningDomainId,
        'scopes': scopes.map((value) => value.name).toList(growable: false),
        'credentialName': credentialName,
        'idempotencyKey': idempotencyKey,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
    ),
  );

  /// Lists the managed SCIM connections for [organizationId].
  Future<AuthScimConnectionPage> list({
    required String organizationId,
    int limit = 100,
    int offset = 0,
  }) async {
    final json = await _get(
      const AuthRoutePath('/scim/connections'),
      <String, String>{
        'organizationId': organizationId,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _connectionPage(json);
  }

  /// Updates a connection after checking [expectedUpdatedAt].
  Future<AuthScimManagedConnection> update({
    required String organizationId,
    required String connectionId,
    required DateTime expectedUpdatedAt,
    required String name,
    required String provisioningDomainId,
    required Iterable<AuthScimScope> scopes,
  }) async => AuthScimManagedConnection.fromJson(
    await _post(
      const AuthRoutePath('/scim/connections/update'),
      <String, dynamic>{
        'organizationId': organizationId,
        'connectionId': connectionId,
        'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String(),
        'name': name,
        'provisioningDomainId': provisioningDomainId,
        'scopes': scopes.map((value) => value.name).toList(growable: false),
      },
    ),
  );

  /// Disables a managed SCIM connection.
  Future<AuthScimManagedConnection> disable({
    required String organizationId,
    required String connectionId,
  }) async => AuthScimManagedConnection.fromJson(
    await _post(
      const AuthRoutePath('/scim/connections/disable'),
      <String, dynamic>{
        'organizationId': organizationId,
        'connectionId': connectionId,
      },
    ),
  );

  /// Lists credentials belonging to a managed connection.
  Future<AuthScimCredentialPage> listCredentials({
    required String organizationId,
    required String connectionId,
    int limit = 100,
    int offset = 0,
  }) async {
    final json = await _get(
      const AuthRoutePath('/scim/connections/credentials'),
      <String, String>{
        'organizationId': organizationId,
        'connectionId': connectionId,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _credentialPage(json);
  }

  /// Issues a one-time-displayed credential for a connection.
  Future<AuthScimCredentialIssuance> issueCredential({
    required String organizationId,
    required String connectionId,
    required String name,
    required Iterable<AuthScimScope> scopes,
    required String idempotencyKey,
    DateTime? expiresAt,
  }) async => AuthScimCredentialIssuance.fromJson(
    await _post(
      const AuthRoutePath('/scim/connections/credentials/issue'),
      <String, dynamic>{
        'organizationId': organizationId,
        'connectionId': connectionId,
        'name': name,
        'scopes': scopes.map((value) => value.name).toList(growable: false),
        'idempotencyKey': idempotencyKey,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
    ),
  );

  /// Rotates [credentialId] and returns the replacement secret once.
  Future<AuthScimCredentialIssuance> rotateCredential({
    required String organizationId,
    required String connectionId,
    required String credentialId,
    required String name,
    required Iterable<AuthScimScope> scopes,
    required String idempotencyKey,
    DateTime? expiresAt,
  }) async => AuthScimCredentialIssuance.fromJson(
    await _post(
      const AuthRoutePath('/scim/connections/credentials/rotate'),
      <String, dynamic>{
        'organizationId': organizationId,
        'connectionId': connectionId,
        'credentialId': credentialId,
        'name': name,
        'scopes': scopes.map((value) => value.name).toList(growable: false),
        'idempotencyKey': idempotencyKey,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
    ),
  );

  /// Revokes [credentialId] and returns its updated record.
  Future<AuthScimCredential> revokeCredential({
    required String organizationId,
    required String connectionId,
    required String credentialId,
  }) async => AuthScimCredential.fromJson(
    await _post(
      const AuthRoutePath('/scim/connections/credentials/revoke'),
      <String, dynamic>{
        'organizationId': organizationId,
        'connectionId': connectionId,
        'credentialId': credentialId,
      },
    ),
  );

  Future<Map<String, dynamic>> _get(
    AuthRoutePath path,
    Map<String, String> query,
  ) async => _body(
    (await transport.request('GET', path, queryParameters: query)).body,
  );

  Future<Map<String, dynamic>> _post(
    AuthRoutePath path,
    Map<String, dynamic> body,
  ) async => _body((await transport.mutate('POST', path, body)).body);
}

AuthScimConnectionPage _connectionPage(Map<String, dynamic> json) {
  final values = json['items'];
  if (values is! List) throw const FormatException('Invalid connection page.');
  return AuthScimConnectionPage(
    items: List<AuthScimManagedConnection>.unmodifiable(
      values.map((value) {
        if (value is! Map) {
          throw const FormatException('Invalid connection page item.');
        }
        return AuthScimManagedConnection.fromJson(
          Map<String, dynamic>.from(value),
        );
      }),
    ),
    total: _int(json, 'total'),
    limit: _int(json, 'limit'),
    offset: _int(json, 'offset'),
  );
}

AuthScimCredentialPage _credentialPage(Map<String, dynamic> json) {
  final values = json['items'];
  if (values is! List) throw const FormatException('Invalid credential page.');
  return AuthScimCredentialPage(
    items: List<AuthScimCredential>.unmodifiable(
      values.map((value) {
        if (value is! Map) {
          throw const FormatException('Invalid credential page item.');
        }
        return AuthScimCredential.fromJson(Map<String, dynamic>.from(value));
      }),
    ),
    total: _int(json, 'total'),
    limit: _int(json, 'limit'),
    offset: _int(json, 'offset'),
  );
}

Map<String, dynamic> _body(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) throw const FormatException('Invalid auth response.');
  return Map<String, dynamic>.from(decoded);
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  final parsed = int.tryParse('$value');
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed;
}
