import 'dart:async';

import 'exceptions.dart';
import 'organization_models.dart';
import 'users.dart' show normalizeAuthEmail;

final class AuthOrganizationCreateTransaction {
  const AuthOrganizationCreateTransaction({
    required this.organization,
    required this.creatorMembership,
    required this.organizationLimit,
    this.defaultTeam,
    this.creatorTeamMembership,
  });

  final AuthOrganization organization;
  final AuthOrganizationMember creatorMembership;
  final int? organizationLimit;
  final AuthOrganizationTeam? defaultTeam;
  final AuthOrganizationTeamMember? creatorTeamMembership;
}

final class AuthOrganizationCreateStoredResult {
  const AuthOrganizationCreateStoredResult({
    required this.organization,
    required this.creatorMembership,
    this.defaultTeam,
  });

  final AuthOrganization organization;
  final AuthOrganizationMember creatorMembership;
  final AuthOrganizationTeam? defaultTeam;
}

final class AuthOrganizationInvitationAcceptance {
  const AuthOrganizationInvitationAcceptance({
    required this.invitationId,
    required this.email,
    required this.membership,
    required this.membershipLimit,
    this.teamMembership,
    this.teamMemberLimit,
    required this.now,
  });

  final String invitationId;
  final String email;
  final AuthOrganizationMember membership;
  final int? membershipLimit;
  final AuthOrganizationTeamMember? teamMembership;
  final int? teamMemberLimit;
  final DateTime now;
}

final class AuthOrganizationInvitationAcceptanceResult {
  const AuthOrganizationInvitationAcceptanceResult({
    required this.invitation,
    required this.membership,
    this.teamMembership,
  });

  final AuthOrganizationInvitation invitation;
  final AuthOrganizationMember membership;
  final AuthOrganizationTeamMember? teamMembership;
}

/// Plugin-owned persistence contract. Implementations must preserve the
/// documented atomicity of every mutating method.
abstract interface class AuthOrganizationStore {
  FutureOr<AuthOrganizationCreateStoredResult> createOrganization(
    AuthOrganizationCreateTransaction transaction,
  );
  FutureOr<AuthOrganization?> findOrganization(String organizationId);
  FutureOr<AuthOrganization?> findOrganizationBySlug(String slug);
  FutureOr<List<AuthOrganization>> listOrganizationsForUser(String userId);
  FutureOr<AuthOrganization> updateOrganization(AuthOrganization value);
  FutureOr<AuthOrganization> deleteOrganization(String organizationId);

  FutureOr<AuthOrganizationMember?> findMember(
    String organizationId,
    String userId,
  );
  FutureOr<List<AuthOrganizationMember>> listMembers(String organizationId);
  FutureOr<AuthOrganizationMember> addMember(
    AuthOrganizationMember member, {
    int? membershipLimit,
  });
  FutureOr<AuthOrganizationMember> replaceMemberRoles(
    String organizationId,
    String userId,
    Iterable<String> roles, {
    required String creatorRole,
  });
  FutureOr<AuthOrganizationMember> removeMember(
    String organizationId,
    String userId, {
    required String creatorRole,
  });

  FutureOr<AuthOrganizationInvitation?> findInvitation(String invitationId);
  FutureOr<List<AuthOrganizationInvitation>> listInvitations(
    String organizationId,
  );
  FutureOr<List<AuthOrganizationInvitation>> listInvitationsForEmail(
    String email,
  );
  FutureOr<AuthOrganizationInvitation> createInvitation(
    AuthOrganizationInvitation invitation, {
    int? invitationLimit,
    bool replacePending = false,
  });
  FutureOr<AuthOrganizationInvitation> transitionInvitation(
    String invitationId,
    AuthOrganizationInvitationStatus status, {
    required DateTime now,
  });
  FutureOr<AuthOrganizationInvitationAcceptanceResult> acceptInvitation(
    AuthOrganizationInvitationAcceptance acceptance,
  );

