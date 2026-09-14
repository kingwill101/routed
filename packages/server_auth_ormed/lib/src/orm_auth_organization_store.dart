import 'dart:async';
import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:server_auth/server_auth.dart';

import 'orm_auth_organization_schema.dart';
import 'orm_transaction_gate.dart';

/// Durable organization persistence backed by an Ormed database.
///
/// The adapter owns only the tables declared by [schema]. The application's
/// core [AuthStore] remains a separate concern; pass this store to
/// [OrganizationPlugin] while passing the core store to [AuthOptions]. Every
/// mutating operation is ordered through the shared database gate. Transaction
/// capable drivers run these operations atomically; drivers with native Ormed
/// atomic batches use them when a mutation can be staged up front, while D1
/// operations that require read-dependent control flow remain ordered.
final class OrmAuthOrganizationStore
    implements
        AuthOrganizationStore,
        AuthOrganizationAtomicMutationStore,
        AuthOrganizationMembershipMutationStore,
        AuthOrganizationUserDeletionStore,
        AuthOrganizationUserDeletionPlanFactory {
  /// Creates an adapter over an initialized Ormed database.
  OrmAuthOrganizationStore(
    this.database, {
    this.schema = const OrmAuthOrganizationSchema(),
  }) : _transactionGate = transactionGateFor(database) {
    if (!database.isOpen) {
      throw ArgumentError.value(database, 'database', 'must be open');
    }
  }

  /// Opens an adapter and applies its migration through Ormed's ledger.
  static Future<OrmAuthOrganizationStore> open(
    OrmDatabase database, {
    OrmAuthOrganizationSchema schema = const OrmAuthOrganizationSchema(),
    String ledgerTable = 'orm_migrations',
  }) async {
    await schema.migrate(database, ledgerTable: ledgerTable);
    return OrmAuthOrganizationStore(database, schema: schema);
  }

  /// Ormed database handle owned by the application lifecycle.
  final OrmDatabase database;

  /// Table naming and migration configuration.
  final OrmAuthOrganizationSchema schema;
  final OrmAuthTransactionGate _transactionGate;

  String get _organizations => schema.table('organizations');
  String get _members => schema.table('organization_members');
  String get _invitations => schema.table('organization_invitations');
  String get _roles => schema.table('organization_roles');
  String get _teams => schema.table('organization_teams');
  String get _teamMembers => schema.table('organization_team_members');
  String get _idempotency => schema.table('organization_idempotency');

  Future<T> _transaction<T>(Future<T> Function() action) =>
      _transactionGate.run(database, action);

  Query<AdHocRow> _table(String name) =>
      database.table(name, columns: _tableColumns(name));

  bool get _supportsAtomicBatch => database.driver.metadata.supportsCapability(
    DriverCapability.atomicBatches,
  );

  Future<List<Map<String, Object?>>> _query(Query<AdHocRow> query) async {
    final rows = await query.get();
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Query<AdHocRow> _where(
    Query<AdHocRow> query,
    Map<String, Object?> conditions,
  ) {
    var result = query;
    for (final entry in conditions.entries) {
      result = result.whereEquals(entry.key, entry.value);
    }
    return result;
  }

  Future<void> _insert(String table, Map<String, Object?> values) async {
    await _table(table).insertManyInputs([values], returning: false);
  }

  Future<int> _update(
    String table,
    Map<String, Object?> conditions,
    Map<String, Object?> values,
  ) => _where(_table(table), conditions).update(values);

  Future<int> _delete(String table, Map<String, Object?> conditions) =>
      _where(_table(table), conditions).delete();

  @override
  Future<AuthOrganizationCreateStoredResult> createOrganization(
    AuthOrganizationCreateTransaction transaction,
  ) => _transaction(() async {
    final replay = await _replay(
      transaction.idempotency,
      resultType: 'organization',
    );
    if (replay != null) {
      final payload = _jsonObject(replay.result);
      return AuthOrganizationCreateStoredResult(
        organization: AuthOrganization.fromJson(
          _jsonObject(payload['organization']),
        ),
        creatorMembership: AuthOrganizationMember.fromJson(
          _jsonObject(payload['creatorMembership']),
        ),
        defaultTeam: payload['defaultTeam'] == null
            ? null
            : AuthOrganizationTeam.fromJson(
                _jsonObject(payload['defaultTeam']),
              ),
        replayed: true,
      );
    }
    final organization = transaction.organization.copyWith(
      slug: transaction.organization.slug.trim().toLowerCase(),
    );
    final creator = transaction.creatorMembership;
    _require(
      await _findOrganization(organization.id) == null,
      'organization_exists',
    );
    _require(
      await _findOrganizationBySlug(organization.slug) == null,
      'organization_slug_taken',
    );
    _require(
      creator.organizationId == organization.id,
      'invalid_organization_member',
    );
    final count = await _count(
      _table(_members).whereEquals('user_id', creator.userId),
    );
    _requireLimit(count, transaction.organizationLimit, 'organization_limit');
    _require(
      await _findMember(organization.id, creator.userId) == null,
      'member_exists',
    );
    final team = transaction.defaultTeam;
    final teamMember = transaction.creatorTeamMembership;
    if (team != null) {
      _require(team.organizationId == organization.id, 'invalid_team');
      if (teamMember != null) {
        _require(teamMember.teamId == team.id, 'invalid_team_member');
        _require(teamMember.userId == creator.userId, 'invalid_team_member');
      }
    } else {
      _require(teamMember == null, 'invalid_team_member');
    }
    await _insertOrganization(organization);
    await _insertMember(creator);
    if (team != null) await _insertTeam(team);
    if (teamMember != null) await _insertTeamMember(teamMember);
    final result = AuthOrganizationCreateStoredResult(
      organization: organization,
      creatorMembership: creator,
      defaultTeam: team,
    );
    await _remember(
      transaction.idempotency,
      resultType: 'organization',
      result: {
        'organization': organization.toJson(),
        'creatorMembership': creator.toJson(),
        'defaultTeam': team?.toJson(),
      },
    );
    return result;
  });

  @override
  Future<AuthOrganization?> findOrganization(String organizationId) =>
      _transaction(() => _findOrganization(organizationId));

  @override
  Future<AuthOrganization?> findOrganizationBySlug(String slug) =>
      _transaction(() => _findOrganizationBySlug(slug));

  @override
  Future<List<AuthOrganization>> listOrganizationsForUser(String userId) =>
      _transaction(() async {
        final memberRows = await _query(
          _table(_members).whereEquals('user_id', userId.trim()),
        );
        final organizationIds = memberRows
            .map((row) => row['organization_id'])
            .whereType<Object>()
            .toList(growable: false);
        if (organizationIds.isEmpty) return const <AuthOrganization>[];
        final rows = await _query(
          _table(_organizations).whereIn('id', organizationIds).orderBy('name'),
        );
        return List<AuthOrganization>.unmodifiable(
          rows.map(_organizationFromRow),
        );
      });

  @override
  Future<AuthOrganization> updateOrganization(AuthOrganization value) =>
      _transaction(() async {
        final normalized = value.copyWith(
          slug: value.slug.trim().toLowerCase(),
        );
        _require(
          await _findOrganization(normalized.id) != null,
          'organization_not_found',
        );
        final duplicate = await _query(
          _table(_organizations)
              .whereEquals('slug', normalized.slug)
              .whereNotEquals('id', normalized.id),
        );
        _require(duplicate.isEmpty, 'organization_slug_taken');
        await _update(
          _organizations,
          {'id': normalized.id},
          {
            'name': normalized.name,
            'slug': normalized.slug,
            'logo': normalized.logo,
            'metadata': _json(normalized.metadata),
            'updated_at': _date(normalized.updatedAt),
          },
        );
        return normalized;
      });

  @override
  Future<AuthOrganization> deleteOrganization(String organizationId) =>
      _transaction(() async {
        final id = organizationId.trim();
        final organization = await _findOrganization(id);
        _require(organization != null, 'organization_not_found');
        final teams = await _query(
          _table(_teams).whereEquals('organization_id', id),
        );
        final teamIds = teams.map((row) => row['id']).whereType<Object>();
        if (teamIds.isNotEmpty) {
          await _table(_teamMembers).whereIn('team_id', teamIds).delete();
        }
        await _delete(_members, {'organization_id': id});
        await _delete(_invitations, {'organization_id': id});
        await _delete(_roles, {'organization_id': id});
        await _delete(_teams, {'organization_id': id});
        await _delete(_organizations, {'id': id});
        return organization!;
      });

  @override
  Future<AuthOrganizationMember?> findMember(
    String organizationId,
    String userId,
  ) => _transaction(() => _findMember(organizationId, userId));

  @override
  Future<List<AuthOrganizationMember>> listMembers(
    String organizationId,
  ) => _transaction(() async {
    final rows = await _query(
      _table(_members).whereEquals('organization_id', organizationId.trim()),
    );
    return List<AuthOrganizationMember>.unmodifiable(rows.map(_memberFromRow));
  });

  @override
  Future<AuthOrganizationMember> addMember(
    AuthOrganizationMember member, {
    int? membershipLimit,
  }) => _transaction(() async {
    _require(
      await _findOrganization(member.organizationId) != null,
      'organization_not_found',
    );
    _require(
      await _findMember(member.organizationId, member.userId) == null,
      'member_exists',
    );
    final count = await _count(
      _table(_members).whereEquals('organization_id', member.organizationId),
    );
    _requireLimit(count, membershipLimit, 'membership_limit');
    await _insertMember(member);
    return member;
  });

  @override
  Future<AuthOrganizationMember> mutateOrganizationMembership(
    AuthOrganizationMembershipMutation mutation,
  ) => _transaction(() async {
    final actorSnapshot = mutation.actorMembership;
    final targetSnapshot = mutation.targetMembership;
    final organizationId = actorSnapshot.organizationId.trim();
    _require(
      organizationId.isNotEmpty &&
          targetSnapshot.organizationId.trim() == organizationId,
      'invalid_organization_member',
    );
    _require(
      await _findOrganization(organizationId) != null,
      'organization_not_found',
    );
    final actor = await _findMember(organizationId, actorSnapshot.userId);
    _require(
      actor != null && _sameMembershipSnapshot(actor, actorSnapshot),
      'organization_forbidden',
    );
    final actorValue = actor!;
    await _requireRoleSnapshots(actorValue, mutation.actorRoleSnapshots);
    final target = await _findMember(organizationId, targetSnapshot.userId);
    _require(target != null, 'member_not_found');
    _require(
      _sameMembershipSnapshot(target!, targetSnapshot),
      'organization_membership_changed',
    );
    final creatorRole = _normalizeCreatorRole(mutation.creatorRole);
    final replacementRoles = mutation.replacementRoles;
    if (mutation.kind == AuthOrganizationMembershipMutationKind.replaceRoles) {
      _require(
        replacementRoles != null && replacementRoles.isNotEmpty,
        'invalid_role',
      );
    } else {
      _require(replacementRoles == null, 'invalid_role');
    }
    final affectsCreator =
        target.roles.contains(creatorRole) ||
        (replacementRoles?.contains(creatorRole) ?? false);
    if (affectsCreator) {
      _require(actor.roles.contains(creatorRole), 'organization_forbidden');
    }
    final removesCreator =
        target.roles.contains(creatorRole) &&
        (mutation.kind == AuthOrganizationMembershipMutationKind.remove ||
            !replacementRoles!.contains(creatorRole));
    if (removesCreator) {
      final owners = await _creatorCount(organizationId, creatorRole);
      _require(owners > 1, 'last_owner');
    }
    if (mutation.kind == AuthOrganizationMembershipMutationKind.replaceRoles) {
      await _update(
        _members,
        {'organization_id': organizationId, 'user_id': target.userId},
        {'roles': jsonEncode(replacementRoles)},
      );
      return target.copyWith(roles: replacementRoles);
    }
    final teams = await _query(
      _table(_teams).whereEquals('organization_id', organizationId),
    );
    final teamIds = teams.map((row) => row['id']).whereType<Object>();
    if (teamIds.isNotEmpty) {
      await _where(_table(_teamMembers), {
        'user_id': target.userId,
      }).whereIn('team_id', teamIds).delete();
    }
    await _delete(_members, {
      'organization_id': organizationId,
      'user_id': target.userId,
    });
    return target;
  });

  @override
  Future<AuthOrganizationInvitation?> findInvitation(String invitationId) =>
      _transaction(() => _findInvitation(invitationId));

  @override
  Future<List<AuthOrganizationInvitation>> listInvitations(
    String organizationId,
  ) => _transaction(() async {
    final rows = await _query(
      _table(
        _invitations,
      ).whereEquals('organization_id', organizationId.trim()),
    );
    return List<AuthOrganizationInvitation>.unmodifiable(
      rows.map(_invitationFromRow),
    );
  });

  @override
  Future<List<AuthOrganizationInvitation>> listInvitationsForEmail(
    String email,
  ) => _transaction(() async {
    final rows = await _query(
      _table(_invitations).whereEquals('email', normalizeAuthEmail(email)),
    );
    return List<AuthOrganizationInvitation>.unmodifiable(
      rows.map(_invitationFromRow),
    );
  });

  @override
  Future<AuthOrganizationInvitation> createInvitation(
    AuthOrganizationInvitation invitation, {
    int? invitationLimit,
    bool replacePending = false,
  }) => _transaction(() async {
    _require(
      await _findOrganization(invitation.organizationId) != null,
      'organization_not_found',
    );
    final existing = await _findPendingInvitation(
      invitation.organizationId,
      invitation.email,
      invitation.createdAt,
    );
    if (existing != null && !replacePending) return existing;
    final count = await _countPendingInvitations(
      invitation.organizationId,
      invitation.createdAt,
    );
    if (existing == null) {
      _requireLimit(count, invitationLimit, 'invitation_limit');
    } else {
      await _update(
        _invitations,
        {'id': existing.id},
        {'status': AuthOrganizationInvitationStatus.canceled.name},
      );
    }
    _require(await _findInvitation(invitation.id) == null, 'invitation_exists');
    await _insertInvitation(invitation);
    return invitation;
  });

  @override
  Future<AuthOrganizationInvitation> transitionInvitation(
    String invitationId,
    AuthOrganizationInvitationStatus status, {
    required DateTime now,
  }) => _transaction(() async {
    final invitation = await _findInvitation(invitationId);
    _require(invitation != null, 'invitation_not_found');
    _require(invitation!.isPending(now), 'invitation_not_pending');
    final updated = invitation.copyWith(status: status);
    await _update(_invitations, {'id': invitation.id}, {'status': status.name});
    return updated;
  });

  @override
  Future<AuthOrganizationInvitationAcceptanceResult> acceptInvitation(
    AuthOrganizationInvitationAcceptance acceptance,
  ) => _transaction(() async {
    final invitation = await _findInvitation(acceptance.invitationId);
    _require(invitation != null, 'invitation_not_found');
    _require(invitation!.isPending(acceptance.now), 'invitation_not_pending');
    _require(
      invitation.email == normalizeAuthEmail(acceptance.email),
      'invitation_email_mismatch',
    );
    final membership = acceptance.membership;
    _require(
      membership.organizationId == invitation.organizationId,
      'invalid_organization_member',
    );
    _require(
      await _findMember(membership.organizationId, membership.userId) == null,
      'member_exists',
    );
    final memberCount = await _count(
      _table(
        _members,
      ).whereEquals('organization_id', membership.organizationId),
    );
    _requireLimit(memberCount, acceptance.membershipLimit, 'membership_limit');
    final teamMembership = acceptance.teamMembership;
    if (teamMembership != null) {
      final team = await _findTeam(teamMembership.teamId);
      _require(
        team != null && team.organizationId == membership.organizationId,
        'team_not_found',
      );
      _require(
        teamMembership.userId == membership.userId,
        'invalid_team_member',
      );
      _require(
        await _findTeamMember(teamMembership.teamId, teamMembership.userId) ==
            null,
        'team_member_exists',
      );
      final count = await _count(
        _table(_teamMembers).whereEquals('team_id', teamMembership.teamId),
      );
      _requireLimit(count, acceptance.teamMemberLimit, 'team_member_limit');
    }
    final accepted = invitation.copyWith(
      status: AuthOrganizationInvitationStatus.accepted,
    );
    await _insertMember(membership);
    if (teamMembership != null) await _insertTeamMember(teamMembership);
    await _update(
      _invitations,
      {'id': invitation.id},
      {'status': accepted.status.name},
    );
    return AuthOrganizationInvitationAcceptanceResult(
      invitation: accepted,
      membership: membership,
      teamMembership: teamMembership,
    );
  });

  @override
  Future<AuthOrganizationRole?> findRole(String organizationId, String name) =>
      _transaction(() => _findRole(organizationId, name));

  @override
  Future<List<AuthOrganizationRole>> listRoles(String organizationId) =>
      _transaction(() async {
        final rows = await _query(
          _table(_roles).whereEquals('organization_id', organizationId.trim()),
        );
        return List<AuthOrganizationRole>.unmodifiable(rows.map(_roleFromRow));
      });

  @override
  Future<AuthOrganizationRole> createRole(
    AuthOrganizationRole role, {
    int? roleLimit,
  }) => _transaction(() async {
    _require(
      await _findRole(role.organizationId, role.name) == null,
      'role_exists',
    );
    _require(
      !(await _table(_roles).whereEquals('id', role.id).exists()),
      'role_exists',
    );
    final count = await _count(
      _table(_roles).whereEquals('organization_id', role.organizationId),
    );
    _requireLimit(count, roleLimit, 'role_limit');
    await _insertRole(role);
    return role;
  });

  @override
  Future<AuthOrganizationRole> updateRole(
    AuthOrganizationRole role, {
    required String previousName,
    required String creatorRole,
  }) => _transaction(() async {
    final existing = await _findRole(role.organizationId, previousName);
    _require(existing != null, 'role_not_found');
    _require(!existing!.predefined, 'predefined_role');
    final normalizedCreatorRole = _normalizeCreatorRole(creatorRole);
    _require(
      existing.name != normalizedCreatorRole &&
          role.name != normalizedCreatorRole,
      'creator_role',
    );
    final duplicate = await _findRole(role.organizationId, role.name);
    _require(duplicate == null || duplicate.id == existing.id, 'role_exists');
    await _renameRoleReferences(role.organizationId, existing.name, role.name);
    await _delete(_roles, {'id': existing.id});
    await _insertRole(role);
    return role;
  });

  @override
  Future<AuthOrganizationRole> deleteRole(
    String organizationId,
    String name, {
    required String creatorRole,
  }) => _transaction(() async {
    final role = await _findRole(organizationId, name);
    _require(role != null, 'role_not_found');
    _require(!role!.predefined, 'predefined_role');
    _require(role.name != _normalizeCreatorRole(creatorRole), 'creator_role');
    _require(
      !(await _membersWithRole(role.organizationId, role.name)).isNotEmpty,
      'role_in_use',
    );
    _require(
      !(await _pendingInvitationsWithRole(
        role.organizationId,
        role.name,
      )).isNotEmpty,
      'role_in_use',
    );
    await _delete(_roles, {'id': role.id});
    return role;
  });

  @override
  Future<AuthOrganizationTeam?> findTeam(String teamId) =>
      _transaction(() => _findTeam(teamId));

  @override
  Future<List<AuthOrganizationTeam>> listTeams(String organizationId) =>
      _transaction(() async {
        final rows = await _query(
          _table(_teams).whereEquals('organization_id', organizationId.trim()),
        );
        return List<AuthOrganizationTeam>.unmodifiable(rows.map(_teamFromRow));
      });

  @override
  Future<List<AuthOrganizationTeam>> listTeamsForUser(
    String organizationId,
    String userId,
  ) => _transaction(() async {
    final memberships = await _query(
      _table(_teamMembers).whereEquals('user_id', userId.trim()),
    );
    final teamIds = memberships
        .map((row) => row['team_id'])
        .whereType<Object>();
    if (teamIds.isEmpty) return const <AuthOrganizationTeam>[];
    final rows = await _query(
      _table(_teams)
          .whereEquals('organization_id', organizationId.trim())
          .whereIn('id', teamIds),
    );
    return List<AuthOrganizationTeam>.unmodifiable(rows.map(_teamFromRow));
  });

  @override
  Future<AuthOrganizationTeam> createTeam(
    AuthOrganizationTeam team, {
    int? teamLimit,
  }) => _transaction(() async {
    _require(
      await _findOrganization(team.organizationId) != null,
      'organization_not_found',
    );
    _require(await _findTeam(team.id) == null, 'team_exists');
    final duplicate = await _query(
      _table(_teams)
          .whereEquals('organization_id', team.organizationId)
          .whereILike('name', team.name),
    );
    _require(duplicate.isEmpty, 'team_exists');
    final count = await _count(
      _table(_teams).whereEquals('organization_id', team.organizationId),
    );
    _requireLimit(count, teamLimit, 'team_limit');
    await _insertTeam(team);
    return team;
  });

  @override
  Future<AuthOrganizationTeam> updateTeam(AuthOrganizationTeam team) =>
      _transaction(() async {
        final existing = await _findTeam(team.id);
        _require(existing != null, 'team_not_found');
        _require(
          existing!.organizationId == team.organizationId,
          'organization_forbidden',
        );
        final duplicate = await _query(
          _table(_teams)
              .whereEquals('organization_id', team.organizationId)
              .whereILike('name', team.name)
              .whereNotEquals('id', team.id),
        );
        _require(duplicate.isEmpty, 'team_exists');
        await _update(
          _teams,
          {'id': team.id},
          {
            'name': team.name,
            'attributes': _json(team.attributes),
            'updated_at': _date(team.updatedAt),
          },
        );
        return team;
      });

  @override
  Future<AuthOrganizationTeam> deleteTeam(
    String teamId, {
    bool allowLastTeam = false,
  }) => _transaction(() async {
    final team = await _findTeam(teamId);
    _require(team != null, 'team_not_found');
    if (!allowLastTeam) {
      final count = await _count(
        _table(_teams).whereEquals('organization_id', team!.organizationId),
      );
      _require(count > 1, 'last_team');
    }
    await _delete(_teamMembers, {'team_id': team!.id});
    await _update(_invitations, {'team_id': team.id}, {'team_id': null});
    await _delete(_teams, {'id': team.id});
    return team;
  });

  @override
  Future<AuthOrganizationTeamMember?> findTeamMember(
    String teamId,
    String userId,
  ) => _transaction(() => _findTeamMember(teamId, userId));

  @override
  Future<List<AuthOrganizationTeamMember>> listTeamMembers(String teamId) =>
      _transaction(() async {
        final rows = await _query(
          _table(_teamMembers).whereEquals('team_id', teamId.trim()),
        );
        return List<AuthOrganizationTeamMember>.unmodifiable(
          rows.map(_teamMemberFromRow),
        );
      });

  @override
  Future<AuthOrganizationTeamMember> addTeamMember(
    AuthOrganizationTeamMember member, {
    int? memberLimit,
  }) => _transaction(() async {
    final team = await _findTeam(member.teamId);
    _require(team != null, 'team_not_found');
    _require(
      await _findMember(team!.organizationId, member.userId) != null,
      'member_not_found',
    );
    _require(
      await _findTeamMember(member.teamId, member.userId) == null,
      'team_member_exists',
    );
    final count = await _count(
      _table(_teamMembers).whereEquals('team_id', member.teamId),
    );
    _requireLimit(count, memberLimit, 'team_member_limit');
    await _insertTeamMember(member);
    return member;
  });

  @override
  Future<AuthOrganizationTeamMember> removeTeamMember(
    String teamId,
    String userId,
  ) => _transaction(() async {
    final member = await _findTeamMember(teamId, userId);
    _require(member != null, 'team_member_not_found');
    await _delete(_teamMembers, {
      'team_id': teamId.trim(),
      'user_id': userId.trim(),
    });
    return member!;
  });

  @override
  Future<TResult> executeOrganizationMutation<TResult>(
    AuthOrganizationStoreCommand<TResult> command,
  ) => _transaction(() async {
    final Object result;
    if (command case final AuthOrganizationCreateInvitationCommand value) {
      result = await _executeCreateInvitation(value);
    } else if (command
        case final AuthOrganizationTransitionInvitationCommand value) {
      result = await _executeTransitionInvitation(value);
    } else if (command case final AuthOrganizationRoleMutationCommand value) {
      result = await _executeRoleMutation(value);
    } else if (command case final AuthOrganizationTeamMutationCommand value) {
      result = await _executeTeamMutation(value);
    } else if (command
        case final AuthOrganizationTeamMemberMutationCommand value) {
      result = await _executeTeamMemberMutation(value);
    } else {
      throw StateError('Unsupported organization mutation command.');
    }
    return result as TResult;
  });

  @override
  Future<void> validateUserDeletion(
    String userId, {
    required String creatorRole,
  }) => _transaction(() async {
    final role = _normalizeCreatorRole(creatorRole);
    final members = await _membersForUser(userId);
    for (final member in members) {
      if (member.roles.contains(role) &&
          await _creatorCount(member.organizationId, role) <= 1) {
        throw AuthFlowException('last_owner');
      }
    }
  });

  @override
  Future<AuthUserDeletionPlan> createOrganizationDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
    required String creatorRole,
  }) async {
    if (namespace != 'organization') {
      throw ArgumentError.value(namespace, 'namespace');
    }
    return _OrmOrganizationDeletionPlan(
      domain: domain,
      userId: user.id,
      namespace: namespace,
      applyOperation: () => _deleteUserDataInTransaction(
        user.id,
        creatorRole: creatorRole,
        email: user.email,
      ),
    );
  }

  @override
  Future<void> deleteUserData(
    String userId, {
    required String creatorRole,
    String? email,
  }) => _transaction(() async {
    await _deleteUserDataInTransaction(
      userId,
      creatorRole: creatorRole,
      email: email,
    );
  });

  Future<void> _deleteUserDataInTransaction(
    String userId, {
    required String creatorRole,
    String? email,
  }) async {
    await _validateUserDeletionInTransaction(userId, creatorRole: creatorRole);
    final id = userId.trim();
    await _delete(_teamMembers, {'user_id': id});
    await _delete(_members, {'user_id': id});
    var invitations = _table(_invitations).whereEquals('inviter_id', id);
    if (email != null) {
      invitations = invitations.orWhere('email', normalizeAuthEmail(email));
    }
    await invitations.delete();
  }

  Future<void> _validateUserDeletionInTransaction(
    String userId, {
    required String creatorRole,
  }) async {
    final role = _normalizeCreatorRole(creatorRole);
    for (final member in await _membersForUser(userId)) {
      if (member.roles.contains(role) &&
          await _creatorCount(member.organizationId, role) <= 1) {
        throw AuthFlowException('last_owner');
      }
    }
  }

  Future<AuthOrganizationStoreMutationResult<AuthOrganizationInvitation>>
  _executeCreateInvitation(
    AuthOrganizationCreateInvitationCommand command,
  ) async {
    final invitation = command.invitation;
    await _requireActor(
      command.actorMembership,
      invitation.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = await _replay(command.idempotency, resultType: 'invitation');
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(
        value: AuthOrganizationInvitation.fromJson(_jsonObject(replay.result)),
        replayed: true,
      );
    }
    _require(
      await _findOrganization(invitation.organizationId) != null,
      'organization_not_found',
    );
    final existing = await _findPendingInvitation(
      invitation.organizationId,
      invitation.email,
      invitation.createdAt,
    );
    if (existing != null && !command.replacePending) {
      await _remember(
        command.idempotency,
        resultType: 'invitation',
        result: existing.toJson(),
      );
      return AuthOrganizationStoreMutationResult(value: existing);
    }
    final count = await _countPendingInvitations(
      invitation.organizationId,
      invitation.createdAt,
    );
    if (existing == null) {
      _requireLimit(count, command.invitationLimit, 'invitation_limit');
    }
    _require(await _findInvitation(invitation.id) == null, 'invitation_exists');

    if (_supportsAtomicBatch) {
      final remember = await _prepareRememberOperation(
        command.idempotency,
        resultType: 'invitation',
        result: invitation.toJson(),
      );
      final operations = <AtomicBatchOperation>[
        if (existing != null)
          _where(_table(_invitations), {'id': existing.id}).batchUpdate({
            'status': AuthOrganizationInvitationStatus.canceled.name,
          }),
        _table(
          _invitations,
        ).batchInsert([_invitationMap(invitation)], returning: false),
        ?remember,
      ];
      await database.atomicBatch(operations);
    } else {
      if (existing != null) {
        await _update(
          _invitations,
          {'id': existing.id},
          {'status': AuthOrganizationInvitationStatus.canceled.name},
        );
      }
      await _insertInvitation(invitation);
      await _remember(
        command.idempotency,
        resultType: 'invitation',
        result: invitation.toJson(),
      );
    }
    return AuthOrganizationStoreMutationResult(value: invitation);
  }

  Future<AuthOrganizationStoreMutationResult<AuthOrganizationInvitation>>
  _executeTransitionInvitation(
    AuthOrganizationTransitionInvitationCommand command,
  ) async {
    final expected = command.expectedInvitation;
    final current = await _findInvitation(expected.id);
    _require(current != null, 'invitation_not_found');
    _require(_sameInvitationSnapshot(current!, expected), 'invitation_changed');
    _require(current.isPending(command.now), 'invitation_not_pending');
    if (command.actorMembership != null) {
      await _requireActor(
        command.actorMembership!,
        current.organizationId,
        command.actorRoleSnapshots,
      );
    } else {
      _require(
        command.actorId.trim().isNotEmpty &&
            command.actorEmail != null &&
            current.email == normalizeAuthEmail(command.actorEmail!),
        'invitation_email_mismatch',
      );
      _require(
        command.status == AuthOrganizationInvitationStatus.rejected,
        'organization_forbidden',
      );
    }
    final updated = current.copyWith(status: command.status);
    await _update(
      _invitations,
      {'id': current.id},
      {'status': command.status.name},
    );
    return AuthOrganizationStoreMutationResult(value: updated);
  }

  Future<AuthOrganizationStoreMutationResult<AuthOrganizationRole>>
  _executeRoleMutation(AuthOrganizationRoleMutationCommand command) async {
    final role = command.role;
    await _requireActor(
      command.actorMembership,
      role.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = await _replay(command.idempotency, resultType: 'role');
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(
        value: AuthOrganizationRole.fromJson(_jsonObject(replay.result)),
        replayed: true,
      );
    }
    final creatorRole = _normalizeCreatorRole(command.creatorRole);
    late final AuthOrganizationRole result;
    switch (command.kind) {
      case AuthOrganizationRoleMutationKind.create:
        _require(
          await _findRole(role.organizationId, role.name) == null,
          'role_exists',
        );
        _require(
          !(await _table(_roles).whereEquals('id', role.id).exists()),
          'role_exists',
        );
        _requireLimit(
          await _count(
            _table(_roles).whereEquals('organization_id', role.organizationId),
          ),
          command.roleLimit,
          'role_limit',
        );
        await _insertRole(role);
        result = role;
      case AuthOrganizationRoleMutationKind.update:
        final previousName = command.previousName?.trim() ?? '';
        final existing = await _findRole(role.organizationId, previousName);
        _require(existing != null, 'role_not_found');
        _require(
          command.expectedRole != null &&
              _sameRoleSnapshot(existing!, command.expectedRole!),
          'role_changed',
        );
        final existingRole = existing!;
        _require(!existingRole.predefined, 'predefined_role');
        _require(
          existingRole.name != creatorRole && role.name != creatorRole,
          'creator_role',
        );
        final duplicate = await _findRole(role.organizationId, role.name);
        _require(
          duplicate == null || duplicate.id == existingRole.id,
          'role_exists',
        );
        await _renameRoleReferences(
          role.organizationId,
          existingRole.name,
          role.name,
        );
        await _delete(_roles, {'id': existingRole.id});
        await _insertRole(role);
        result = role;
      case AuthOrganizationRoleMutationKind.delete:
        final existing = await _findRole(role.organizationId, role.name);
        _require(existing != null, 'role_not_found');
        _require(_sameRoleSnapshot(existing!, role), 'role_changed');
        _require(!existing.predefined, 'predefined_role');
        _require(existing.name != creatorRole, 'creator_role');
        _require(
          (await _membersWithRole(role.organizationId, existing.name)).isEmpty,
          'role_in_use',
        );
        _require(
          (await _pendingInvitationsWithRole(
            role.organizationId,
            existing.name,
          )).isEmpty,
          'role_in_use',
        );
        await _delete(_roles, {'id': existing.id});
        result = existing;
    }
    await _remember(
      command.idempotency,
      resultType: 'role',
      result: result.toJson(),
    );
    return AuthOrganizationStoreMutationResult(value: result);
  }

  Future<AuthOrganizationStoreMutationResult<AuthOrganizationTeam>>
  _executeTeamMutation(AuthOrganizationTeamMutationCommand command) async {
    final team = command.team;
    await _requireActor(
      command.actorMembership,
      team.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = await _replay(command.idempotency, resultType: 'team');
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(
        value: AuthOrganizationTeam.fromJson(_jsonObject(replay.result)),
        replayed: true,
      );
    }
    late final AuthOrganizationTeam result;
    switch (command.kind) {
      case AuthOrganizationTeamMutationKind.create:
        _require(
          await _findOrganization(team.organizationId) != null,
          'organization_not_found',
        );
        _require(await _findTeam(team.id) == null, 'team_exists');
        _require(
          !(await _table(_teams)
              .whereEquals('organization_id', team.organizationId)
              .whereILike('name', team.name)
              .exists()),
          'team_exists',
        );
        _requireLimit(
          await _count(
            _table(_teams).whereEquals('organization_id', team.organizationId),
          ),
          command.teamLimit,
          'team_limit',
        );
        await _insertTeam(team);
        result = team;
      case AuthOrganizationTeamMutationKind.update:
        final existing = await _findTeam(team.id);
        _require(existing != null, 'team_not_found');
        _require(
          existing!.organizationId == team.organizationId,
          'organization_forbidden',
        );
        _require(
          command.expectedTeam != null &&
              _sameTeamSnapshot(existing, command.expectedTeam!),
          'team_changed',
        );
        _require(
          !(await _table(_teams)
              .whereEquals('organization_id', team.organizationId)
              .whereILike('name', team.name)
              .whereNotEquals('id', team.id)
              .exists()),
          'team_exists',
        );
        await _update(
          _teams,
          {'id': team.id},
          {
            'name': team.name,
            'attributes': _json(team.attributes),
            'updated_at': _date(team.updatedAt),
          },
        );
        result = team;
      case AuthOrganizationTeamMutationKind.delete:
        final existing = await _findTeam(team.id);
        _require(existing != null, 'team_not_found');
        _require(_sameTeamSnapshot(existing!, team), 'team_changed');
        if (!command.allowLastTeam) {
          _require(
            await _count(
                  _table(
                    _teams,
                  ).whereEquals('organization_id', team.organizationId),
                ) >
                1,
            'last_team',
          );
        }
        await _delete(_teamMembers, {'team_id': team.id});
        await _update(_invitations, {'team_id': team.id}, {'team_id': null});
        await _delete(_teams, {'id': team.id});
        result = existing;
    }
    await _remember(
      command.idempotency,
      resultType: 'team',
      result: result.toJson(),
    );
    return AuthOrganizationStoreMutationResult(value: result);
  }

  Future<AuthOrganizationStoreMutationResult<AuthOrganizationTeamMember>>
  _executeTeamMemberMutation(
    AuthOrganizationTeamMemberMutationCommand command,
  ) async {
    await _requireActor(
      command.actorMembership,
      command.team.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = await _replay(
      command.idempotency,
      resultType: 'team_member',
    );
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(
        value: AuthOrganizationTeamMember.fromJson(_jsonObject(replay.result)),
        replayed: true,
      );
    }
    final currentTeam = await _findTeam(command.team.id);
    _require(currentTeam != null, 'team_not_found');
    _require(_sameTeamSnapshot(currentTeam!, command.team), 'team_changed');
    final member = command.teamMember;
    late final AuthOrganizationTeamMember result;
    switch (command.kind) {
      case AuthOrganizationTeamMemberMutationKind.add:
        _require(member.teamId == currentTeam.id, 'invalid_team_member');
        _require(
          await _findMember(currentTeam.organizationId, member.userId) != null,
          'member_not_found',
        );
        _require(
          await _findTeamMember(member.teamId, member.userId) == null,
          'team_member_exists',
        );
        _requireLimit(
          await _count(
            _table(_teamMembers).whereEquals('team_id', member.teamId),
          ),
          command.memberLimit,
          'team_member_limit',
        );
        await _insertTeamMember(member);
        result = member;
      case AuthOrganizationTeamMemberMutationKind.remove:
        final existing = await _findTeamMember(member.teamId, member.userId);
        _require(existing != null, 'team_member_not_found');
        _require(
          _sameTeamMemberSnapshot(existing!, member),
          'team_member_changed',
        );
        await _delete(_teamMembers, {
          'team_id': member.teamId,
          'user_id': member.userId,
        });
        result = existing;
    }
    await _remember(
      command.idempotency,
      resultType: 'team_member',
      result: result.toJson(),
    );
    return AuthOrganizationStoreMutationResult(value: result);
  }

  Future<void> _requireActor(
    AuthOrganizationMember expected,
    String organizationId,
    List<AuthOrganizationRole> roleSnapshots,
  ) async {
    _require(
      expected.organizationId == organizationId,
      'organization_forbidden',
    );
    final current = await _findMember(organizationId, expected.userId);
    _require(
      current != null && _sameMembershipSnapshot(current, expected),
      'organization_forbidden',
    );
    await _requireRoleSnapshots(current!, roleSnapshots);
  }

  Future<void> _requireRoleSnapshots(
    AuthOrganizationMember actor,
    List<AuthOrganizationRole> snapshots,
  ) async {
    for (final expected in snapshots) {
      _require(
        expected.organizationId == actor.organizationId &&
            actor.roles.contains(expected.name),
        'organization_forbidden',
      );
      final current = await _findRole(expected.organizationId, expected.name);
      _require(
        current != null && _sameRoleSnapshot(current, expected),
        'organization_forbidden',
      );
    }
  }

  Future<_Replay?> _replay(
    AuthOrganizationIdempotency? value, {
    required String resultType,
  }) async {
    if (value == null) return null;
    final normalized = _validateIdempotency(value);
    final rows = await _query(
      _table(_idempotency).whereEquals('key', normalized.key),
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    _require(
      row['organization_id'] == normalized.organizationId &&
          row['actor_id'] == normalized.actorId &&
          row['operation_id'] == normalized.operationId &&
          row['fingerprint'] == normalized.fingerprint,
      'idempotency_key_conflict',
    );
    _require(row['result_type'] == resultType, 'idempotency_key_conflict');
    return _Replay(result: _jsonObject(row['result']));
  }

  Future<void> _remember(
    AuthOrganizationIdempotency? value, {
    required String resultType,
    required Object result,
  }) async {
    if (value == null) return;
    final normalized = _validateIdempotency(value);
    final rows = await _query(
      _table(_idempotency).whereEquals('key', normalized.key),
    );
    if (rows.isEmpty) {
      _require(
        await _count(_table(_idempotency)) < 10000,
        'idempotency_capacity',
      );
      await _insert(_idempotency, {
        'key': normalized.key,
        'organization_id': normalized.organizationId,
        'actor_id': normalized.actorId,
        'operation_id': normalized.operationId,
        'fingerprint': normalized.fingerprint,
        'result_type': resultType,
        'result': _json(result),
        'created_at': _date(DateTime.now()),
      });
    }
  }

  Future<AtomicBatchOperation?> _prepareRememberOperation(
    AuthOrganizationIdempotency? value, {
    required String resultType,
    required Object result,
  }) async {
    if (value == null) return null;
    final normalized = _validateIdempotency(value);
    final rows = await _query(
      _table(_idempotency).whereEquals('key', normalized.key),
    );
    if (rows.isNotEmpty) {
      final row = rows.single;
      _require(
        row['organization_id'] == normalized.organizationId &&
            row['actor_id'] == normalized.actorId &&
            row['operation_id'] == normalized.operationId &&
            row['fingerprint'] == normalized.fingerprint &&
            row['result_type'] == resultType,
        'idempotency_key_conflict',
      );
      return null;
    }
    _require(
      await _count(_table(_idempotency)) < 10000,
      'idempotency_capacity',
    );
    return _table(_idempotency).batchInsert([
      {
        'key': normalized.key,
        'organization_id': normalized.organizationId,
        'actor_id': normalized.actorId,
        'operation_id': normalized.operationId,
        'fingerprint': normalized.fingerprint,
        'result_type': resultType,
        'result': _json(result),
        'created_at': _date(DateTime.now()),
      },
    ], returning: false);
  }

  ({
    String key,
    String organizationId,
    String actorId,
    String operationId,
    String fingerprint,
  })
  _validateIdempotency(AuthOrganizationIdempotency value) {
    final key = value.key.trim();
    _require(
      key.length >= 8 &&
          key.length <= 128 &&
          RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key),
      'invalid_idempotency_key',
    );
    final fields = [
      value.organizationId.trim(),
      value.actorId.trim(),
      value.operationId.trim(),
      value.fingerprint.trim(),
    ];
    _require(
      fields.every((field) => field.isNotEmpty && field.length <= 256),
      'invalid_idempotency_key',
    );
    return (
      key: key,
      organizationId: fields[0],
      actorId: fields[1],
      operationId: fields[2],
      fingerprint: fields[3],
    );
  }

  Future<AuthOrganization?> _findOrganization(String id) async {
    final rows = await _query(
      _table(_organizations).whereEquals('id', id.trim()),
    );
    return rows.isEmpty ? null : _organizationFromRow(rows.single);
  }

  Future<AuthOrganization?> _findOrganizationBySlug(String slug) async {
    final rows = await _query(
      _table(_organizations).whereEquals('slug', slug.trim().toLowerCase()),
    );
    return rows.isEmpty ? null : _organizationFromRow(rows.single);
  }

  Future<AuthOrganizationMember?> _findMember(
    String organizationId,
    String userId,
  ) async {
    final rows = await _query(
      _table(_members)
          .whereEquals('organization_id', organizationId.trim())
          .whereEquals('user_id', userId.trim()),
    );
    return rows.isEmpty ? null : _memberFromRow(rows.single);
  }

  Future<AuthOrganizationInvitation?> _findInvitation(String id) async {
    final rows = await _query(
      _table(_invitations).whereEquals('id', id.trim()),
    );
    return rows.isEmpty ? null : _invitationFromRow(rows.single);
  }

  Future<AuthOrganizationInvitation?> _findPendingInvitation(
    String organizationId,
    String email,
    DateTime now,
  ) async {
    final rows = await _query(
      _table(_invitations)
          .whereEquals('organization_id', organizationId.trim())
          .whereEquals('email', normalizeAuthEmail(email))
          .whereEquals('status', AuthOrganizationInvitationStatus.pending.name)
          .whereGreaterThan('expires_at', _date(now))
          .orderBy('created_at'),
    );
    return rows.isEmpty ? null : _invitationFromRow(rows.single);
  }

  Future<AuthOrganizationRole?> _findRole(
    String organizationId,
    String name,
  ) async {
    final rows = await _query(
      _table(_roles)
          .whereEquals('organization_id', organizationId.trim())
          .whereEquals('name', name.trim().toLowerCase()),
    );
    return rows.isEmpty ? null : _roleFromRow(rows.single);
  }

  Future<AuthOrganizationTeam?> _findTeam(String id) async {
    final rows = await _query(_table(_teams).whereEquals('id', id.trim()));
    return rows.isEmpty ? null : _teamFromRow(rows.single);
  }

  Future<AuthOrganizationTeamMember?> _findTeamMember(
    String teamId,
    String userId,
  ) async {
    final rows = await _query(
      _table(_teamMembers)
          .whereEquals('team_id', teamId.trim())
          .whereEquals('user_id', userId.trim()),
    );
    return rows.isEmpty ? null : _teamMemberFromRow(rows.single);
  }

  Future<int> _count(Query<AdHocRow> query) => query.count();

  Future<int> _countPendingInvitations(String organizationId, DateTime now) =>
      _count(
        _table(_invitations)
            .whereEquals('organization_id', organizationId.trim())
            .whereEquals(
              'status',
              AuthOrganizationInvitationStatus.pending.name,
            )
            .whereGreaterThan('expires_at', _date(now)),
      );

  Future<int> _creatorCount(String organizationId, String role) async {
    final members = await _query(
      _table(_members).whereEquals('organization_id', organizationId.trim()),
    );
    return members.where((row) => _strings(row['roles']).contains(role)).length;
  }

  Future<List<AuthOrganizationMember>> _membersForUser(String userId) async {
    final rows = await _query(
      _table(_members).whereEquals('user_id', userId.trim()),
    );
    return rows.map(_memberFromRow).toList(growable: false);
  }

  Future<List<AuthOrganizationMember>> _membersWithRole(
    String organizationId,
    String role,
  ) async {
    final members = await _query(
      _table(_members).whereEquals('organization_id', organizationId.trim()),
    );
    return members
        .map(_memberFromRow)
        .where((value) => value.roles.contains(role))
        .toList(growable: false);
  }

  Future<List<AuthOrganizationInvitation>> _pendingInvitationsWithRole(
    String organizationId,
    String role,
  ) async {
    final rows = await _query(
      _table(_invitations)
          .whereEquals('organization_id', organizationId.trim())
          .whereEquals('status', AuthOrganizationInvitationStatus.pending.name),
    );
    return rows
        .map(_invitationFromRow)
        .where((value) => value.roles.contains(role))
        .toList(growable: false);
  }

  Future<void> _renameRoleReferences(
    String organizationId,
    String oldName,
    String newName,
  ) async {
    final members = await _query(
      _table(_members).whereEquals('organization_id', organizationId),
    );
    for (final row in members) {
      final member = _memberFromRow(row);
      if (!member.roles.contains(oldName)) continue;
      await _update(
        _members,
        {'organization_id': member.organizationId, 'user_id': member.userId},
        {
          'roles': jsonEncode(
            member.roles
                .map((value) => value == oldName ? newName : value)
                .toList(),
          ),
        },
      );
    }
    final invitations = await _query(
      _table(_invitations)
          .whereEquals('organization_id', organizationId)
          .whereEquals('status', AuthOrganizationInvitationStatus.pending.name),
    );
    for (final row in invitations) {
      final invitation = _invitationFromRow(row);
      if (!invitation.roles.contains(oldName)) continue;
      await _update(
        _invitations,
        {'id': invitation.id},
        {
          'roles': jsonEncode(
            invitation.roles
                .map((value) => value == oldName ? newName : value)
                .toList(),
          ),
        },
      );
    }
  }

  Future<void> _insertOrganization(AuthOrganization value) async {
    await _insert(_organizations, _organizationMap(value));
  }

  Future<void> _insertMember(AuthOrganizationMember value) async {
    await _insert(_members, _memberMap(value));
  }

  Future<void> _insertInvitation(AuthOrganizationInvitation value) async {
    await _insert(_invitations, _invitationMap(value));
  }

  Future<void> _insertRole(AuthOrganizationRole value) async {
    await _insert(_roles, _roleMap(value));
  }

  Future<void> _insertTeam(AuthOrganizationTeam value) async {
    await _insert(_teams, _teamMap(value));
  }

  Future<void> _insertTeamMember(AuthOrganizationTeamMember value) async {
    await _insert(_teamMembers, _teamMemberMap(value));
  }
}

