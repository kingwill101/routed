import 'dart:async';

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'organization_models.dart';
import 'users.dart' show normalizeAuthEmail;

/// Authentication data for auth organization create transaction.
final class AuthOrganizationCreateTransaction {
  /// Creates an instance of AuthOrganizationCreateTransaction.
  const AuthOrganizationCreateTransaction({
    required this.organization,
    required this.creatorMembership,
    required this.organizationLimit,
    this.defaultTeam,
    this.creatorTeamMembership,
    this.idempotency,
  });

  /// The organization associated with this value.
  final AuthOrganization organization;

  /// The creator membership associated with this value.
  final AuthOrganizationMember creatorMembership;

  /// The organization limit associated with this value.
  final int? organizationLimit;

  /// The default team associated with this value.
  final AuthOrganizationTeam? defaultTeam;

  /// The creator team membership associated with this value.
  final AuthOrganizationTeamMember? creatorTeamMembership;

  /// The idempotency associated with this value.
  final AuthOrganizationIdempotency? idempotency;
}

/// A bounded, non-secret retry key bound to one organization mutation.
///
/// Stores must reject reuse when any binding or [fingerprint] differs. The
/// key is an opaque correlation value, not an authentication credential.
final class AuthOrganizationIdempotency {
  /// Creates an instance of AuthOrganizationIdempotency.
  const AuthOrganizationIdempotency({
    required this.key,
    required this.organizationId,
    required this.actorId,
    required this.operationId,
    required this.fingerprint,
  });

  /// The key associated with this value.
  final String key;

  /// The identifier of the organization.
  final String organizationId;

  /// The identifier of actor.
  final String actorId;

  /// The identifier of operation.
  final String operationId;

  /// The fingerprint associated with this value.
  final String fingerprint;
}

/// Result returned by auth organization create stored result.
final class AuthOrganizationCreateStoredResult {
  /// Creates an instance of AuthOrganizationCreateStoredResult.
  const AuthOrganizationCreateStoredResult({
    required this.organization,
    required this.creatorMembership,
    this.defaultTeam,
    this.replayed = false,
  });

  /// The organization associated with this value.
  final AuthOrganization organization;

  /// The creator membership associated with this value.
  final AuthOrganizationMember creatorMembership;

  /// The default team associated with this value.
  final AuthOrganizationTeam? defaultTeam;

  /// The replayed associated with this value.
  final bool replayed;
}

/// Result returned by auth organization store mutation result.
final class AuthOrganizationStoreMutationResult<T> {
  /// Creates an instance of AuthOrganizationStoreMutationResult.
  const AuthOrganizationStoreMutationResult({
    required this.value,
    this.replayed = false,
  });

  /// The value associated with this value.
  final T value;

  /// The replayed associated with this value.
  final bool replayed;
}

/// Authentication data for auth organization invitation acceptance.
final class AuthOrganizationInvitationAcceptance {
  /// Creates an instance of AuthOrganizationInvitationAcceptance.
  const AuthOrganizationInvitationAcceptance({
    required this.invitationId,
    required this.email,
    required this.membership,
    required this.membershipLimit,
    this.teamMembership,
    this.teamMemberLimit,
    required this.now,
  });

  /// The identifier of invitation.
  final String invitationId;

  /// The email associated with this value.
  final String email;

  /// The membership associated with this value.
  final AuthOrganizationMember membership;

  /// The membership limit associated with this value.
  final int? membershipLimit;

  /// The team membership associated with this value.
  final AuthOrganizationTeamMember? teamMembership;

  /// The team member limit associated with this value.
  final int? teamMemberLimit;

  /// The now associated with this value.
  final DateTime now;
}

/// Result returned by auth organization invitation acceptance result.
final class AuthOrganizationInvitationAcceptanceResult {
  /// Creates an instance of AuthOrganizationInvitationAcceptanceResult.
  const AuthOrganizationInvitationAcceptanceResult({
    required this.invitation,
    required this.membership,
    this.teamMembership,
  });

  /// The invitation associated with this value.
  final AuthOrganizationInvitation invitation;

  /// The membership associated with this value.
  final AuthOrganizationMember membership;

  /// The team membership associated with this value.
  final AuthOrganizationTeamMember? teamMembership;
}

/// The ownership-bearing membership change performed by an organization
/// store.
enum AuthOrganizationMembershipMutationKind {
  /// Replace the target membership's complete role set.
  replaceRoles,

  /// Remove the target membership and its team memberships.
  remove,
}

/// One authorization-checked organization membership mutation.
///
/// Stores must compare both membership snapshots and apply the mutation in a
/// single transaction. A mismatch must fail closed; callers must not retry the
/// write with a newly read snapshot without repeating authorization.
final class AuthOrganizationMembershipMutation {
  /// Creates an instance of AuthOrganizationMembershipMutation.
  AuthOrganizationMembershipMutation({
    required this.kind,
    required this.actorMembership,
    required this.targetMembership,
    required this.creatorRole,
    Iterable<String>? replacementRoles,
    Iterable<AuthOrganizationRole> actorRoleSnapshots =
        const <AuthOrganizationRole>[],
  }) : replacementRoles = replacementRoles == null
           ? null
           : normalizeAuthOrganizationRoles(replacementRoles),
       actorRoleSnapshots = List<AuthOrganizationRole>.unmodifiable(
         actorRoleSnapshots,
       );

  /// The kind associated with this value.
  final AuthOrganizationMembershipMutationKind kind;

  /// The actor membership associated with this value.
  final AuthOrganizationMember actorMembership;