  FutureOr<AuthOrganizationRole?> findRole(String organizationId, String name);
  FutureOr<List<AuthOrganizationRole>> listRoles(String organizationId);
  FutureOr<AuthOrganizationRole> createRole(
    AuthOrganizationRole role, {
    int? roleLimit,
  });

  /// Updates a role atomically. A rename must update both member assignments
  /// and pending invitation assignments in the same transaction.
  FutureOr<AuthOrganizationRole> updateRole(
    AuthOrganizationRole role, {
    required String previousName,
  });

  /// Deletes an unreferenced dynamic role. Member and pending invitation
  /// references must both be treated as active assignments.
  FutureOr<AuthOrganizationRole> deleteRole(String organizationId, String name);

  FutureOr<AuthOrganizationTeam?> findTeam(String teamId);
  FutureOr<List<AuthOrganizationTeam>> listTeams(String organizationId);
  FutureOr<List<AuthOrganizationTeam>> listTeamsForUser(
    String organizationId,
    String userId,
  );
  FutureOr<AuthOrganizationTeam> createTeam(
    AuthOrganizationTeam team, {
    int? teamLimit,
  });
  FutureOr<AuthOrganizationTeam> updateTeam(AuthOrganizationTeam team);
  FutureOr<AuthOrganizationTeam> deleteTeam(
    String teamId, {
    bool allowLastTeam = false,
  });
  FutureOr<AuthOrganizationTeamMember?> findTeamMember(
    String teamId,
    String userId,
  );
  FutureOr<List<AuthOrganizationTeamMember>> listTeamMembers(String teamId);
  FutureOr<AuthOrganizationTeamMember> addTeamMember(
    AuthOrganizationTeamMember member, {
    int? memberLimit,
  });
  FutureOr<AuthOrganizationTeamMember> removeTeamMember(
    String teamId,
    String userId,
  );
}

/// Optional organization namespace support for atomic administrative deletion.
abstract interface class AuthOrganizationUserDeletionStore {
  FutureOr<void> validateUserDeletion(
    String userId, {
    required String creatorRole,
  });
  FutureOr<void> deleteUserData(
    String userId, {
    String? email,
    required String creatorRole,
  });
}