List<AdHocColumn> _tableColumns(String table) {
  AdHocColumn column(
    String name, {
    String? dartType,
    bool nullable = false,
    bool primaryKey = false,
  }) => AdHocColumn(
    name: name,
    dartType: dartType,
    resolvedType: dartType,
    isNullable: nullable,
    isPrimaryKey: primaryKey,
  );

  if (table.endsWith('_organizations')) {
    return [
      column('id', primaryKey: true),
      column('name'),
      column('slug'),
      column('logo', nullable: true),
      column('metadata'),
      column('created_at'),
      column('updated_at'),
    ];
  }
  if (table.endsWith('_organization_members')) {
    return [
      column('db_key', primaryKey: true),
      column('id'),
      column('organization_id'),
      column('user_id'),
      column('roles'),
      column('attributes'),
      column('created_at'),
    ];
  }
  if (table.endsWith('_organization_invitations')) {
    return [
      column('id', primaryKey: true),
      column('organization_id'),
      column('email'),
      column('roles'),
      column('inviter_id'),
      column('status'),
      column('expires_at'),
      column('created_at'),
      column('team_id', nullable: true),
      column('attributes'),
    ];
  }
  if (table.endsWith('_organization_roles')) {
    return [
      column('id', primaryKey: true),
      column('organization_id'),
      column('name'),
      column('permissions'),
      column('predefined', dartType: 'bool'),
      column('created_at'),
      column('updated_at'),
    ];
  }
  if (table.endsWith('_organization_teams')) {
    return [
      column('id', primaryKey: true),
      column('organization_id'),
      column('name'),
      column('attributes'),
      column('created_at'),
      column('updated_at'),
    ];
  }
  if (table.endsWith('_organization_team_members')) {
    return [
      column('db_key', primaryKey: true),
      column('id'),
      column('team_id'),
      column('user_id'),
      column('created_at'),
    ];
  }
  if (table.endsWith('_organization_idempotency')) {
    return [
      column('key', primaryKey: true),
      column('organization_id'),
      column('actor_id'),
      column('operation_id'),
      column('fingerprint'),
      column('result_type'),
      column('result'),
      column('created_at'),
    ];
  }
  throw ArgumentError.value(table, 'table', 'unknown organization table');
}

