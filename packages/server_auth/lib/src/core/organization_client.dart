import 'dart:convert';

import 'client.dart';
import 'organization_models.dart';
import 'organization_permissions.dart';

/// Installs the typed organization API on an [AuthClient].
final class AuthOrganizationClientPlugin
    implements AuthClientPlugin<AuthOrganizationClient> {
  const AuthOrganizationClientPlugin({this.staticRoles});

  final Map<String, AuthOrganizationPermissionSet>? staticRoles;

  @override
  String get id => 'organization';

  @override
  AuthOrganizationClient install(AuthClientPluginContext context) {
    return AuthOrganizationClient(
      transport: context.transport,
      staticRoles: staticRoles,
    );
  }
}

/// Typed client for the opt-in organization plugin.
final class AuthOrganizationClient {
  AuthOrganizationClient({
    required this.transport,
    Map<String, AuthOrganizationPermissionSet>? staticRoles,
  }) : _staticRoles = AuthOrganizationAccessControl(
         staticRoles: staticRoles,
       ).staticRoles;

  final AuthClientTransport transport;
  final Map<String, Map<String, List<String>>> _staticRoles;

  String? activeOrganizationId;
  String? activeTeamId;

  bool localRoleAllows(Iterable<String> roles, String resource, String action) {
    final normalizedResource = resource.trim().toLowerCase();
    final normalizedAction = action.trim().toLowerCase();
    for (final role in normalizeAuthOrganizationRoles(roles)) {
      final permissions = _staticRoles[role];
      final actions = permissions?[normalizedResource] ?? permissions?['*'];
      if (actions?.any((value) => value == normalizedAction || value == '*') ==
          true) {
        return true;
      }
    }
    return false;
  }

  Future<AuthOrganizationMutationResult<AuthOrganization>> create({
    required String name,
    required String slug,
    required String idempotencyKey,
    String? logo,
    Map<String, dynamic>? metadata,
    bool keepCurrentActiveOrganization = false,
  }) async {
    final result = _mutation(
      await _post('/organization/create', {
        'name': name,
        'slug': slug,
        'idempotencyKey': idempotencyKey,
        'logo': logo,
        'metadata': metadata,
      }),
      AuthOrganization.fromJson,
    );
    if (!keepCurrentActiveOrganization) {
      activeOrganizationId = result.data.id;
      activeTeamId = null;
    }
    return result;
  }

  Future<bool> checkSlug(String slug) async =>
      (await _get('/organization/check-slug', {'slug': slug}))['available'] ==
      true;

  Future<List<AuthOrganization>> list() async => _list(
    (await _get('/organization/list'))['organizations'],
    AuthOrganization.fromJson,
  );

  Future<AuthOrganization> get({String? organizationId}) async =>
      AuthOrganization.fromJson(
        await _get('/organization/get', {
          'organizationId': _organizationId(organizationId),
        }),
      );

  Future<AuthOrganizationDetails> getFull({
    String? organizationId,
    int membersLimit = 100,
  }) async {
    final json = await _get('/organization/get-full', {
      'organizationId': _organizationId(organizationId),
      'membersLimit': '$membersLimit',
    });
    final page = _map(json['members']);
    return AuthOrganizationDetails(
      organization: AuthOrganization.fromJson(_map(json['organization'])),
      members: AuthOrganizationPage(
        items: _list(page['items'], AuthOrganizationMember.fromJson),
        total: _integer(page['total']),
        limit: _integer(page['limit']),
        offset: _integer(page['offset']),
      ),
      invitations: _list(
        json['invitations'],
        AuthOrganizationInvitation.fromJson,
      ),
      teams: _list(json['teams'], AuthOrganizationTeam.fromJson),
    );
  }