/// Serialized, process-local organization store for tests and development.
final class InMemoryAuthOrganizationStore
    implements AuthOrganizationStore, AuthOrganizationUserDeletionStore {
  final Map<String, AuthOrganization> _organizations = {};
  final Map<String, AuthOrganizationMember> _members = {};
  final Map<String, AuthOrganizationInvitation> _invitations = {};
  final Map<String, AuthOrganizationRole> _roles = {};
  final Map<String, AuthOrganizationTeam> _teams = {};
  final Map<String, AuthOrganizationTeamMember> _teamMembers = {};
  Future<void> _tail = Future<void>.value();

  Future<T> _atomic<T>(FutureOr<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<AuthOrganizationCreateStoredResult> createOrganization(
    AuthOrganizationCreateTransaction transaction,
  ) => _atomic(() {
    final organization = transaction.organization;
    final creator = transaction.creatorMembership;
    _require(
      !_organizations.containsKey(organization.id),
      'organization_exists',
    );
    _require(
      !_organizations.values.any((value) => value.slug == organization.slug),
      'organization_slug_taken',
    );
    _require(
      creator.organizationId == organization.id,
      'invalid_organization_member',
    );
    final count = _members.values
        .where((member) => member.userId == creator.userId)
        .length;
    _requireLimit(count, transaction.organizationLimit, 'organization_limit');
    _require(
      !_members.containsKey(_memberKey(organization.id, creator.userId)),
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

    _organizations[organization.id] = organization;
    _members[_memberKey(organization.id, creator.userId)] = creator;
    if (team != null) _teams[team.id] = team;
    if (teamMember != null) {
      _teamMembers[_teamMemberKey(teamMember.teamId, teamMember.userId)] =
          teamMember;
    }
    return AuthOrganizationCreateStoredResult(
      organization: organization,
      creatorMembership: creator,
      defaultTeam: team,
    );
  });

  @override
  Future<AuthOrganization?> findOrganization(String organizationId) =>
      _atomic(() => _organizations[organizationId.trim()]);

  @override
  Future<AuthOrganization?> findOrganizationBySlug(String slug) => _atomic(() {
    final normalized = slug.trim().toLowerCase();
    return _organizations.values
        .where((organization) => organization.slug == normalized)
        .firstOrNull;
  });

  @override
  Future<List<AuthOrganization>> listOrganizationsForUser(String userId) =>
      _atomic(() {
        final ids = _members.values
            .where((member) => member.userId == userId.trim())
            .map((member) => member.organizationId)
            .toSet();
        final values =
            _organizations.values
                .where((organization) => ids.contains(organization.id))
                .toList(growable: false)
              ..sort((a, b) => a.name.compareTo(b.name));
        return List<AuthOrganization>.unmodifiable(values);
      });

  @override
  Future<AuthOrganization> updateOrganization(AuthOrganization value) =>
      _atomic(() {
        _require(
          _organizations.containsKey(value.id),
          'organization_not_found',
        );
        _require(
          !_organizations.values.any(
            (organization) =>
                organization.id != value.id && organization.slug == value.slug,
          ),
          'organization_slug_taken',
        );
        _organizations[value.id] = value;
        return value;
      });

  @override
  Future<AuthOrganization> deleteOrganization(String organizationId) => _atomic(
    () {
      final id = organizationId.trim();
      final removed = _organizations.remove(id);
      _require(removed != null, 'organization_not_found');
      final teamIds = _teams.values
          .where((team) => team.organizationId == id)
          .map((team) => team.id)
          .toSet();
      _members.removeWhere((_, member) => member.organizationId == id);
      _invitations.removeWhere((_, invite) => invite.organizationId == id);
      _roles.removeWhere((_, role) => role.organizationId == id);
      _teams.removeWhere((_, team) => team.organizationId == id);
      _teamMembers.removeWhere((_, member) => teamIds.contains(member.teamId));
      return removed!;
    },
  );

  @override
  Future<AuthOrganizationMember?> findMember(
    String organizationId,
    String userId,
  ) => _atomic(() => _members[_memberKey(organizationId, userId)]);

  @override
  Future<List<AuthOrganizationMember>> listMembers(String organizationId) =>
      _atomic(
        () => List<AuthOrganizationMember>.unmodifiable(
          _members.values.where(
            (member) => member.organizationId == organizationId.trim(),
          ),
        ),
      );

  @override
  Future<AuthOrganizationMember> addMember(
    AuthOrganizationMember member, {
    int? membershipLimit,
  }) => _atomic(() {
    _require(
      _organizations.containsKey(member.organizationId),
      'organization_not_found',
    );
    final key = _memberKey(member.organizationId, member.userId);
    _require(!_members.containsKey(key), 'member_exists');
    final count = _members.values
        .where((value) => value.organizationId == member.organizationId)
        .length;
    _requireLimit(count, membershipLimit, 'membership_limit');
    _members[key] = member;
    return member;
  });

  @override
  Future<AuthOrganizationMember> replaceMemberRoles(
    String organizationId,
    String userId,
    Iterable<String> roles, {
    required String creatorRole,
  }) => _atomic(() {
    final key = _memberKey(organizationId, userId);
    final member = _members[key];
    _require(member != null, 'member_not_found');
    final normalized = normalizeAuthOrganizationRoles(roles);
    final normalizedCreatorRole = _normalizeCreatorRole(creatorRole);
    _require(normalized.isNotEmpty, 'invalid_role');
    if (member!.roles.contains(normalizedCreatorRole) &&
        !normalized.contains(normalizedCreatorRole)) {
      _require(
        _creatorCount(organizationId, normalizedCreatorRole) > 1,
        'last_owner',
      );
    }
    final updated = member.copyWith(roles: normalized);
    _members[key] = updated;
    return updated;
  });

  @override
  Future<AuthOrganizationMember> removeMember(
    String organizationId,
    String userId, {
    required String creatorRole,
  }) => _atomic(() {
    final key = _memberKey(organizationId, userId);
    final member = _members[key];
    _require(member != null, 'member_not_found');
    final normalizedCreatorRole = _normalizeCreatorRole(creatorRole);
    if (member!.roles.contains(normalizedCreatorRole)) {
      _require(
        _creatorCount(organizationId, normalizedCreatorRole) > 1,
        'last_owner',
      );
    }
    _members.remove(key);
    final teamIds = _teams.values
        .where((team) => team.organizationId == organizationId.trim())
        .map((team) => team.id)
        .toSet();
    _teamMembers.removeWhere(
      (_, value) =>
          value.userId == userId.trim() && teamIds.contains(value.teamId),
    );
    return member;
  });

  @override
  Future<AuthOrganizationInvitation?> findInvitation(String invitationId) =>
      _atomic(() => _invitations[invitationId.trim()]);

  @override
  Future<List<AuthOrganizationInvitation>> listInvitations(
    String organizationId,
  ) => _atomic(
    () => List<AuthOrganizationInvitation>.unmodifiable(
      _invitations.values.where(
        (value) => value.organizationId == organizationId.trim(),
      ),
    ),
  );

  @override
  Future<List<AuthOrganizationInvitation>> listInvitationsForEmail(
    String email,
  ) => _atomic(() {
    final normalized = normalizeAuthEmail(email);
    return List<AuthOrganizationInvitation>.unmodifiable(
      _invitations.values.where((value) => value.email == normalized),
    );
  });

  @override
  Future<AuthOrganizationInvitation> createInvitation(
    AuthOrganizationInvitation invitation, {
    int? invitationLimit,
    bool replacePending = false,
  }) => _atomic(() {
    _require(
      _organizations.containsKey(invitation.organizationId),
      'organization_not_found',
    );
    final existing = _invitations.values
        .where(
          (value) =>
              value.organizationId == invitation.organizationId &&
              value.email == invitation.email &&
              value.isPending(invitation.createdAt),
        )
        .firstOrNull;
    if (existing != null && !replacePending) return existing;
    final count = _invitations.values
        .where(
          (value) =>
              value.organizationId == invitation.organizationId &&
              value.isPending(invitation.createdAt),
        )
        .length;
    if (existing == null) {
      _requireLimit(count, invitationLimit, 'invitation_limit');
    } else {
      _invitations[existing.id] = existing.copyWith(
        status: AuthOrganizationInvitationStatus.canceled,
      );
    }
    _require(!_invitations.containsKey(invitation.id), 'invitation_exists');
    _invitations[invitation.id] = invitation;
    return invitation;
  });

  @override
  Future<AuthOrganizationInvitation> transitionInvitation(
    String invitationId,
    AuthOrganizationInvitationStatus status, {
    required DateTime now,
  }) => _atomic(() {
    final invitation = _invitations[invitationId.trim()];
    _require(invitation != null, 'invitation_not_found');
    _require(invitation!.isPending(now), 'invitation_not_pending');
    final updated = invitation.copyWith(status: status);
    _invitations[invitation.id] = updated;
    return updated;
  });

  @override
  Future<AuthOrganizationInvitationAcceptanceResult> acceptInvitation(
    AuthOrganizationInvitationAcceptance acceptance,
  ) => _atomic(() {
    final invitation = _invitations[acceptance.invitationId.trim()];
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
    final memberKey = _memberKey(membership.organizationId, membership.userId);
    _require(!_members.containsKey(memberKey), 'member_exists');
    final memberCount = _members.values
        .where((member) => member.organizationId == membership.organizationId)
        .length;
    _requireLimit(memberCount, acceptance.membershipLimit, 'membership_limit');

    final teamMembership = acceptance.teamMembership;
    if (teamMembership != null) {
      final team = _teams[teamMembership.teamId];
      _require(
        team != null && team.organizationId == membership.organizationId,
        'team_not_found',
      );
      _require(
        teamMembership.userId == membership.userId,
        'invalid_team_member',
      );
      final key = _teamMemberKey(teamMembership.teamId, teamMembership.userId);
      _require(!_teamMembers.containsKey(key), 'team_member_exists');
      final count = _teamMembers.values
          .where((member) => member.teamId == teamMembership.teamId)
          .length;
      _requireLimit(count, acceptance.teamMemberLimit, 'team_member_limit');
    }

    final accepted = invitation.copyWith(
      status: AuthOrganizationInvitationStatus.accepted,
    );
    _members[memberKey] = membership;
    if (teamMembership != null) {
      _teamMembers[_teamMemberKey(
            teamMembership.teamId,
            teamMembership.userId,
          )] =
          teamMembership;
    }
    _invitations[invitation.id] = accepted;
    return AuthOrganizationInvitationAcceptanceResult(
      invitation: accepted,
      membership: membership,
      teamMembership: teamMembership,
    );
  });

  @override
  Future<AuthOrganizationRole?> findRole(String organizationId, String name) =>
      _atomic(() => _roles[_roleKey(organizationId, name)]);

  @override
  Future<List<AuthOrganizationRole>> listRoles(String organizationId) =>
      _atomic(
        () => List<AuthOrganizationRole>.unmodifiable(
          _roles.values.where(
            (role) => role.organizationId == organizationId.trim(),
          ),
        ),
      );

  @override
  Future<AuthOrganizationRole> createRole(
    AuthOrganizationRole role, {
    int? roleLimit,
  }) => _atomic(() {
    final key = _roleKey(role.organizationId, role.name);
    _require(!_roles.containsKey(key), 'role_exists');
    final count = _roles.values
        .where((value) => value.organizationId == role.organizationId)
        .length;
    _requireLimit(count, roleLimit, 'role_limit');
    _roles[key] = role;
    return role;
  });

  @override
  Future<AuthOrganizationRole> updateRole(
    AuthOrganizationRole role, {
    required String previousName,
  }) => _atomic(() {
    final oldKey = _roleKey(role.organizationId, previousName);
    final existing = _roles[oldKey];
    _require(existing != null, 'role_not_found');
    _require(!existing!.predefined, 'predefined_role');
    final newKey = _roleKey(role.organizationId, role.name);
    _require(oldKey == newKey || !_roles.containsKey(newKey), 'role_exists');
    if (oldKey != newKey) {
      final affected = _members.entries
          .where(
            (entry) =>
                entry.value.organizationId == role.organizationId &&
                entry.value.roles.contains(existing.name),
          )
          .toList(growable: false);
      for (final entry in affected) {
        _members[entry.key] = entry.value.copyWith(
          roles: entry.value.roles.map(
            (value) => value == existing.name ? role.name : value,
          ),
        );
      }
      final invitations = _invitations.entries
          .where(
            (entry) =>
                entry.value.organizationId == role.organizationId &&
                entry.value.status ==
                    AuthOrganizationInvitationStatus.pending &&
                entry.value.roles.contains(existing.name),
          )
          .toList(growable: false);
      for (final entry in invitations) {
        _invitations[entry.key] = entry.value.copyWith(
          roles: entry.value.roles.map(
            (value) => value == existing.name ? role.name : value,
          ),
        );
      }
      _roles.remove(oldKey);
    }
    _roles[newKey] = role;
    return role;
  });

  @override
  Future<AuthOrganizationRole> deleteRole(String organizationId, String name) =>
      _atomic(() {
        final key = _roleKey(organizationId, name);
        final role = _roles[key];
        _require(role != null, 'role_not_found');
        _require(!role!.predefined, 'predefined_role');
        _require(
          !_members.values.any(
            (member) =>
                member.organizationId == organizationId.trim() &&
                member.roles.contains(role.name),
          ),
          'role_in_use',
        );
        _require(
          !_invitations.values.any(
            (invitation) =>
                invitation.organizationId == organizationId.trim() &&
                invitation.status == AuthOrganizationInvitationStatus.pending &&
                invitation.roles.contains(role.name),
          ),
          'role_in_use',
        );
        _roles.remove(key);
        return role;
      });

  @override
  Future<AuthOrganizationTeam?> findTeam(String teamId) =>
      _atomic(() => _teams[teamId.trim()]);

  @override
  Future<List<AuthOrganizationTeam>> listTeams(String organizationId) =>
      _atomic(
        () => List<AuthOrganizationTeam>.unmodifiable(
          _teams.values.where(
            (team) => team.organizationId == organizationId.trim(),
          ),
        ),
      );

  @override
  Future<List<AuthOrganizationTeam>> listTeamsForUser(
    String organizationId,
    String userId,
  ) => _atomic(() {
    final ids = _teamMembers.values
        .where((member) => member.userId == userId.trim())
        .map((member) => member.teamId)
        .toSet();
    return List<AuthOrganizationTeam>.unmodifiable(
      _teams.values.where(
        (team) =>
            team.organizationId == organizationId.trim() &&
            ids.contains(team.id),
      ),
    );
  });

  @override
  Future<AuthOrganizationTeam> createTeam(
    AuthOrganizationTeam team, {
    int? teamLimit,
  }) => _atomic(() {
    _require(
      _organizations.containsKey(team.organizationId),
      'organization_not_found',
    );
    _require(!_teams.containsKey(team.id), 'team_exists');
    _require(
      !_teams.values.any(
        (value) =>
            value.organizationId == team.organizationId &&
            value.name.toLowerCase() == team.name.toLowerCase(),
      ),
      'team_exists',
    );
    final count = _teams.values
        .where((value) => value.organizationId == team.organizationId)
        .length;
    _requireLimit(count, teamLimit, 'team_limit');
    _teams[team.id] = team;
    return team;
  });

  @override
  Future<AuthOrganizationTeam> updateTeam(AuthOrganizationTeam team) =>
      _atomic(() {
        _require(_teams.containsKey(team.id), 'team_not_found');
        _require(
          !_teams.values.any(
            (value) =>
                value.id != team.id &&
                value.organizationId == team.organizationId &&
                value.name.toLowerCase() == team.name.toLowerCase(),
          ),
          'team_exists',
        );
        _teams[team.id] = team;
        return team;
      });

  @override
  Future<AuthOrganizationTeam> deleteTeam(
    String teamId, {
    bool allowLastTeam = false,
  }) => _atomic(() {
    final team = _teams[teamId.trim()];
    _require(team != null, 'team_not_found');
    if (!allowLastTeam) {
      final count = _teams.values
          .where((value) => value.organizationId == team!.organizationId)
          .length;
      _require(count > 1, 'last_team');
    }
    _teams.remove(team!.id);
    _teamMembers.removeWhere((_, member) => member.teamId == team.id);
    _invitations.updateAll((id, invite) {
      if (invite.teamId != team.id) return invite;
      return AuthOrganizationInvitation(
        id: invite.id,
        organizationId: invite.organizationId,
        email: invite.email,
        roles: invite.roles,
        inviterId: invite.inviterId,
        status: invite.status,
        expiresAt: invite.expiresAt,
        createdAt: invite.createdAt,
        attributes: invite.attributes,
      );
    });
    return team;
  });

  @override
  Future<AuthOrganizationTeamMember?> findTeamMember(
    String teamId,
    String userId,
  ) => _atomic(() => _teamMembers[_teamMemberKey(teamId, userId)]);

  @override
  Future<List<AuthOrganizationTeamMember>> listTeamMembers(String teamId) =>
      _atomic(
        () => List<AuthOrganizationTeamMember>.unmodifiable(
          _teamMembers.values.where((member) => member.teamId == teamId.trim()),
        ),
      );

  @override
  Future<AuthOrganizationTeamMember> addTeamMember(
    AuthOrganizationTeamMember member, {
    int? memberLimit,
  }) => _atomic(() {
    final team = _teams[member.teamId];
    _require(team != null, 'team_not_found');
    _require(
      _members.containsKey(_memberKey(team!.organizationId, member.userId)),
      'member_not_found',
    );
    final key = _teamMemberKey(member.teamId, member.userId);
    _require(!_teamMembers.containsKey(key), 'team_member_exists');
    final count = _teamMembers.values
        .where((value) => value.teamId == member.teamId)
        .length;
    _requireLimit(count, memberLimit, 'team_member_limit');
    _teamMembers[key] = member;
    return member;
  });

  @override
  Future<AuthOrganizationTeamMember> removeTeamMember(
    String teamId,
    String userId,
  ) => _atomic(() {
    final removed = _teamMembers.remove(_teamMemberKey(teamId, userId));
    _require(removed != null, 'team_member_not_found');
    return removed!;
  });

  @override
  Future<void> validateUserDeletion(
    String userId, {
    required String creatorRole,
  }) => _atomic(() {
    final normalizedRole = _normalizeCreatorRole(creatorRole);
    for (final member in _members.values.where(
      (member) => member.userId == userId.trim(),
    )) {
      if (member.roles.contains(normalizedRole) &&
          _creatorCount(member.organizationId, normalizedRole) <= 1) {
        throw AuthFlowException('last_owner');
      }
    }
  });

  @override
  Future<void> deleteUserData(
    String userId, {
    String? email,
    required String creatorRole,
  }) => _atomic(() {
    final id = userId.trim();
    final normalizedEmail = email == null ? null : normalizeAuthEmail(email);
    final normalizedRole = _normalizeCreatorRole(creatorRole);
    for (final member in _members.values.where(
      (member) => member.userId == id,
    )) {
      if (member.roles.contains(normalizedRole) &&
          _creatorCount(member.organizationId, normalizedRole) <= 1) {
        throw AuthFlowException('last_owner');
      }
    }
    _members.removeWhere((_, member) => member.userId == id);
    _teamMembers.removeWhere((_, member) => member.userId == id);
    _invitations.removeWhere(
      (_, invitation) =>
          invitation.inviterId == id ||
          normalizedEmail != null && invitation.email == normalizedEmail,
    );
  });

  int _creatorCount(String organizationId, String creatorRole) => _members
      .values
      .where(
        (member) =>
            member.organizationId == organizationId.trim() &&
            member.roles.contains(creatorRole.trim().toLowerCase()),
      )
      .length;
}

String _memberKey(String organizationId, String userId) =>
    '${organizationId.trim()}\u0000${userId.trim()}';
String _roleKey(String organizationId, String name) =>
    '${organizationId.trim()}\u0000${name.trim().toLowerCase()}';
String _teamMemberKey(String teamId, String userId) =>
    '${teamId.trim()}\u0000${userId.trim()}';

String _normalizeCreatorRole(String creatorRole) {
  final normalized = normalizeAuthOrganizationRoles([creatorRole]);
  _require(normalized.isNotEmpty, 'invalid_role');
  return normalized.single;
}

void _require(bool condition, String code) {
  if (!condition) throw AuthFlowException(code);
}

void _requireLimit(int current, int? limit, String code) {
  if (limit != null) _require(current < limit, code);
}