final class _Replay {
  const _Replay({required this.result});

  final Map<String, dynamic> result;
}

Map<String, Object?> _organizationMap(AuthOrganization value) => {
  'id': value.id,
  'name': value.name,
  'slug': value.slug,
  'logo': value.logo,
  'metadata': _json(value.metadata),
  'created_at': _date(value.createdAt),
  'updated_at': _date(value.updatedAt),
};

Map<String, Object?> _memberMap(AuthOrganizationMember value) => {
  'db_key': _compositeKey([value.organizationId, value.userId]),
  'id': value.id,
  'organization_id': value.organizationId,
  'user_id': value.userId,
  'roles': _json(value.roles),
  'attributes': _json(value.attributes),
  'created_at': _date(value.createdAt),
};

Map<String, Object?> _invitationMap(AuthOrganizationInvitation value) => {
  'id': value.id,
  'organization_id': value.organizationId,
  'email': value.email,
  'roles': _json(value.roles),
  'inviter_id': value.inviterId,
  'status': value.status.name,
  'expires_at': _date(value.expiresAt),
  'created_at': _date(value.createdAt),
  'team_id': value.teamId,
  'attributes': _json(value.attributes),
};

Map<String, Object?> _roleMap(AuthOrganizationRole value) => {
  'id': value.id,
  'organization_id': value.organizationId,
  'name': value.name,
  'permissions': _json(value.permissions),
  'predefined': value.predefined,
  'created_at': _date(value.createdAt),
  'updated_at': _date(value.updatedAt),
};