  /// The target membership associated with this value.
  final AuthOrganizationMember targetMembership;

  /// The roles assigned to this value.
  final String creatorRole;

  /// The roles assigned to this value.
  final List<String>? replacementRoles;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> actorRoleSnapshots;
}

/// A typed organization-store transaction command.
sealed class AuthOrganizationStoreCommand<TResult> {
  /// Creates an instance of AuthOrganizationStoreCommand.
  const AuthOrganizationStoreCommand();
}

/// Command describing auth organization create invitation command.
final class AuthOrganizationCreateInvitationCommand
    extends
        AuthOrganizationStoreCommand<
          AuthOrganizationStoreMutationResult<AuthOrganizationInvitation>
        > {
  /// Creates an instance of AuthOrganizationCreateInvitationCommand.
  AuthOrganizationCreateInvitationCommand({
    required this.actorMembership,
    required this.invitation,
    required this.invitationLimit,
    required this.replacePending,
    required this.idempotency,
    Iterable<AuthOrganizationRole> actorRoleSnapshots =
        const <AuthOrganizationRole>[],
  }) : actorRoleSnapshots = List<AuthOrganizationRole>.unmodifiable(
         actorRoleSnapshots,
       );

  /// The actor membership associated with this value.
  final AuthOrganizationMember actorMembership;

  /// The invitation associated with this value.
  final AuthOrganizationInvitation invitation;

  /// The invitation limit associated with this value.
  final int? invitationLimit;

  /// The replace pending associated with this value.
  final bool replacePending;

  /// The idempotency associated with this value.
  final AuthOrganizationIdempotency idempotency;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> actorRoleSnapshots;
}

/// Command describing auth organization transition invitation command.
final class AuthOrganizationTransitionInvitationCommand
    extends
        AuthOrganizationStoreCommand<
          AuthOrganizationStoreMutationResult<AuthOrganizationInvitation>
        > {
  /// Creates an instance of AuthOrganizationTransitionInvitationCommand.
  AuthOrganizationTransitionInvitationCommand({
    required this.expectedInvitation,
    required this.status,
    required this.now,
    required this.actorId,
    this.actorMembership,
    this.actorEmail,
    Iterable<AuthOrganizationRole> actorRoleSnapshots =
        const <AuthOrganizationRole>[],
  }) : actorRoleSnapshots = List<AuthOrganizationRole>.unmodifiable(
         actorRoleSnapshots,
       );

  /// The expected invitation associated with this value.
  final AuthOrganizationInvitation expectedInvitation;

  /// The status associated with this value.
  final AuthOrganizationInvitationStatus status;

  /// The now associated with this value.
  final DateTime now;

  /// The identifier of actor.
  final String actorId;

  /// The actor membership associated with this value.
  final AuthOrganizationMember? actorMembership;

  /// The actor email associated with this value.
  final String? actorEmail;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> actorRoleSnapshots;
}

/// Authentication data for auth organization role mutation kind.
enum AuthOrganizationRoleMutationKind {
  /// A value representing create.
  create,

  /// A value representing update.
  update,

  /// A value representing delete.
  delete,
}

/// Command describing auth organization role mutation command.
final class AuthOrganizationRoleMutationCommand
    extends
        AuthOrganizationStoreCommand<
          AuthOrganizationStoreMutationResult<AuthOrganizationRole>
        > {
  /// Creates an instance of AuthOrganizationRoleMutationCommand.
  AuthOrganizationRoleMutationCommand({
    required this.kind,
    required this.actorMembership,
    required this.role,
    required this.creatorRole,
    this.expectedRole,
    this.previousName,
    this.roleLimit,
    this.idempotency,
    Iterable<AuthOrganizationRole> actorRoleSnapshots =
        const <AuthOrganizationRole>[],
  }) : actorRoleSnapshots = List<AuthOrganizationRole>.unmodifiable(
         actorRoleSnapshots,
       );

  /// The kind associated with this value.
  final AuthOrganizationRoleMutationKind kind;

  /// The actor membership associated with this value.
  final AuthOrganizationMember actorMembership;

  /// The roles assigned to this value.
  final AuthOrganizationRole role;

  /// The roles assigned to this value.
  final AuthOrganizationRole? expectedRole;

  /// The roles assigned to this value.
  final String creatorRole;

  /// The previous name associated with this value.
  final String? previousName;

  /// The roles assigned to this value.
  final int? roleLimit;

  /// The idempotency associated with this value.
  final AuthOrganizationIdempotency? idempotency;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> actorRoleSnapshots;
}

/// Authentication data for auth organization team mutation kind.
enum AuthOrganizationTeamMutationKind {
  /// A value representing create.
  create,

  /// A value representing update.
  update,

  /// A value representing delete.
  delete,
}

/// Command describing auth organization team mutation command.
final class AuthOrganizationTeamMutationCommand
    extends
        AuthOrganizationStoreCommand<
          AuthOrganizationStoreMutationResult<AuthOrganizationTeam>
        > {
  /// Creates an instance of AuthOrganizationTeamMutationCommand.
  AuthOrganizationTeamMutationCommand({
    required this.kind,
    required this.actorMembership,
    required this.team,
    this.expectedTeam,
    this.teamLimit,
    this.allowLastTeam = false,
    this.idempotency,
    Iterable<AuthOrganizationRole> actorRoleSnapshots =
        const <AuthOrganizationRole>[],
  }) : actorRoleSnapshots = List<AuthOrganizationRole>.unmodifiable(
         actorRoleSnapshots,
       );

  /// The kind associated with this value.
  final AuthOrganizationTeamMutationKind kind;

  /// The actor membership associated with this value.
  final AuthOrganizationMember actorMembership;

  /// The team associated with this value.
  final AuthOrganizationTeam team;

  /// The expected team associated with this value.
  final AuthOrganizationTeam? expectedTeam;

  /// The team limit associated with this value.
  final int? teamLimit;

  /// The allow last team associated with this value.
  final bool allowLastTeam;

  /// The idempotency associated with this value.
  final AuthOrganizationIdempotency? idempotency;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> actorRoleSnapshots;
}

