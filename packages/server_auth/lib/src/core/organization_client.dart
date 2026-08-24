import 'dart:convert';

import 'client.dart';
import 'plugin.dart';
import 'organization_models.dart';
import 'organization_permissions.dart';

/// Installs the typed organization API on an [AuthClient].
final class AuthOrganizationClientPlugin
    implements AuthClientPlugin<AuthOrganizationClient> {
  /// Creates an instance of AuthOrganizationClientPlugin.
  const AuthOrganizationClientPlugin({this.staticRoles});

  /// The roles assigned to this value.
  final Map<String, AuthOrganizationPermissionSet>? staticRoles;

  /// The identifier exposed by this component.
  @override
  String get id => 'organization';

  /// Installs the requested value.
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
  /// Creates an instance of AuthOrganizationClient.
  AuthOrganizationClient({
    required this.transport,
    Map<String, AuthOrganizationPermissionSet>? staticRoles,
  }) : _staticRoles = AuthOrganizationAccessControl(
         staticRoles: staticRoles,
       ).staticRoles;

  /// The transport used to send client requests.
  final AuthClientTransport transport;
  final Map<String, Map<String, List<String>>> _staticRoles;

  /// The identifier of active organization.
  String? activeOrganizationId;

  /// The identifier of active team.
  String? activeTeamId;

  /// Performs the local role allows operation.
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

  /// Creates the requested value.
  Future<AuthOrganizationMutationResult<AuthOrganization>> create({
    required String name,
    required String slug,
    required String idempotencyKey,
    String? logo,
    Map<String, dynamic>? metadata,
    bool keepCurrentActiveOrganization = false,
  }) async {
    final result = _mutation(
      await _post(const AuthRoutePath('/organization/create'), {
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

  /// Performs the check slug operation.
  Future<bool> checkSlug(String slug) async =>
      (await _get(const AuthRoutePath('/organization/check-slug'), {
        'slug': slug,
      }))['available'] ==
      true;

  /// Lists the requested value.
  Future<List<AuthOrganization>> list() async => _list(
    (await _get(const AuthRoutePath('/organization/list')))['organizations'],
    AuthOrganization.fromJson,
  );

  /// Looks up the requested value.
  Future<AuthOrganization> get({String? organizationId}) async =>
      AuthOrganization.fromJson(
        await _get(const AuthRoutePath('/organization/get'), {
          'organizationId': _organizationId(organizationId),
        }),
      );

  /// Looks up full.
  Future<AuthOrganizationDetails> getFull({
    String? organizationId,
    int membersLimit = 100,
  }) async {
    final json = await _get(const AuthRoutePath('/organization/get-full'), {
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

  /// Updates the requested value.
  Future<AuthOrganizationMutationResult<AuthOrganization>> update({
    String? organizationId,
    String? name,
    String? slug,
    Object? logo,
    Object? metadata,
  }) async => _mutation(
    await _post(const AuthRoutePath('/organization/update'), {
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

  /// Deletes the requested value.
  Future<AuthOrganizationMutationResult<AuthOrganization>> delete({
    String? organizationId,
  }) async {
    final id = _organizationId(organizationId);
    final result = _mutation(
      await _post(const AuthRoutePath('/organization/delete'), {
        'organizationId': id,
      }),
      AuthOrganization.fromJson,
    );
    if (activeOrganizationId == id) {
      activeOrganizationId = null;
      activeTeamId = null;
    }
    return result;
  }

  /// Sets active.
  Future<void> setActive(String? organizationId) async {
    await _post(const AuthRoutePath('/organization/set-active'), {
      'organizationId': organizationId,
    });
    activeOrganizationId = organizationId;
    activeTeamId = null;
  }

  /// Lists members.
  Future<AuthOrganizationPage<AuthOrganizationMember>> listMembers({
    String? organizationId,
    int limit = 100,
    int offset = 0,
  }) async {
    final json = await _get(const AuthRoutePath('/organization/list-members'), {
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

  /// Deletes member.
  Future<AuthOrganizationMutationResult<AuthOrganizationMember>> removeMember({
    required String userId,
    String? organizationId,
  }) => _memberMutation(
    const AuthRoutePath('/organization/remove-member'),
    userId,
    organizationId,
  );

  /// Updates member role.
  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  updateMemberRole({
    required String userId,
    required Iterable<String> roles,
    String? organizationId,
  }) async => _mutation(
    await _post(const AuthRoutePath('/organization/update-member-role'), {
      'organizationId': _organizationId(organizationId),
      'userId': userId,
      'roles': roles.toList(),
    }),
    AuthOrganizationMember.fromJson,
  );

  /// Looks up active member.
  Future<AuthOrganizationMember> getActiveMember({
    String? organizationId,
  }) async => AuthOrganizationMember.fromJson(
    await _get(const AuthRoutePath('/organization/get-active-member'), {
      'organizationId': _organizationId(organizationId),
    }),
  );

  /// Looks up active member role.
  Future<List<String>> getActiveMemberRole({String? organizationId}) async {
    final roles = (await _get(
      const AuthRoutePath('/organization/get-active-member-role'),
      {'organizationId': _organizationId(organizationId)},
    ))['roles'];
    return roles is List
        ? List<String>.unmodifiable(roles.map((value) => '$value'))
        : const [];
  }

  /// Performs the leave operation.
  Future<AuthOrganizationMutationResult<AuthOrganizationMember>> leave({
    String? organizationId,
  }) async {
    final id = _organizationId(organizationId);
    final result = _mutation(
      await _post(const AuthRoutePath('/organization/leave'), {
        'organizationId': id,
      }),
      AuthOrganizationMember.fromJson,
    );
    if (activeOrganizationId?.trim() == id) {
      activeOrganizationId = null;
      activeTeamId = null;
    }
    return result;
  }

  /// Performs the invite member operation.
  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  inviteMember({
    required String email,
    required String idempotencyKey,
    Iterable<String> roles = const ['member'],
    String? organizationId,
    String? teamId,
  }) async => _mutation(
    await _post(const AuthRoutePath('/organization/invite-member'), {
      'organizationId': _organizationId(organizationId),
      'email': email,
      'idempotencyKey': idempotencyKey,
      'roles': roles.toList(),
      'teamId': teamId,
    }),
    AuthOrganizationInvitation.fromJson,
  );

  /// Performs the accept invitation operation.
  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  acceptInvitation(String invitationId) async => _mutation(
    await _post(const AuthRoutePath('/organization/accept-invitation'), {
      'invitationId': invitationId,
    }),
    AuthOrganizationMember.fromJson,
  );

  /// Performs the reject invitation operation.
  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  rejectInvitation(String invitationId) => _invitationMutation(
    const AuthRoutePath('/organization/reject-invitation'),
    invitationId,
  );

  /// Returns whether this value can cel invitation.
  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  cancelInvitation(String invitationId) => _invitationMutation(
    const AuthRoutePath('/organization/cancel-invitation'),
    invitationId,
  );

  /// Looks up invitation.
  Future<AuthOrganizationInvitation> getInvitation(String invitationId) async =>
      AuthOrganizationInvitation.fromJson(
        await _get(const AuthRoutePath('/organization/get-invitation'), {
          'invitationId': invitationId,
        }),
      );

  /// Lists invitations.
  Future<List<AuthOrganizationInvitation>> listInvitations({
    String? organizationId,
  }) async => _list(
    (await _get(const AuthRoutePath('/organization/list-invitations'), {
      'organizationId': _organizationId(organizationId),
    }))['invitations'],
    AuthOrganizationInvitation.fromJson,
  );

  /// Lists user invitations.
  Future<List<AuthOrganizationInvitation>> listUserInvitations() async => _list(
    (await _get(
      const AuthRoutePath('/organization/list-user-invitations'),
    ))['invitations'],
    AuthOrganizationInvitation.fromJson,
  );

  /// Returns whether this value has permission.
  Future<bool> hasPermission({
    required String resource,
    required String action,
    String? organizationId,
  }) async =>
      (await _get(const AuthRoutePath('/organization/has-permission'), {
        'organizationId': _organizationId(organizationId),
        'resource': resource,
        'action': action,
      }))['allowed'] ==
      true;

  /// Creates role.
  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> createRole({
    required String name,
    required Map<String, Iterable<String>> permissions,
    required String idempotencyKey,
    String? organizationId,
  }) => _roleMutation(const AuthRoutePath('/organization/create-role'), {
    'organizationId': _organizationId(organizationId),
    'name': name,
    'idempotencyKey': idempotencyKey,
    'permissions': _permissionJson(permissions),
  });

  /// Lists roles.
  Future<List<AuthOrganizationRole>> listRoles({
    String? organizationId,
  }) async => _list(
    (await _get(const AuthRoutePath('/organization/list-roles'), {
      'organizationId': _organizationId(organizationId),
    }))['roles'],
    AuthOrganizationRole.fromJson,
  );

  /// Looks up role.
  Future<AuthOrganizationRole> getRole(
    String name, {
    String? organizationId,
  }) async => AuthOrganizationRole.fromJson(
    await _get(const AuthRoutePath('/organization/get-role'), {
      'organizationId': _organizationId(organizationId),
      'name': name,
    }),
  );

  /// Updates role.
  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> updateRole({
    required String name,
    String? newName,
    Map<String, Iterable<String>>? permissions,
    String? organizationId,
  }) => _roleMutation(const AuthRoutePath('/organization/update-role'), {
    'organizationId': _organizationId(organizationId),
    'name': name,
    'newName': newName,
    if (permissions != null) 'permissions': _permissionJson(permissions),
  });

  /// Deletes role.
  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> deleteRole(
    String name, {
    String? organizationId,
  }) => _roleMutation(const AuthRoutePath('/organization/delete-role'), {
    'organizationId': _organizationId(organizationId),
    'name': name,
  });

  /// Creates team.
  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> createTeam({
    required String name,
    required String idempotencyKey,
    String? organizationId,
    Map<String, dynamic>? attributes,
  }) => _teamMutation(const AuthRoutePath('/organization/create-team'), {
    'organizationId': _organizationId(organizationId),
    'name': name,
    'idempotencyKey': idempotencyKey,
    'attributes': attributes,
  });

  /// Lists teams.
  Future<List<AuthOrganizationTeam>> listTeams({
    String? organizationId,
  }) async => _list(
    (await _get(const AuthRoutePath('/organization/list-teams'), {
      'organizationId': _organizationId(organizationId),
    }))['teams'],
    AuthOrganizationTeam.fromJson,
  );

  /// Updates team.
  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> updateTeam({
    required String teamId,
    required String name,
  }) => _teamMutation(const AuthRoutePath('/organization/update-team'), {
    'teamId': teamId,
    'name': name,
  });

  /// Deletes team.
  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> removeTeam(
    String teamId,
  ) async {
    final normalizedTeamId = teamId.trim();
    final result = await _teamMutation(
      const AuthRoutePath('/organization/remove-team'),
      {'teamId': normalizedTeamId},
    );
    if (activeTeamId?.trim() == normalizedTeamId) {
      activeTeamId = null;
    }
    return result;
  }

  /// Sets active team.
  Future<void> setActiveTeam(String? teamId) async {
    await _post(const AuthRoutePath('/organization/set-active-team'), {
      'organizationId': _organizationId(null),
      'teamId': teamId,
    });
    activeTeamId = teamId;
  }

  /// Lists user teams.
  Future<List<AuthOrganizationTeam>> listUserTeams({
    String? organizationId,
  }) async => _list(
    (await _get(const AuthRoutePath('/organization/list-user-teams'), {
      'organizationId': _organizationId(organizationId),
    }))['teams'],
    AuthOrganizationTeam.fromJson,
  );

  /// Lists team members.
  Future<List<AuthOrganizationTeamMember>> listTeamMembers(
    String teamId,
  ) async => _list(
    (await _get(const AuthRoutePath('/organization/list-team-members'), {
      'teamId': teamId,
    }))['members'],
    AuthOrganizationTeamMember.fromJson,
  );

  /// Adds team member.
  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  addTeamMember({
    required String teamId,
    required String userId,
    required String idempotencyKey,
  }) async => _mutation(
    await _post(const AuthRoutePath('/organization/add-team-member'), {
      'teamId': teamId,
      'userId': userId,
      'idempotencyKey': idempotencyKey,
    }),
    AuthOrganizationTeamMember.fromJson,
  );

  /// Deletes team member.
  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  removeTeamMember({required String teamId, required String userId}) =>
      _teamMemberMutation(
        const AuthRoutePath('/organization/remove-team-member'),
        teamId,
        userId,
      );

  String _organizationId(String? explicit) {
    final value = explicit?.trim().isNotEmpty == true
        ? explicit!.trim()
        : activeOrganizationId?.trim() ?? '';
    if (value.isEmpty) throw StateError('No active organization is selected.');
    return value;
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  _memberMutation(
    AuthRoutePath path,
    String userId,
    String? organizationId,
  ) async => _mutation(
    await _post(path, {
      'organizationId': _organizationId(organizationId),
      'userId': userId,
    }),
    AuthOrganizationMember.fromJson,
  );

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  _invitationMutation(AuthRoutePath path, String invitationId) async =>
      _mutation(
        await _post(path, {'invitationId': invitationId}),
        AuthOrganizationInvitation.fromJson,
      );

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> _roleMutation(
    AuthRoutePath path,
    Map<String, dynamic> body,
  ) async => _mutation(await _post(path, body), AuthOrganizationRole.fromJson);

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> _teamMutation(
    AuthRoutePath path,
    Map<String, dynamic> body,
  ) async => _mutation(await _post(path, body), AuthOrganizationTeam.fromJson);

  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  _teamMemberMutation(AuthRoutePath path, String teamId, String userId) async =>
      _mutation(
        await _post(path, {'teamId': teamId, 'userId': userId}),
        AuthOrganizationTeamMember.fromJson,
      );

  Future<Map<String, dynamic>> _get(
    AuthRoutePath path, [
    Map<String, String>? query,
  ]) async => _decode(
    (await transport.request('GET', path, queryParameters: query)).body,
  );

  Future<Map<String, dynamic>> _post(
    AuthRoutePath path,
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