Map<String, Object?> _teamMap(AuthOrganizationTeam value) => {
  'id': value.id,
  'organization_id': value.organizationId,
  'name': value.name,
  'attributes': _json(value.attributes),
  'created_at': _date(value.createdAt),
  'updated_at': _date(value.updatedAt),
};

Map<String, Object?> _teamMemberMap(AuthOrganizationTeamMember value) => {
  'db_key': _compositeKey([value.teamId, value.userId]),
  'id': value.id,
  'team_id': value.teamId,
  'user_id': value.userId,
  'created_at': _date(value.createdAt),
};

AuthOrganization _organizationFromRow(Map<String, Object?> row) =>
    AuthOrganization(
      id: _string(row['id']),
      name: _string(row['name']),
      slug: _string(row['slug']),
      logo: row['logo']?.toString(),
      metadata: _jsonObject(row['metadata']),
      createdAt: _dateParse(row['created_at']),
      updatedAt: _dateParse(row['updated_at']),
    );

AuthOrganizationMember _memberFromRow(Map<String, Object?> row) =>
    AuthOrganizationMember(
      id: _string(row['id']),
      organizationId: _string(row['organization_id']),
      userId: _string(row['user_id']),
      roles: _strings(row['roles']),
      attributes: _jsonObject(row['attributes']),
      createdAt: _dateParse(row['created_at']),
    );