/// Authentication data for auth organization team member mutation kind.
enum AuthOrganizationTeamMemberMutationKind {
  /// A value representing add.
  add,

  /// A value representing remove.
  remove,
}

/// Command describing auth organization team member mutation command.
final class AuthOrganizationTeamMemberMutationCommand
    extends
        AuthOrganizationStoreCommand<
          AuthOrganizationStoreMutationResult<AuthOrganizationTeamMember>
        > {
  /// Creates an instance of AuthOrganizationTeamMemberMutationCommand.
  AuthOrganizationTeamMemberMutationCommand({
    required this.kind,
    required this.actorMembership,
    required this.team,
    required this.teamMember,
    this.memberLimit,
    this.idempotency,
    Iterable<AuthOrganizationRole> actorRoleSnapshots =
        const <AuthOrganizationRole>[],
  }) : actorRoleSnapshots = List<AuthOrganizationRole>.unmodifiable(
         actorRoleSnapshots,
       );

  /// The kind associated with this value.
  final AuthOrganizationTeamMemberMutationKind kind;

  /// The actor membership associated with this value.
  final AuthOrganizationMember actorMembership;

  /// The team associated with this value.
  final AuthOrganizationTeam team;

  /// The team member associated with this value.
  final AuthOrganizationTeamMember teamMember;

  /// The member limit associated with this value.
  final int? memberLimit;

  /// The idempotency associated with this value.
  final AuthOrganizationIdempotency? idempotency;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> actorRoleSnapshots;
}

/// Plugin-owned persistence contract. Implementations must preserve the
/// documented atomicity of every mutating method.
abstract interface class AuthOrganizationStore {
  /// Creates organization.
  FutureOr<AuthOrganizationCreateStoredResult> createOrganization(
    AuthOrganizationCreateTransaction transaction,
  );

  /// Looks up organization.
  FutureOr<AuthOrganization?> findOrganization(String organizationId);

  /// Looks up organization by slug.
  FutureOr<AuthOrganization?> findOrganizationBySlug(String slug);

  /// Lists organizations for user.
  FutureOr<List<AuthOrganization>> listOrganizationsForUser(String userId);

  /// Updates organization.
  FutureOr<AuthOrganization> updateOrganization(AuthOrganization value);

  /// Deletes organization.
  FutureOr<AuthOrganization> deleteOrganization(String organizationId);

  /// Looks up member.
  FutureOr<AuthOrganizationMember?> findMember(
    String organizationId,
    String userId,
  );

  /// Lists members.
  FutureOr<List<AuthOrganizationMember>> listMembers(String organizationId);

  /// Adds member.
  FutureOr<AuthOrganizationMember> addMember(
    AuthOrganizationMember member, {
    int? membershipLimit,
  });

  /// Looks up invitation.
  FutureOr<AuthOrganizationInvitation?> findInvitation(String invitationId);

  /// Lists invitations.
  FutureOr<List<AuthOrganizationInvitation>> listInvitations(
    String organizationId,
  );

  /// Lists invitations for email.
  FutureOr<List<AuthOrganizationInvitation>> listInvitationsForEmail(
    String email,
  );

  /// Creates invitation.
  FutureOr<AuthOrganizationInvitation> createInvitation(
    AuthOrganizationInvitation invitation, {
    int? invitationLimit,
    bool replacePending = false,
  });

  /// Performs the transition invitation operation.
  FutureOr<AuthOrganizationInvitation> transitionInvitation(
    String invitationId,
    AuthOrganizationInvitationStatus status, {
    required DateTime now,
  });

  /// Performs the accept invitation operation.
  FutureOr<AuthOrganizationInvitationAcceptanceResult> acceptInvitation(
    AuthOrganizationInvitationAcceptance acceptance,
  );

  /// Looks up role.
  FutureOr<AuthOrganizationRole?> findRole(String organizationId, String name);

  /// Lists roles.
  FutureOr<List<AuthOrganizationRole>> listRoles(String organizationId);

  /// Creates role.
  FutureOr<AuthOrganizationRole> createRole(
    AuthOrganizationRole role, {
    int? roleLimit,
  });

  /// Updates a role atomically. A rename must update both member assignments
  /// and pending invitation assignments in the same transaction.
  FutureOr<AuthOrganizationRole> updateRole(
    AuthOrganizationRole role, {
    required String previousName,
    required String creatorRole,
  });

  /// Deletes an unreferenced dynamic role. Member and pending invitation
  /// references must both be treated as active assignments.
  FutureOr<AuthOrganizationRole> deleteRole(
    String organizationId,
    String name, {
    required String creatorRole,
  });

  /// Looks up team.
  FutureOr<AuthOrganizationTeam?> findTeam(String teamId);

  /// Lists teams.
  FutureOr<List<AuthOrganizationTeam>> listTeams(String organizationId);

