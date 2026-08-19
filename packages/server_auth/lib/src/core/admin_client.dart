import 'dart:convert';

import 'admin.dart' show AuthAdminAccessControl, AuthAdminPermissionSet;
import 'admin_models.dart';
import 'client.dart';
import 'models.dart';

/// Installs the typed administrative API on an [AuthClient].
final class AuthAdminClientPlugin implements AuthClientPlugin<AuthAdminClient> {
  const AuthAdminClientPlugin({this.roles});

  final Map<String, AuthAdminPermissionSet>? roles;

  @override
  String get id => 'admin';

  @override
  AuthAdminClient install(AuthClientPluginContext context) {
    return AuthAdminClient(transport: context.transport, roles: roles);
  }
}

/// Typed client for the opt-in Admin feature.
final class AuthAdminClient {
  AuthAdminClient({
    required this.transport,
    Map<String, AuthAdminPermissionSet>? roles,
  }) : _accessControl = AuthAdminAccessControl(roles: roles);

  final AuthClientTransport transport;
  final AuthAdminAccessControl _accessControl;

  bool localRoleAllows(
    Iterable<String> roles,
    String resource,
    String action,
  ) => _accessControl.allows(roles, resource, action);

  Future<AuthAdminUserPage> listUsers({
    String? search,
    String? id,
    String? email,
    String? name,
    String? role,
    bool? banned,
    AuthAdminUserSortField sortBy = AuthAdminUserSortField.id,
    bool descending = false,
    int limit = 100,
    int offset = 0,
  }) async => AuthAdminUserPage.fromJson(
    await _get('/admin/list-users', {
      'search': ?search,
      'id': ?id,
      'email': ?email,
      'name': ?name,
      'role': ?role,
      if (banned != null) 'banned': banned.toString(),
      'sortBy': sortBy.name,
      'sortDirection': descending ? 'desc' : 'asc',
      'limit': '$limit',
      'offset': '$offset',
    }),
  );

  Future<AuthAdminUser> getUser(String userId) async =>
      AuthAdminUser.fromJson(await _get('/admin/get-user', {'userId': userId}));

  Future<AuthAdminMutationResult<AuthAdminUser>> createUser({
    String? id,
    required String email,
    required String name,
    required String password,
    String? image,
    Iterable<String>? roles,
    Map<String, dynamic>? attributes,
  }) => _userMutation('/admin/create-user', {
    'id': id,
    'email': email,
    'name': name,
    'password': password,
    'image': image,
    'roles': ?roles?.toList(),
    'attributes': ?attributes,
  });

  Future<AuthAdminMutationResult<AuthAdminUser>> updateUser({
    required String userId,
    String? email,
    String? name,
    Object? image,
    bool clearImage = false,
    Map<String, dynamic>? attributes,
  }) => _userMutation('/admin/update-user', {
    'userId': userId,
    'email': ?email,
    'name': ?name,
    if (clearImage) 'image': null else 'image': ?image,
    'attributes': ?attributes,
  });

  Future<AuthAdminMutationResult<AuthAdminUser>> setRole({
    required String userId,
    required Iterable<String> roles,
  }) => _userMutation('/admin/set-role', {
    'userId': userId,
    'roles': roles.toList(),
  });

  Future<AuthAdminMutationResult<AuthAdminUser>> setUserPassword({
    required String userId,
    required String newPassword,
  }) => _userMutation('/admin/set-user-password', {
    'userId': userId,
    'newPassword': newPassword,
  });

  Future<AuthAdminMutationResult<AuthAdminUser>> banUser({
    required String userId,
    String? reason,
    DateTime? expiresAt,
  }) => _userMutation('/admin/ban-user', {
    'userId': userId,
    'banReason': reason,
    'banExpiresAt': expiresAt?.toUtc().toIso8601String(),
  });

  Future<AuthAdminMutationResult<AuthAdminUser>> unbanUser(String userId) =>
      _userMutation('/admin/unban-user', {'userId': userId});

  Future<List<AuthAdminSession>> listUserSessions(String userId) async {
    final values = (await _post('/admin/list-user-sessions', {
      'userId': userId,
    }))['sessions'];
    return _list(values, AuthAdminSession.fromJson);
  }

  Future<void> revokeUserSession({
    required String userId,
    required String sessionId,
  }) async {
    await _post('/admin/revoke-user-session', {
      'userId': userId,
      'sessionId': sessionId,
    });
  }

  Future<int> revokeUserSessions(String userId) async {
    final value = (await _post('/admin/revoke-user-sessions', {
      'userId': userId,
    }))['revoked'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  Future<AuthAdminMutationResult<AuthSession>> impersonateUser(String userId) =>
      _sessionMutation('/admin/impersonate-user', {'userId': userId});

  Future<AuthAdminMutationResult<AuthAdminStopImpersonatingResult>>
  stopImpersonating() async {
    final json = await _post('/admin/stop-impersonating', const {});
    final data = _map(json['data']);
    final rawSession = data['session'];
    return AuthAdminMutationResult(
      data: AuthAdminStopImpersonatingResult(
        signedOut: data['signedOut'] == true,
        session: rawSession is Map ? _session(_map(rawSession)) : null,
      ),
      warnings: _warnings(json),
    );
  }

  Future<AuthAdminMutationResult<bool>> removeUser(String userId) async {
    final json = await _post('/admin/remove-user', {'userId': userId});
    return AuthAdminMutationResult(
      data: _map(json)['data'] == true,
      warnings: _warnings(json),
    );
  }

  Future<bool> hasPermission({
    required String resource,
    required String action,
    String? userId,
  }) async =>
      (await _post('/admin/has-permission', {
        'resource': resource,
        'action': action,
        'userId': userId,
      }))['allowed'] ==
      true;

  Future<AuthAdminMutationResult<AuthAdminUser>> _userMutation(
    String path,
    Map<String, dynamic> body,
  ) async {
    final json = await _post(path, body);
    return AuthAdminMutationResult(
      data: AuthAdminUser.fromJson(_map(json['data'])),
      warnings: _warnings(json),
    );
  }

  Future<AuthAdminMutationResult<AuthSession>> _sessionMutation(
    String path,
    Map<String, dynamic> body,
  ) async {
    final json = await _post(path, body);
    return AuthAdminMutationResult(
      data: _session(_map(json['data'])),
      warnings: _warnings(json),
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async => _body(
    (await transport.request('GET', path, queryParameters: query)).body,
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async => _body((await transport.mutate('POST', path, body)).body);
}

Map<String, dynamic> _body(String body) {
  final value = jsonDecode(body);
  if (value is! Map) throw const FormatException('Invalid admin response');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Invalid admin response');
  return Map<String, dynamic>.from(value);
}

List<AuthAdminWarning> _warnings(Map<String, dynamic> json) =>
    _list(json['warnings'], AuthAdminWarning.fromJson);

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) decode) {
  if (value is! List) return const [];
  return List<T>.unmodifiable(value.map((item) => decode(_map(item))));
}

AuthSession _session(Map<String, dynamic> json) {
  final expires = json['expires'];
  final strategy = json['strategy']?.toString();
  return AuthSession(
    user: AuthUser.fromJson(_map(json['user'])),
    expiresAt: expires == null ? null : DateTime.parse('$expires').toUtc(),
    strategy: strategy == null
        ? null
        : AuthSessionStrategy.values.firstWhere(
            (value) => value.name == strategy,
          ),
    token: json['token']?.toString(),
  );
}