AuthOrganizationInvitation _invitationFromRow(Map<String, Object?> row) =>
    AuthOrganizationInvitation(
      id: _string(row['id']),
      organizationId: _string(row['organization_id']),
      email: _string(row['email']),
      roles: _strings(row['roles']),
      inviterId: _string(row['inviter_id']),
      status: AuthOrganizationInvitationStatus.values.byName(
        _string(row['status']),
      ),
      expiresAt: _dateParse(row['expires_at']),
      createdAt: _dateParse(row['created_at']),
      teamId: row['team_id']?.toString(),
      attributes: _jsonObject(row['attributes']),
    );

AuthOrganizationRole _roleFromRow(Map<String, Object?> row) =>
    AuthOrganizationRole(
      id: _string(row['id']),
      organizationId: _string(row['organization_id']),
      name: _string(row['name']),
      permissions: _permissionMap(row['permissions']),
      predefined: _boolean(row['predefined']),
      createdAt: _dateParse(row['created_at']),
      updatedAt: _dateParse(row['updated_at']),
    );

AuthOrganizationTeam _teamFromRow(Map<String, Object?> row) =>
    AuthOrganizationTeam(
      id: _string(row['id']),
      organizationId: _string(row['organization_id']),
      name: _string(row['name']),
      attributes: _jsonObject(row['attributes']),
      createdAt: _dateParse(row['created_at']),
      updatedAt: _dateParse(row['updated_at']),
    );