  /// Lists teams for user.
  FutureOr<List<AuthOrganizationTeam>> listTeamsForUser(
    String organizationId,
    String userId,
  );

  /// Creates team.
  FutureOr<AuthOrganizationTeam> createTeam(
    AuthOrganizationTeam team, {
    int? teamLimit,
  });

  /// Updates team.
  FutureOr<AuthOrganizationTeam> updateTeam(AuthOrganizationTeam team);

  /// Deletes team.
  FutureOr<AuthOrganizationTeam> deleteTeam(
    String teamId, {
    bool allowLastTeam = false,
  });

  /// Looks up team member.
  FutureOr<AuthOrganizationTeamMember?> findTeamMember(
    String teamId,
    String userId,
  );

  /// Lists team members.
  FutureOr<List<AuthOrganizationTeamMember>> listTeamMembers(String teamId);

  /// Adds team member.
  FutureOr<AuthOrganizationTeamMember> addTeamMember(
    AuthOrganizationTeamMember member, {
    int? memberLimit,
  });

  /// Deletes team member.
  FutureOr<AuthOrganizationTeamMember> removeTeamMember(
    String teamId,
    String userId,
  );
}

/// Required capability for ownership-bearing membership writes.
///
/// Organization plugins fail closed when a durable adapter does not implement
/// this capability. Implementations must validate the actor and target
/// snapshots, preserve at least one [AuthOrganizationMembershipMutation.creatorRole]
/// member, and apply the write atomically.
abstract interface class AuthOrganizationMembershipMutationStore {
  /// Performs the mutate organization membership operation.
  FutureOr<AuthOrganizationMember> mutateOrganizationMembership(
    AuthOrganizationMembershipMutation mutation,
  );
}

/// Required capability for organization mutations whose authorization and
/// invariants must be checked in the same durable transaction as the write.
abstract interface class AuthOrganizationAtomicMutationStore {
  /// Executes organization mutation.
  FutureOr<TResult> executeOrganizationMutation<TResult>(
    AuthOrganizationStoreCommand<TResult> command,
  );
}

/// Optional organization namespace support for atomic administrative deletion.
abstract interface class AuthOrganizationUserDeletionStore {
  /// Validates user deletion.
  FutureOr<void> validateUserDeletion(
    String userId, {
    required String creatorRole,
  });

  /// Deletes user data.
  FutureOr<void> deleteUserData(
    String userId, {
    String? email,
    required String creatorRole,
  });
}