  Future<AuthOrganizationMutationResult<AuthOrganization>> update({
    String? organizationId,
    String? name,
    String? slug,
    Object? logo,
    Object? metadata,
  }) async => _mutation(
    await _post('/organization/update', {
      'organizationId': _organizationId(organizationId),
      'data': {
        'name': ?name,
        'slug': ?slug,
        'logo': ?logo,
        'metadata': ?metadata,
      },
    }),
    AuthOrganization.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganization>> delete({
    String? organizationId,
  }) async {
    final id = _organizationId(organizationId);
    final result = _mutation(
      await _post('/organization/delete', {'organizationId': id}),
      AuthOrganization.fromJson,
    );
    if (activeOrganizationId == id) {
      activeOrganizationId = null;
      activeTeamId = null;
    }
    return result;
  }

  Future<void> setActive(String? organizationId) async {
    await _post('/organization/set-active', {'organizationId': organizationId});
    activeOrganizationId = organizationId;
    activeTeamId = null;
  }

  Future<AuthOrganizationPage<AuthOrganizationMember>> listMembers({
    String? organizationId,
    int limit = 100,
    int offset = 0,
  }) async {
    final json = await _get('/organization/list-members', {
      'organizationId': _organizationId(organizationId),
      'limit': '$limit',
      'offset': '$offset',
    });
    return AuthOrganizationPage(
      items: _list(json['items'], AuthOrganizationMember.fromJson),
      total: _integer(json['total']),
      limit: _integer(json['limit']),
      offset: _integer(json['offset']),
    );
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>> removeMember({
    required String userId,
    String? organizationId,
  }) => _memberMutation('/organization/remove-member', userId, organizationId);

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  updateMemberRole({
    required String userId,
    required Iterable<String> roles,
    String? organizationId,
  }) async => _mutation(
    await _post('/organization/update-member-role', {
      'organizationId': _organizationId(organizationId),
      'userId': userId,
      'roles': roles.toList(),
    }),
    AuthOrganizationMember.fromJson,
  );

  Future<AuthOrganizationMember> getActiveMember({
    String? organizationId,
  }) async => AuthOrganizationMember.fromJson(
    await _get('/organization/get-active-member', {
      'organizationId': _organizationId(organizationId),
    }),
  );

  Future<List<String>> getActiveMemberRole({String? organizationId}) async {
    final roles = (await _get('/organization/get-active-member-role', {
      'organizationId': _organizationId(organizationId),
    }))['roles'];
    return roles is List
        ? List<String>.unmodifiable(roles.map((value) => '$value'))
        : const [];
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>> leave({
    String? organizationId,
  }) async {
    final id = _organizationId(organizationId);
    final result = _mutation(
      await _post('/organization/leave', {'organizationId': id}),
      AuthOrganizationMember.fromJson,
    );
    if (activeOrganizationId?.trim() == id) {
      activeOrganizationId = null;
      activeTeamId = null;
    }
    return result;
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  inviteMember({
    required String email,
    required String idempotencyKey,
    Iterable<String> roles = const ['member'],
    String? organizationId,
    String? teamId,
  }) async => _mutation(
    await _post('/organization/invite-member', {
      'organizationId': _organizationId(organizationId),
      'email': email,
      'idempotencyKey': idempotencyKey,
      'roles': roles.toList(),
      'teamId': teamId,
    }),
    AuthOrganizationInvitation.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  acceptInvitation(String invitationId) async => _mutation(
    await _post('/organization/accept-invitation', {
      'invitationId': invitationId,
    }),
    AuthOrganizationMember.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  rejectInvitation(String invitationId) =>
      _invitationMutation('/organization/reject-invitation', invitationId);

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  cancelInvitation(String invitationId) =>
      _invitationMutation('/organization/cancel-invitation', invitationId);

  Future<AuthOrganizationInvitation> getInvitation(String invitationId) async =>
      AuthOrganizationInvitation.fromJson(
        await _get('/organization/get-invitation', {
          'invitationId': invitationId,
        }),
      );

  Future<List<AuthOrganizationInvitation>> listInvitations({
    String? organizationId,
  }) async => _list(
    (await _get('/organization/list-invitations', {
      'organizationId': _organizationId(organizationId),
    }))['invitations'],
    AuthOrganizationInvitation.fromJson,
  );

  Future<List<AuthOrganizationInvitation>> listUserInvitations() async => _list(
    (await _get('/organization/list-user-invitations'))['invitations'],
    AuthOrganizationInvitation.fromJson,
  );

  Future<bool> hasPermission({
    required String resource,
    required String action,
    String? organizationId,
  }) async =>
      (await _get('/organization/has-permission', {
        'organizationId': _organizationId(organizationId),
        'resource': resource,
        'action': action,
      }))['allowed'] ==
      true;

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> createRole({
    required String name,
    required Map<String, Iterable<String>> permissions,
    required String idempotencyKey,
    String? organizationId,
  }) => _roleMutation('/organization/create-role', {
    'organizationId': _organizationId(organizationId),
    'name': name,
    'idempotencyKey': idempotencyKey,
    'permissions': _permissionJson(permissions),
  });

  Future<List<AuthOrganizationRole>> listRoles({
    String? organizationId,
  }) async => _list(
    (await _get('/organization/list-roles', {
      'organizationId': _organizationId(organizationId),
    }))['roles'],
    AuthOrganizationRole.fromJson,
  );

  Future<AuthOrganizationRole> getRole(
    String name, {
    String? organizationId,
  }) async => AuthOrganizationRole.fromJson(
    await _get('/organization/get-role', {
      'organizationId': _organizationId(organizationId),
      'name': name,
    }),
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> updateRole({
    required String name,
    String? newName,
    Map<String, Iterable<String>>? permissions,
    String? organizationId,
  }) => _roleMutation('/organization/update-role', {
    'organizationId': _organizationId(organizationId),
    'name': name,
    'newName': newName,
    if (permissions != null) 'permissions': _permissionJson(permissions),
  });

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> deleteRole(
    String name, {
    String? organizationId,
  }) => _roleMutation('/organization/delete-role', {
    'organizationId': _organizationId(organizationId),
    'name': name,
  });

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> createTeam({
    required String name,
    required String idempotencyKey,
    String? organizationId,
    Map<String, dynamic>? attributes,
  }) => _teamMutation('/organization/create-team', {
    'organizationId': _organizationId(organizationId),
    'name': name,
    'idempotencyKey': idempotencyKey,
    'attributes': attributes,
  });

  Future<List<AuthOrganizationTeam>> listTeams({
    String? organizationId,
  }) async => _list(
    (await _get('/organization/list-teams', {
      'organizationId': _organizationId(organizationId),
    }))['teams'],
    AuthOrganizationTeam.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> updateTeam({
    required String teamId,
    required String name,
  }) => _teamMutation('/organization/update-team', {
    'teamId': teamId,
    'name': name,
  });

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> removeTeam(
    String teamId,
  ) async {
    final normalizedTeamId = teamId.trim();
    final result = await _teamMutation('/organization/remove-team', {
      'teamId': normalizedTeamId,
    });
    if (activeTeamId?.trim() == normalizedTeamId) {
      activeTeamId = null;
    }
    return result;
  }

  Future<void> setActiveTeam(String? teamId) async {
    await _post('/organization/set-active-team', {
      'organizationId': _organizationId(null),
      'teamId': teamId,
    });
    activeTeamId = teamId;
  }

  Future<List<AuthOrganizationTeam>> listUserTeams({
    String? organizationId,
  }) async => _list(
    (await _get('/organization/list-user-teams', {
      'organizationId': _organizationId(organizationId),
    }))['teams'],
    AuthOrganizationTeam.fromJson,
  );

  Future<List<AuthOrganizationTeamMember>> listTeamMembers(
    String teamId,
  ) async => _list(
    (await _get('/organization/list-team-members', {
      'teamId': teamId,
    }))['members'],
    AuthOrganizationTeamMember.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  addTeamMember({
    required String teamId,
    required String userId,
    required String idempotencyKey,
  }) async => _mutation(
    await _post('/organization/add-team-member', {
      'teamId': teamId,
      'userId': userId,
      'idempotencyKey': idempotencyKey,
    }),
    AuthOrganizationTeamMember.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  removeTeamMember({required String teamId, required String userId}) =>
      _teamMemberMutation('/organization/remove-team-member', teamId, userId);

  String _organizationId(String? explicit) {
    final value = explicit?.trim().isNotEmpty == true
        ? explicit!.trim()
        : activeOrganizationId?.trim() ?? '';
    if (value.isEmpty) throw StateError('No active organization is selected.');
    return value;
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  _memberMutation(String path, String userId, String? organizationId) async =>
      _mutation(
        await _post(path, {
          'organizationId': _organizationId(organizationId),
          'userId': userId,
        }),
        AuthOrganizationMember.fromJson,
      );

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  _invitationMutation(String path, String invitationId) async => _mutation(
    await _post(path, {'invitationId': invitationId}),
    AuthOrganizationInvitation.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> _roleMutation(
    String path,
    Map<String, dynamic> body,
  ) async => _mutation(await _post(path, body), AuthOrganizationRole.fromJson);

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> _teamMutation(
    String path,
    Map<String, dynamic> body,
  ) async => _mutation(await _post(path, body), AuthOrganizationTeam.fromJson);

  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  _teamMemberMutation(String path, String teamId, String userId) async =>
      _mutation(
        await _post(path, {'teamId': teamId, 'userId': userId}),
        AuthOrganizationTeamMember.fromJson,
      );

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async => _decode(
    (await transport.request('GET', path, queryParameters: query)).body,
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async => _decode((await transport.mutate('POST', path, body)).body);
}

AuthOrganizationMutationResult<T> _mutation<T>(
  Map<String, dynamic> json,
  T Function(Map<String, dynamic>) decode,
) => AuthOrganizationMutationResult(
  data: decode(_map(json['data'])),
  warnings: _list(
    json['warnings'],
    (value) => AuthOrganizationWarning(
      code: value['code']?.toString() ?? 'organization_warning',
      message: value['message']?.toString(),
    ),
  ),
);

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) decode) {
  if (value is! List) return <T>[];
  return List<T>.unmodifiable(value.map((item) => decode(_map(item))));
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid organization response');
  }
  return <String, dynamic>{
    for (final entry in value.entries) '${entry.key}': entry.value,
  };
}

Map<String, dynamic> _decode(String body) {
  final value = jsonDecode(body);
  return _map(value);
}

int _integer(Object? value) =>
    value is int ? value : int.tryParse('$value') ?? 0;

Map<String, List<String>> _permissionJson(
  Map<String, Iterable<String>> value,
) => {for (final entry in value.entries) entry.key: entry.value.toList()};