AuthOrganizationTeamMember _teamMemberFromRow(Map<String, Object?> row) =>
    AuthOrganizationTeamMember(
      id: _string(row['id']),
      teamId: _string(row['team_id']),
      userId: _string(row['user_id']),
      createdAt: _dateParse(row['created_at']),
    );

String _json(Object? value) => jsonEncode(value);

String _compositeKey(Iterable<String> values) => jsonEncode(values.toList());

Map<String, dynamic> _jsonObject(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! Map) {
    throw StateError('Organization JSON field is not an object.');
  }
  return <String, dynamic>{
    for (final entry in decoded.entries) '${entry.key}': entry.value,
  };
}

List<String> _strings(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! Iterable) {
    throw StateError('Organization JSON field is not a list.');
  }
  return decoded.map((item) => item.toString()).toList(growable: false);
}

Map<String, Iterable<String>> _permissionMap(Object? value) {
  final decoded = _jsonObject(value);
  return <String, Iterable<String>>{
    for (final entry in decoded.entries) entry.key: _strings(entry.value),
  };
}

String _string(Object? value) {
  final result = value?.toString() ?? '';
  if (result.isEmpty) {
    throw StateError('Organization database row has an empty field.');
  }
  return result;
}

DateTime _dateParse(Object? value) {
  final result = DateTime.tryParse(value?.toString() ?? '');
  if (result == null) {
    throw StateError('Organization database row has an invalid date.');
  }
  return result.toUtc();
}