/// Serialized, process-local organization store for tests and development.
final class InMemoryAuthOrganizationStore
    implements
        AuthOrganizationStore,
        AuthOrganizationAtomicMutationStore,
        AuthOrganizationMembershipMutationStore,
        AuthOrganizationUserDeletionStore,
        AuthInMemoryDeletionState {
  /// Creates an instance of InMemoryAuthOrganizationStore.
  InMemoryAuthOrganizationStore({void Function(String stage)? failureInjector})
    : _failureInjector = failureInjector;

  final Map<String, AuthOrganization> _organizations = {};
  final Map<String, AuthOrganizationMember> _members = {};
  final Map<String, AuthOrganizationInvitation> _invitations = {};
  final Map<String, AuthOrganizationRole> _roles = {};
  final Map<String, AuthOrganizationTeam> _teams = {};
  final Map<String, AuthOrganizationTeamMember> _teamMembers = {};
  final Map<String, _AuthOrganizationIdempotencyRecord> _idempotency = {};
  final void Function(String stage)? _failureInjector;
  Future<void> _tail = Future<void>.value();

  /// Captures deletion state.
  @override
  Object captureDeletionState() => (
    organizations: Map<String, AuthOrganization>.of(_organizations),
    members: Map<String, AuthOrganizationMember>.of(_members),
    invitations: Map<String, AuthOrganizationInvitation>.of(_invitations),
    roles: Map<String, AuthOrganizationRole>.of(_roles),
    teams: Map<String, AuthOrganizationTeam>.of(_teams),
    teamMembers: Map<String, AuthOrganizationTeamMember>.of(_teamMembers),
    idempotency: Map<String, _AuthOrganizationIdempotencyRecord>.of(
      _idempotency,
    ),
  );

  /// Restores deletion state.
  @override
  void restoreDeletionState(Object checkpoint) {
    final value = checkpoint as _AuthOrganizationStoreCheckpoint;
    _organizations
      ..clear()
      ..addAll(value.organizations);
    _members
      ..clear()
      ..addAll(value.members);
    _invitations
      ..clear()
      ..addAll(value.invitations);
    _roles
      ..clear()
      ..addAll(value.roles);
    _teams
      ..clear()
      ..addAll(value.teams);
    _teamMembers
      ..clear()
      ..addAll(value.teamMembers);
    _idempotency
      ..clear()
      ..addAll(value.idempotency);
  }

  Future<T> _atomic<T>(FutureOr<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      final checkpoint = captureDeletionState();
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        restoreDeletionState(checkpoint);
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Creates organization.
  @override
  Future<AuthOrganizationCreateStoredResult> createOrganization(
    AuthOrganizationCreateTransaction transaction,
  ) => _atomic(() {
    final replay = _replay<AuthOrganizationCreateStoredResult>(
      transaction.idempotency,
    );
    if (replay != null) {
      return AuthOrganizationCreateStoredResult(
        organization: replay.organization,
        creatorMembership: replay.creatorMembership,
        defaultTeam: replay.defaultTeam,
        replayed: true,
      );
    }
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
    final result = AuthOrganizationCreateStoredResult(
      organization: organization,
      creatorMembership: creator,
      defaultTeam: team,
    );
    _remember(transaction.idempotency, result);
    return result;
  });

  /// Looks up organization.
  @override
  Future<AuthOrganization?> findOrganization(String organizationId) =>
      _atomic(() => _organizations[organizationId.trim()]);

  /// Looks up organization by slug.
  @override
  Future<AuthOrganization?> findOrganizationBySlug(String slug) => _atomic(() {
    final normalized = slug.trim().toLowerCase();
    return _organizations.values
        .where((organization) => organization.slug == normalized)
        .firstOrNull;
  });

  /// Lists organizations for user.
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

  /// Updates organization.
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

  /// Deletes organization.
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

  /// Looks up member.
  @override
  Future<AuthOrganizationMember?> findMember(
    String organizationId,
    String userId,
  ) => _atomic(() => _members[_memberKey(organizationId, userId)]);

  /// Lists members.
  @override
  Future<List<AuthOrganizationMember>> listMembers(String organizationId) =>
      _atomic(
        () => List<AuthOrganizationMember>.unmodifiable(
          _members.values.where(
            (member) => member.organizationId == organizationId.trim(),
          ),
        ),
      );

  /// Adds member.
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

  /// Performs the mutate organization membership operation.
  @override
  Future<AuthOrganizationMember> mutateOrganizationMembership(
    AuthOrganizationMembershipMutation mutation,
  ) => _atomic(() {
    final actorSnapshot = mutation.actorMembership;
    final targetSnapshot = mutation.targetMembership;
    final organizationId = actorSnapshot.organizationId.trim();
    _require(
      organizationId.isNotEmpty &&
          targetSnapshot.organizationId.trim() == organizationId,
      'invalid_organization_member',
    );
    _require(
      _organizations.containsKey(organizationId),
      'organization_not_found',
    );
    final actor = _members[_memberKey(organizationId, actorSnapshot.userId)];
    if (actor == null || !_sameMembershipSnapshot(actor, actorSnapshot)) {
      throw AuthFlowException('organization_forbidden');
    }
    _requireRoleSnapshots(actor, mutation.actorRoleSnapshots);
    final targetKey = _memberKey(organizationId, targetSnapshot.userId);
    final target = _members[targetKey];
    if (target == null) throw AuthFlowException('member_not_found');
    _require(
      _sameMembershipSnapshot(target, targetSnapshot),
      'organization_membership_changed',
    );

    final creatorRole = _normalizeCreatorRole(mutation.creatorRole);
    final replacementRoles = mutation.replacementRoles;
    switch (mutation.kind) {
      case AuthOrganizationMembershipMutationKind.replaceRoles:
        _require(replacementRoles != null, 'invalid_role');
        _require(replacementRoles!.isNotEmpty, 'invalid_role');
        break;
      case AuthOrganizationMembershipMutationKind.remove:
        _require(replacementRoles == null, 'invalid_role');
        break;
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
      _require(_creatorCount(organizationId, creatorRole) > 1, 'last_owner');
    }

    switch (mutation.kind) {
      case AuthOrganizationMembershipMutationKind.replaceRoles:
        final updated = target.copyWith(roles: replacementRoles);
        _members[targetKey] = updated;
        return updated;
      case AuthOrganizationMembershipMutationKind.remove:
        _members.remove(targetKey);
        final teamIds = _teams.values
            .where((team) => team.organizationId == organizationId)
            .map((team) => team.id)
            .toSet();
        _teamMembers.removeWhere(
          (_, value) =>
              value.userId == target.userId && teamIds.contains(value.teamId),
        );
        return target;
    }
  });

  /// Looks up invitation.
  @override
  Future<AuthOrganizationInvitation?> findInvitation(String invitationId) =>
      _atomic(() => _invitations[invitationId.trim()]);

  /// Lists invitations.
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

  /// Lists invitations for email.
  @override
  Future<List<AuthOrganizationInvitation>> listInvitationsForEmail(
    String email,
  ) => _atomic(() {
    final normalized = normalizeAuthEmail(email);
    return List<AuthOrganizationInvitation>.unmodifiable(
      _invitations.values.where((value) => value.email == normalized),
    );
  });

  /// Creates invitation.
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

  /// Performs the transition invitation operation.
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

  /// Performs the accept invitation operation.
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

  /// Looks up role.
  @override
  Future<AuthOrganizationRole?> findRole(String organizationId, String name) =>
      _atomic(() => _roles[_roleKey(organizationId, name)]);

  /// Lists roles.
  @override
  Future<List<AuthOrganizationRole>> listRoles(String organizationId) =>
      _atomic(
        () => List<AuthOrganizationRole>.unmodifiable(
          _roles.values.where(
            (role) => role.organizationId == organizationId.trim(),
          ),
        ),
      );

  /// Creates role.
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

  /// Updates role.
  @override
  Future<AuthOrganizationRole> updateRole(
    AuthOrganizationRole role, {
    required String previousName,
    required String creatorRole,
  }) => _atomic(() {
    final oldKey = _roleKey(role.organizationId, previousName);
    final existing = _roles[oldKey];
    _require(existing != null, 'role_not_found');
    _require(!existing!.predefined, 'predefined_role');
    final normalizedCreatorRole = _normalizeCreatorRole(creatorRole);
    _require(
      existing.name != normalizedCreatorRole &&
          role.name != normalizedCreatorRole,
      'creator_role',
    );
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

  /// Deletes role.
  @override
  Future<AuthOrganizationRole> deleteRole(
    String organizationId,
    String name, {
    required String creatorRole,
  }) => _atomic(() {
    final key = _roleKey(organizationId, name);
    final role = _roles[key];
    _require(role != null, 'role_not_found');
    _require(!role!.predefined, 'predefined_role');
    _require(role.name != _normalizeCreatorRole(creatorRole), 'creator_role');
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

  /// Looks up team.
  @override
  Future<AuthOrganizationTeam?> findTeam(String teamId) =>
      _atomic(() => _teams[teamId.trim()]);

  /// Lists teams.
  @override
  Future<List<AuthOrganizationTeam>> listTeams(String organizationId) =>
      _atomic(
        () => List<AuthOrganizationTeam>.unmodifiable(
          _teams.values.where(
            (team) => team.organizationId == organizationId.trim(),
          ),
        ),
      );

  /// Lists teams for user.
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

  /// Creates team.
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

  /// Updates team.
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

  /// Deletes team.
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

  /// Looks up team member.
  @override
  Future<AuthOrganizationTeamMember?> findTeamMember(
    String teamId,
    String userId,
  ) => _atomic(() => _teamMembers[_teamMemberKey(teamId, userId)]);

  /// Lists team members.
  @override
  Future<List<AuthOrganizationTeamMember>> listTeamMembers(String teamId) =>
      _atomic(
        () => List<AuthOrganizationTeamMember>.unmodifiable(
          _teamMembers.values.where((member) => member.teamId == teamId.trim()),
        ),
      );

  /// Adds team member.
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

  /// Deletes team member.
  @override
  Future<AuthOrganizationTeamMember> removeTeamMember(
    String teamId,
    String userId,
  ) => _atomic(() {
    final removed = _teamMembers.remove(_teamMemberKey(teamId, userId));
    _require(removed != null, 'team_member_not_found');
    return removed!;
  });

  /// Executes organization mutation.
  @override
  Future<TResult> executeOrganizationMutation<TResult>(
    AuthOrganizationStoreCommand<TResult> command,
  ) => _atomic(() {
    final Object result = switch (command) {
      AuthOrganizationCreateInvitationCommand value => _executeCreateInvitation(
        value,
      ),
      AuthOrganizationTransitionInvitationCommand value =>
        _executeTransitionInvitation(value),
      AuthOrganizationRoleMutationCommand value => _executeRoleMutation(value),
      AuthOrganizationTeamMutationCommand value => _executeTeamMutation(value),
      AuthOrganizationTeamMemberMutationCommand value =>
        _executeTeamMemberMutation(value),
    };
    return result as TResult;
  });

  AuthOrganizationStoreMutationResult<AuthOrganizationInvitation>
  _executeCreateInvitation(AuthOrganizationCreateInvitationCommand command) {
    final invitation = command.invitation;
    _requireActor(
      command.actorMembership,
      invitation.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = _replay<AuthOrganizationInvitation>(command.idempotency);
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(value: replay, replayed: true);
    }
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
    if (existing != null && !command.replacePending) {
      _remember(command.idempotency, existing);
      return AuthOrganizationStoreMutationResult(value: existing);
    }
    final count = _invitations.values
        .where(
          (value) =>
              value.organizationId == invitation.organizationId &&
              value.isPending(invitation.createdAt),
        )
        .length;
    if (existing == null) {
      _requireLimit(count, command.invitationLimit, 'invitation_limit');
    } else {
      _invitations[existing.id] = existing.copyWith(
        status: AuthOrganizationInvitationStatus.canceled,
      );
      _stage('invitation.replace.after-cancel');
    }
    _require(!_invitations.containsKey(invitation.id), 'invitation_exists');
    _invitations[invitation.id] = invitation;
    _remember(command.idempotency, invitation);
    return AuthOrganizationStoreMutationResult(value: invitation);
  }

  AuthOrganizationStoreMutationResult<AuthOrganizationInvitation>
  _executeTransitionInvitation(
    AuthOrganizationTransitionInvitationCommand command,
  ) {
    final expected = command.expectedInvitation;
    final current = _invitations[expected.id.trim()];
    _require(current != null, 'invitation_not_found');
    _require(_sameInvitationSnapshot(current!, expected), 'invitation_changed');
    _require(current.isPending(command.now), 'invitation_not_pending');
    final actorMembership = command.actorMembership;
    if (actorMembership != null) {
      _requireActor(
        actorMembership,
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
    _invitations[current.id] = updated;
    return AuthOrganizationStoreMutationResult(value: updated);
  }

  AuthOrganizationStoreMutationResult<AuthOrganizationRole>
  _executeRoleMutation(AuthOrganizationRoleMutationCommand command) {
    final role = command.role;
    _requireActor(
      command.actorMembership,
      role.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = _replay<AuthOrganizationRole>(command.idempotency);
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(value: replay, replayed: true);
    }
    final creatorRole = _normalizeCreatorRole(command.creatorRole);
    final result = switch (command.kind) {
      AuthOrganizationRoleMutationKind.create => () {
        final key = _roleKey(role.organizationId, role.name);
        _require(!_roles.containsKey(key), 'role_exists');
        final count = _roles.values
            .where((value) => value.organizationId == role.organizationId)
            .length;
        _requireLimit(count, command.roleLimit, 'role_limit');
        _roles[key] = role;
        return role;
      }(),
      AuthOrganizationRoleMutationKind.update => () {
        final previousName = command.previousName?.trim() ?? '';
        final oldKey = _roleKey(role.organizationId, previousName);
        final existing = _roles[oldKey];
        if (existing == null) throw AuthFlowException('role_not_found');
        final expected = command.expectedRole;
        _require(
          expected != null && _sameRoleSnapshot(existing, expected),
          'role_changed',
        );
        _require(!existing.predefined, 'predefined_role');
        _require(
          existing.name != creatorRole && role.name != creatorRole,
          'creator_role',
        );
        final newKey = _roleKey(role.organizationId, role.name);
        _require(
          oldKey == newKey || !_roles.containsKey(newKey),
          'role_exists',
        );
        if (oldKey != newKey) {
          for (final entry
              in _members.entries
                  .where(
                    (entry) =>
                        entry.value.organizationId == role.organizationId &&
                        entry.value.roles.contains(existing.name),
                  )
                  .toList(growable: false)) {
            _members[entry.key] = entry.value.copyWith(
              roles: entry.value.roles.map(
                (value) => value == existing.name ? role.name : value,
              ),
            );
          }
          _stage('role.rename.after-members');
          for (final entry
              in _invitations.entries
                  .where(
                    (entry) =>
                        entry.value.organizationId == role.organizationId &&
                        entry.value.status ==
                            AuthOrganizationInvitationStatus.pending &&
                        entry.value.roles.contains(existing.name),
                  )
                  .toList(growable: false)) {
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
      }(),
      AuthOrganizationRoleMutationKind.delete => () {
        final key = _roleKey(role.organizationId, role.name);
        final existing = _roles[key];
        _require(existing != null, 'role_not_found');
        _require(_sameRoleSnapshot(existing!, role), 'role_changed');
        _require(!existing.predefined, 'predefined_role');
        _require(existing.name != creatorRole, 'creator_role');
        _require(
          !_members.values.any(
                (member) =>
                    member.organizationId == role.organizationId &&
                    member.roles.contains(existing.name),
              ) &&
              !_invitations.values.any(
                (invitation) =>
                    invitation.organizationId == role.organizationId &&
                    invitation.status ==
                        AuthOrganizationInvitationStatus.pending &&
                    invitation.roles.contains(existing.name),
              ),
          'role_in_use',
        );
        _roles.remove(key);
        return existing;
      }(),
    };
    _remember(command.idempotency, result);
    return AuthOrganizationStoreMutationResult(value: result);
  }

  AuthOrganizationStoreMutationResult<AuthOrganizationTeam>
  _executeTeamMutation(AuthOrganizationTeamMutationCommand command) {
    final team = command.team;
    _requireActor(
      command.actorMembership,
      team.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = _replay<AuthOrganizationTeam>(command.idempotency);
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(value: replay, replayed: true);
    }
    final result = switch (command.kind) {
      AuthOrganizationTeamMutationKind.create => () {
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
        _requireLimit(count, command.teamLimit, 'team_limit');
        _teams[team.id] = team;
        return team;
      }(),
      AuthOrganizationTeamMutationKind.update => () {
        final existing = _teams[team.id];
        if (existing == null) throw AuthFlowException('team_not_found');
        _require(
          existing.organizationId == team.organizationId,
          'organization_forbidden',
        );
        final expected = command.expectedTeam;
        _require(
          expected != null && _sameTeamSnapshot(existing, expected),
          'team_changed',
        );
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
      }(),
      AuthOrganizationTeamMutationKind.delete => () {
        final existing = _teams[team.id];
        _require(existing != null, 'team_not_found');
        _require(_sameTeamSnapshot(existing!, team), 'team_changed');
        if (!command.allowLastTeam) {
          final count = _teams.values
              .where((value) => value.organizationId == team.organizationId)
              .length;
          _require(count > 1, 'last_team');
        }
        _teams.remove(team.id);
        _teamMembers.removeWhere((_, member) => member.teamId == team.id);
        _stage('team.delete.after-members');
        _invitations.updateAll((_, invite) {
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
        return existing;
      }(),
    };
    _remember(command.idempotency, result);
    return AuthOrganizationStoreMutationResult(value: result);
  }

  AuthOrganizationStoreMutationResult<AuthOrganizationTeamMember>
  _executeTeamMemberMutation(
    AuthOrganizationTeamMemberMutationCommand command,
  ) {
    _requireActor(
      command.actorMembership,
      command.team.organizationId,
      command.actorRoleSnapshots,
    );
    final replay = _replay<AuthOrganizationTeamMember>(command.idempotency);
    if (replay != null) {
      return AuthOrganizationStoreMutationResult(value: replay, replayed: true);
    }
    final currentTeam = _teams[command.team.id];
    _require(currentTeam != null, 'team_not_found');
    _require(_sameTeamSnapshot(currentTeam!, command.team), 'team_changed');
    final member = command.teamMember;
    final key = _teamMemberKey(member.teamId, member.userId);
    final result = switch (command.kind) {
      AuthOrganizationTeamMemberMutationKind.add => () {
        _require(member.teamId == currentTeam.id, 'invalid_team_member');
        _require(
          _members.containsKey(
            _memberKey(currentTeam.organizationId, member.userId),
          ),
          'member_not_found',
        );
        _require(!_teamMembers.containsKey(key), 'team_member_exists');
        final count = _teamMembers.values
            .where((value) => value.teamId == member.teamId)
            .length;
        _requireLimit(count, command.memberLimit, 'team_member_limit');
        _teamMembers[key] = member;
        return member;
      }(),
      AuthOrganizationTeamMemberMutationKind.remove => () {
        final existing = _teamMembers[key];
        _require(existing != null, 'team_member_not_found');
        _require(
          _sameTeamMemberSnapshot(existing!, member),
          'team_member_changed',
        );
        _teamMembers.remove(key);
        return existing;
      }(),
    };
    _remember(command.idempotency, result);
    return AuthOrganizationStoreMutationResult(value: result);
  }

  void _requireActor(
    AuthOrganizationMember expected,
    String organizationId,
    List<AuthOrganizationRole> roleSnapshots,
  ) {
    _require(
      expected.organizationId == organizationId,
      'organization_forbidden',
    );
    final current = _members[_memberKey(organizationId, expected.userId)];
    if (current == null || !_sameMembershipSnapshot(current, expected)) {
      throw AuthFlowException('organization_forbidden');
    }
    _requireRoleSnapshots(current, roleSnapshots);
  }

  void _requireRoleSnapshots(
    AuthOrganizationMember actor,
    List<AuthOrganizationRole> snapshots,
  ) {
    for (final expected in snapshots) {
      _require(
        expected.organizationId == actor.organizationId &&
            actor.roles.contains(expected.name),
        'organization_forbidden',
      );
      final current = _roles[_roleKey(expected.organizationId, expected.name)];
      if (current == null || !_sameRoleSnapshot(current, expected)) {
        throw AuthFlowException('organization_forbidden');
      }
    }
  }

  T? _replay<T>(AuthOrganizationIdempotency? idempotency) {
    if (idempotency == null) return null;
    final normalized = _validateIdempotency(idempotency);
    final existing = _idempotency[normalized.key];
    if (existing == null) return null;
    _require(
      existing.binding == normalized.binding,
      'idempotency_key_conflict',
    );
    return existing.result as T;
  }

  void _remember(AuthOrganizationIdempotency? idempotency, Object result) {
    if (idempotency == null) return;
    final normalized = _validateIdempotency(idempotency);
    _require(
      _idempotency.length < 10000 || _idempotency.containsKey(normalized.key),
      'idempotency_capacity',
    );
    _idempotency[normalized.key] = _AuthOrganizationIdempotencyRecord(
      binding: normalized.binding,
      result: result,
    );
  }

  ({String key, String binding}) _validateIdempotency(
    AuthOrganizationIdempotency value,
  ) {
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
    return (key: key, binding: fields.join('\u0000'));
  }

  void _stage(String stage) => _failureInjector?.call(stage);

  /// Validates user deletion.
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

  /// Deletes user data.
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

typedef _AuthOrganizationStoreCheckpoint = ({
  Map<String, AuthOrganization> organizations,
  Map<String, AuthOrganizationMember> members,
  Map<String, AuthOrganizationInvitation> invitations,
  Map<String, AuthOrganizationRole> roles,
  Map<String, AuthOrganizationTeam> teams,
  Map<String, AuthOrganizationTeamMember> teamMembers,
  Map<String, _AuthOrganizationIdempotencyRecord> idempotency,
});

final class _AuthOrganizationIdempotencyRecord {
  /// Creates an instance of _AuthOrganizationIdempotencyRecord.
  const _AuthOrganizationIdempotencyRecord({
    required this.binding,
    required this.result,
  });

  /// The binding associated with this value.
  final String binding;

  /// The result associated with this value.
  final Object result;
}

String _memberKey(String organizationId, String userId) =>
    '${organizationId.trim()}\u0000${userId.trim()}';
String _roleKey(String organizationId, String name) =>
    '${organizationId.trim()}\u0000${name.trim().toLowerCase()}';
String _teamMemberKey(String teamId, String userId) =>
    '${teamId.trim()}\u0000${userId.trim()}';

bool _sameMembershipSnapshot(
  AuthOrganizationMember current,
  AuthOrganizationMember expected,
) =>
    current.id == expected.id &&
    current.organizationId == expected.organizationId &&
    current.userId == expected.userId &&
    _sameStrings(current.roles, expected.roles);

bool _sameInvitationSnapshot(
  AuthOrganizationInvitation current,
  AuthOrganizationInvitation expected,
) =>
    current.id == expected.id &&
    current.organizationId == expected.organizationId &&
    current.email == expected.email &&
    current.inviterId == expected.inviterId &&
    current.status == expected.status &&
    current.expiresAt == expected.expiresAt &&
    current.teamId == expected.teamId &&
    _sameStrings(current.roles, expected.roles);

bool _sameRoleSnapshot(
  AuthOrganizationRole current,
  AuthOrganizationRole expected, {
  bool compareName = true,
}) =>
    current.id == expected.id &&
    current.organizationId == expected.organizationId &&
    (!compareName || current.name == expected.name) &&
    current.createdAt == expected.createdAt &&
    current.updatedAt == expected.updatedAt &&
    current.predefined == expected.predefined &&
    _sameJson(current.permissions, expected.permissions);

bool _sameTeamSnapshot(
  AuthOrganizationTeam current,
  AuthOrganizationTeam expected,
) =>
    current.id == expected.id &&
    current.organizationId == expected.organizationId &&
    current.name == expected.name &&
    current.createdAt == expected.createdAt &&
    current.updatedAt == expected.updatedAt &&
    _sameJson(current.attributes, expected.attributes);

bool _sameTeamMemberSnapshot(
  AuthOrganizationTeamMember current,
  AuthOrganizationTeamMember expected,
) =>
    current.id == expected.id &&
    current.teamId == expected.teamId &&
    current.userId == expected.userId &&
    current.createdAt == expected.createdAt;

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameJson(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_sameJson(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameJson(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

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