String _date(DateTime value) => value.toUtc().toIso8601String();

bool _boolean(Object? value) => value is bool ? value : (value as num) != 0;

void _require(bool condition, String code) {
  if (!condition) throw AuthFlowException(code);
}

void _requireLimit(int count, int? limit, String code) {
  if (limit != null && count >= limit) throw AuthFlowException(code);
}

String _normalizeCreatorRole(String value) {
  final normalized = value.trim().toLowerCase();
  _require(normalized.isNotEmpty, 'invalid_role');
  return normalized;
}

bool _sameMembershipSnapshot(
  AuthOrganizationMember a,
  AuthOrganizationMember b,
) =>
    a.id == b.id &&
    a.organizationId == b.organizationId &&
    a.userId == b.userId &&
    _deepEqual(a.roles, b.roles) &&
    _deepEqual(a.attributes, b.attributes) &&
    a.createdAt == b.createdAt;

bool _sameInvitationSnapshot(
  AuthOrganizationInvitation a,
  AuthOrganizationInvitation b,
) =>
    a.id == b.id &&
    a.organizationId == b.organizationId &&
    a.email == b.email &&
    _deepEqual(a.roles, b.roles) &&
    a.inviterId == b.inviterId &&
    a.status == b.status &&
    a.expiresAt == b.expiresAt &&
    a.createdAt == b.createdAt &&
    a.teamId == b.teamId &&
    _deepEqual(a.attributes, b.attributes);

bool _sameRoleSnapshot(AuthOrganizationRole a, AuthOrganizationRole b) =>
    a.id == b.id &&
    a.organizationId == b.organizationId &&
    a.name == b.name &&
    _deepEqual(a.permissions, b.permissions) &&
    a.predefined == b.predefined &&
    a.createdAt == b.createdAt &&
    a.updatedAt == b.updatedAt;

bool _sameTeamSnapshot(AuthOrganizationTeam a, AuthOrganizationTeam b) =>
    a.id == b.id &&
    a.organizationId == b.organizationId &&
    a.name == b.name &&
    _deepEqual(a.attributes, b.attributes) &&
    a.createdAt == b.createdAt &&
    a.updatedAt == b.updatedAt;

bool _sameTeamMemberSnapshot(
  AuthOrganizationTeamMember a,
  AuthOrganizationTeamMember b,
) =>
    a.id == b.id &&
    a.teamId == b.teamId &&
    a.userId == b.userId &&
    a.createdAt == b.createdAt;

bool _deepEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is Iterable && b is Iterable) {
    final left = a.toList();
    final right = b.toList();
    return left.length == right.length &&
        List<int>.generate(
          left.length,
          (index) => index,
        ).every((index) => _deepEqual(left[index], right[index]));
  }
  return a == b;
}

final class _OrmOrganizationDeletionPlan
    implements AuthDurableUserDeletionPlan {
  const _OrmOrganizationDeletionPlan({
    required this.domain,
    required this.userId,
    required this.namespace,
    required this.applyOperation,
  });

  @override
  final AuthUserDeletionDomain domain;

  @override
  final String userId;

  @override
  final String namespace;

  @override
  final FutureOr<void> Function() applyOperation;

  @override
  Future<void> apply() async {
    await applyOperation();
  }
}
