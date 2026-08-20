import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'organization_models.dart';
import 'organization_permissions.dart';
import 'organization_store.dart';
import 'rate_limit.dart';
import 'store.dart' show AuthUserStore;
import 'tokens.dart' show secureRandomToken;
import 'users.dart' show normalizeAuthEmail;

const String authOrganizationPluginId = 'organization';

typedef AuthOrganizationCreationPolicy = FutureOr<bool> Function(AuthUser user);
typedef AuthOrganizationInvitationIdGenerator = String Function();
typedef AuthOrganizationInvitationSender<TContext> =
    FutureOr<void> Function(
      AuthOrganizationInvitationDelivery<TContext> delivery,
    );
typedef AuthOrganizationFailureReporter =
    FutureOr<void> Function(AuthOrganizationInternalFailure failure);
typedef AuthOrganizationEventSink =
    FutureOr<void> Function(AuthOrganizationLifecycleEvent event);

final class AuthOrganizationTeamsOptions {
  const AuthOrganizationTeamsOptions({
    this.enabled = false,
    this.createDefaultTeam = true,
    this.defaultTeamName = 'Default',
    this.allowRemovingLastTeam = false,
    this.teamLimit,
    this.teamMemberLimit,
  });

  final bool enabled;
  final bool createDefaultTeam;
  final String defaultTeamName;
  final bool allowRemovingLastTeam;
  final int? teamLimit;
  final int? teamMemberLimit;
}

final class AuthOrganizationOptions<TContext> {
  const AuthOrganizationOptions({
    this.allowUserToCreateOrganization = true,
    this.creationPolicy,
    this.organizationLimit,
    this.creatorRole = 'owner',
    this.membershipLimit = 100,
    this.invitationLimit = 100,
    this.invitationExpiresIn = const Duration(hours: 48),
    this.replacePendingInvitations = false,
    this.requireVerifiedEmailForInvitations = false,
    this.invitationIdGenerator,
    this.invitationIdGeneratorIsOpaque = false,
    this.disableOrganizationDeletion = false,
    this.dynamicRoles = false,
    this.dynamicRoleLimit,
    this.staticRoles,
    this.teams = const AuthOrganizationTeamsOptions(),
    this.hooks = const AuthOrganizationHooks(),
    this.sendInvitation,
    this.reportFailure,
    this.emitEvent,
  });

  final bool allowUserToCreateOrganization;
  final AuthOrganizationCreationPolicy? creationPolicy;
  final int? organizationLimit;
  final String creatorRole;
  final int? membershipLimit;
  final int? invitationLimit;
  final Duration invitationExpiresIn;
  final bool replacePendingInvitations;
  final bool requireVerifiedEmailForInvitations;
  final AuthOrganizationInvitationIdGenerator? invitationIdGenerator;
  final bool invitationIdGeneratorIsOpaque;
  final bool disableOrganizationDeletion;
  final bool dynamicRoles;
  final int? dynamicRoleLimit;
  final Map<String, AuthOrganizationPermissionSet>? staticRoles;
  final AuthOrganizationTeamsOptions teams;
  final AuthOrganizationHooks<TContext> hooks;
  final AuthOrganizationInvitationSender<TContext>? sendInvitation;
  final AuthOrganizationFailureReporter? reportFailure;
  final AuthOrganizationEventSink? emitEvent;
}

final class AuthOrganizationHookContext<TContext, T> {
  const AuthOrganizationHookContext({
    required this.context,
    required this.action,
    required this.user,
    required this.data,
    this.organization,
  });

  final TContext context;
  final String action;
  final AuthUser user;
  final T data;
  final AuthOrganization? organization;
}

typedef AuthOrganizationBeforeHook<TContext, T> =
    FutureOr<T> Function(AuthOrganizationHookContext<TContext, T> event);
typedef AuthOrganizationAfterHook<TContext, T> =
    FutureOr<void> Function(AuthOrganizationHookContext<TContext, T> event);

final class AuthOrganizationHooks<TContext> {
  const AuthOrganizationHooks({
    this.beforeOrganization,
    this.afterOrganization,
    this.beforeMember,
    this.afterMember,
    this.beforeInvitation,
    this.afterInvitation,
    this.beforeRole,
    this.afterRole,
    this.beforeTeam,
    this.afterTeam,
    this.beforeTeamMember,
    this.afterTeamMember,
  });

  final AuthOrganizationBeforeHook<TContext, AuthOrganization>?
  beforeOrganization;
  final AuthOrganizationAfterHook<TContext, AuthOrganization>?
  afterOrganization;
  final AuthOrganizationBeforeHook<TContext, AuthOrganizationMember>?
  beforeMember;
  final AuthOrganizationAfterHook<TContext, AuthOrganizationMember>?
  afterMember;
  final AuthOrganizationBeforeHook<TContext, AuthOrganizationInvitation>?
  beforeInvitation;
  final AuthOrganizationAfterHook<TContext, AuthOrganizationInvitation>?
  afterInvitation;
  final AuthOrganizationBeforeHook<TContext, AuthOrganizationRole>? beforeRole;
  final AuthOrganizationAfterHook<TContext, AuthOrganizationRole>? afterRole;
  final AuthOrganizationBeforeHook<TContext, AuthOrganizationTeam>? beforeTeam;
  final AuthOrganizationAfterHook<TContext, AuthOrganizationTeam>? afterTeam;
  final AuthOrganizationBeforeHook<TContext, AuthOrganizationTeamMember>?
  beforeTeamMember;
  final AuthOrganizationAfterHook<TContext, AuthOrganizationTeamMember>?
  afterTeamMember;
}

final class AuthOrganizationInvitationDelivery<TContext> {
  const AuthOrganizationInvitationDelivery({
    required this.context,
    required this.invitation,
    required this.organization,
    required this.inviter,
  });

  final TContext context;
  final AuthOrganizationInvitation invitation;
  final AuthOrganization organization;
  final AuthUser inviter;
}

final class AuthOrganizationInternalFailure {
  const AuthOrganizationInternalFailure({
    required this.operation,
    required this.error,
    required this.stackTrace,
    this.organizationId,
  });

  final String operation;
  final Object error;
  final StackTrace stackTrace;
  final String? organizationId;
}

final class AuthOrganizationLifecycleEvent {
  AuthOrganizationLifecycleEvent({
    required this.type,
    required this.actorUserId,
    required DateTime occurredAt,
    this.organizationId,
    Map<String, dynamic>? payload,
  }) : occurredAt = occurredAt.toUtc(),
       payload = Map<String, dynamic>.unmodifiable(
         sanitizeAuthPublicAttributes(payload ?? const {}),
       );

  final String type;
  final String actorUserId;
  final String? organizationId;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;
}

/// Complete organization capability with storage-independent behavior.
final class OrganizationPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDeletionPlanContributor {
  OrganizationPlugin({
    required this.store,
    this.options = const AuthOrganizationOptions(),
    AuthUserStore? userStore,
  }) : accessControl = AuthOrganizationAccessControl(
         staticRoles: options.staticRoles,
         dynamicRoles: options.dynamicRoles,
       ),
       _userStore = userStore;

  final AuthOrganizationStore store;
  final AuthOrganizationOptions<TContext> options;
  final AuthOrganizationAccessControl accessControl;
  AuthUserStore? _userStore;
  late AuthUserDeletionDomain _deletionDomain;

  @override
  String get id => authOrganizationPluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _userStore ??= context.store.users;
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError(
        'OrganizationPlugin requires a deletion-coordinator host store.',
      );
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
  }

  @override
  String get userDataNamespace => 'organization';

  @override
  Future<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user) async {
    final target = store;
    if (target is! AuthOrganizationUserDeletionStore ||
        target is! AuthInMemoryDeletionState ||
        _deletionDomain is! AuthInMemoryUserDeletionDomain) {
      throw StateError(
        'The organization adapter has no plan for this persistence domain.',
      );
    }
    final deletionTarget = target as AuthOrganizationUserDeletionStore;
    await deletionTarget.validateUserDeletion(
      user.id,
      creatorRole: _creatorRole,
    );
    return AuthInMemoryUserDeletionPlan(
      domain: _deletionDomain as AuthInMemoryUserDeletionDomain,
      userId: user.id,
      namespace: userDataNamespace,
      operation: _InMemoryOrganizationDeletionOperation(
        store: deletionTarget,
        user: user,
        creatorRole: _creatorRole,
      ),
    );
  }

  static const List<String> publicOperationIds = [
    'organization.create',
    'organization.checkSlug',
    'organization.list',
    'organization.get',
    'organization.getFull',
    'organization.update',
    'organization.delete',
    'organization.setActive',
    'organization.listMembers',
    'organization.removeMember',
    'organization.updateMemberRole',
    'organization.getActiveMember',
    'organization.getActiveMemberRole',
    'organization.leave',
    'organization.inviteMember',
    'organization.acceptInvitation',
    'organization.rejectInvitation',
    'organization.cancelInvitation',
    'organization.getInvitation',
    'organization.listInvitations',
    'organization.listUserInvitations',
    'organization.hasPermission',
    'organization.createRole',
    'organization.listRoles',
    'organization.getRole',
    'organization.updateRole',
    'organization.deleteRole',
    'organization.createTeam',
    'organization.listTeams',
    'organization.updateTeam',
    'organization.removeTeam',
    'organization.setActiveTeam',
    'organization.listUserTeams',
    'organization.listTeamMembers',
    'organization.addTeamMember',
    'organization.removeTeamMember',
  ];

  static const Map<String, String> _paths = {
    'organization.create': '/organization/create',
    'organization.checkSlug': '/organization/check-slug',
    'organization.list': '/organization/list',
    'organization.get': '/organization/get',
    'organization.getFull': '/organization/get-full',
    'organization.update': '/organization/update',
    'organization.delete': '/organization/delete',
    'organization.setActive': '/organization/set-active',
    'organization.listMembers': '/organization/list-members',
    'organization.removeMember': '/organization/remove-member',
    'organization.updateMemberRole': '/organization/update-member-role',
    'organization.getActiveMember': '/organization/get-active-member',
    'organization.getActiveMemberRole': '/organization/get-active-member-role',
    'organization.leave': '/organization/leave',
    'organization.inviteMember': '/organization/invite-member',
    'organization.acceptInvitation': '/organization/accept-invitation',
    'organization.rejectInvitation': '/organization/reject-invitation',
    'organization.cancelInvitation': '/organization/cancel-invitation',
    'organization.getInvitation': '/organization/get-invitation',
    'organization.listInvitations': '/organization/list-invitations',
    'organization.listUserInvitations': '/organization/list-user-invitations',
    'organization.hasPermission': '/organization/has-permission',
    'organization.createRole': '/organization/create-role',
    'organization.listRoles': '/organization/list-roles',
    'organization.getRole': '/organization/get-role',
    'organization.updateRole': '/organization/update-role',
    'organization.deleteRole': '/organization/delete-role',
    'organization.createTeam': '/organization/create-team',
    'organization.listTeams': '/organization/list-teams',
    'organization.updateTeam': '/organization/update-team',
    'organization.removeTeam': '/organization/remove-team',
    'organization.setActiveTeam': '/organization/set-active-team',
    'organization.listUserTeams': '/organization/list-user-teams',
    'organization.listTeamMembers': '/organization/list-team-members',
    'organization.addTeamMember': '/organization/add-team-member',
    'organization.removeTeamMember': '/organization/remove-team-member',
  };

  static const Set<String> _readOperations = {
    'organization.checkSlug',
    'organization.list',
    'organization.get',
    'organization.getFull',
    'organization.listMembers',
    'organization.getActiveMember',
    'organization.getActiveMemberRole',
    'organization.getInvitation',
    'organization.listInvitations',
    'organization.listUserInvitations',
    'organization.listRoles',
    'organization.getRole',
    'organization.listTeams',
    'organization.listUserTeams',
    'organization.listTeamMembers',
    'organization.hasPermission',
  };

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      publicOperationIds.map(_endpoint).toList(growable: false);

  AuthEndpointDescriptor<TContext> _endpoint(String operationId) {
    final method = _readOperations.contains(operationId)
        ? AuthOperationMethod.get
        : AuthOperationMethod.post;
    return TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: operationId,
      method: method,
      path: _paths[operationId]!,
      semantics: _operationSemantics(operationId),
      requestCodec: _mapCodec,
      responseCodec: _objectCodec,
      authentication: operationId == 'organization.checkSlug'
          ? AuthOperationAuthentication.none
          : AuthOperationAuthentication.session,
      originPolicy: method == AuthOperationMethod.post
          ? AuthOperationOriginPolicy.browser
          : AuthOperationOriginPolicy.none,
      csrfPolicy: method == AuthOperationMethod.post
          ? AuthOperationCsrfPolicy.required
          : AuthOperationCsrfPolicy.none,
      rateLimitOperation: AuthRateLimitOperation(
        'organization',
        operationId.split('.').last,
      ),
      handler: (invocation, request) =>
          _invokeEndpoint(operationId, invocation, request),
    );
  }

  static AuthOperationSemantics _operationSemantics(String operationId) {
    if (_readOperations.contains(operationId)) {
      return const AuthOperationSemantics.readOnly();
    }
    if (operationId == 'organization.setActive' ||
        operationId == 'organization.setActiveTeam') {
      return const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.session(),
        replaySafety: AuthMutationReplaySafety.idempotent,
      );
    }
    final atomicOperation = switch (operationId) {
      'organization.create' => 'createOrganization',
      'organization.acceptInvitation' => 'acceptInvitation',
      'organization.delete' => 'cascadeOrganization',
      'organization.removeMember' ||
      'organization.updateMemberRole' ||
      'organization.leave' => 'mutateMembership',
      'organization.inviteMember' => 'createInvitation',
      'organization.rejectInvitation' ||
      'organization.cancelInvitation' => 'transitionInvitation',
      'organization.createRole' ||
      'organization.updateRole' ||
      'organization.deleteRole' => 'mutateRole',
      'organization.createTeam' ||
      'organization.updateTeam' ||
      'organization.removeTeam' => 'mutateTeam',
      'organization.addTeamMember' ||
      'organization.removeTeamMember' => 'mutateTeamMember',
      _ => null,
    };
    final replaySafety = switch (operationId) {
      'organization.update' ||
      'organization.updateMemberRole' ||
      'organization.updateRole' ||
      'organization.updateTeam' => AuthMutationReplaySafety.idempotent,
      'organization.delete' ||
      'organization.leave' ||
      'organization.acceptInvitation' ||
      'organization.rejectInvitation' ||
      'organization.cancelInvitation' ||
      'organization.removeMember' ||
      'organization.deleteRole' ||
      'organization.removeTeam' ||
      'organization.removeTeamMember' => AuthMutationReplaySafety.singleUse,
      'organization.create' ||
      'organization.inviteMember' ||
      'organization.createRole' ||
      'organization.createTeam' ||
      'organization.addTeamMember' => AuthMutationReplaySafety.idempotent,
      _ => AuthMutationReplaySafety.unguarded,
    };
    return AuthOperationSemantics.mutation(
      persistence: AuthMutationPersistence.durable(
        atomicity: atomicOperation == null
            ? AuthMutationAtomicity.nonAtomic
            : AuthMutationAtomicity.atomic,
        reference: AuthPersistenceOperationReference(
          schemaId: 'organization',
          atomicOperationId: atomicOperation,
        ),
      ),
      replaySafety: replaySafety,
    );
  }

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      serverOnly: endpoint.serverOnly,
    ),
  );

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: 'organization',
      entities: [
        AuthEntityDescriptor(
          id: 'organization',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'name', kind: 'string'),
            AuthFieldDescriptor(name: 'slug', kind: 'string'),
            AuthFieldDescriptor(name: 'logo', kind: 'nullable_string'),
            AuthFieldDescriptor(name: 'metadata', kind: 'attributes'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'updatedAt', kind: 'datetime'),
          ],
          uniqueConstraints: [
            ['slug'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'organization_member',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'id'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'roles', kind: 'string_list'),
            AuthFieldDescriptor(name: 'attributes', kind: 'attributes'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'organizationId',
              targetEntity: 'organization',
              cascadeDelete: true,
            ),
            AuthRelationshipDescriptor(field: 'userId', targetEntity: 'user'),
          ],
          uniqueConstraints: [
            ['organizationId', 'userId'],
          ],
          indexes: [
            ['userId'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'organization_invitation',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'id'),
            AuthFieldDescriptor(name: 'email', kind: 'normalized_email'),
            AuthFieldDescriptor(name: 'roles', kind: 'string_list'),
            AuthFieldDescriptor(name: 'inviterId', kind: 'id'),
            AuthFieldDescriptor(name: 'status', kind: 'string'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'teamId', kind: 'nullable_id'),
            AuthFieldDescriptor(name: 'attributes', kind: 'attributes'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'organizationId',
              targetEntity: 'organization',
              cascadeDelete: true,
            ),
            AuthRelationshipDescriptor(
              field: 'inviterId',
              targetEntity: 'user',
            ),
            AuthRelationshipDescriptor(
              field: 'teamId',
              targetEntity: 'organization_team',
            ),
          ],
          indexes: [
            ['organizationId', 'email', 'status'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'organization_role',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'id'),
            AuthFieldDescriptor(name: 'name', kind: 'string'),
            AuthFieldDescriptor(name: 'permissions', kind: 'string_list_map'),
            AuthFieldDescriptor(name: 'predefined', kind: 'boolean'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'updatedAt', kind: 'datetime'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'organizationId',
              targetEntity: 'organization',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: [
            ['organizationId', 'name'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'organization_team',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'id'),
            AuthFieldDescriptor(name: 'name', kind: 'string'),
            AuthFieldDescriptor(name: 'attributes', kind: 'attributes'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'updatedAt', kind: 'datetime'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'organizationId',
              targetEntity: 'organization',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: [
            ['organizationId', 'name'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'organization_team_member',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'teamId', kind: 'id'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'teamId',
              targetEntity: 'organization_team',
              cascadeDelete: true,
            ),
            AuthRelationshipDescriptor(field: 'userId', targetEntity: 'user'),
          ],
          uniqueConstraints: [
            ['teamId', 'userId'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'organization_idempotency',
          fields: [
            AuthFieldDescriptor(name: 'key', kind: 'bounded_non_secret_key'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'string'),
            AuthFieldDescriptor(name: 'actorId', kind: 'id'),
            AuthFieldDescriptor(name: 'operationId', kind: 'string'),
            AuthFieldDescriptor(name: 'fingerprint', kind: 'sha256'),
            AuthFieldDescriptor(name: 'result', kind: 'immutable_snapshot'),
          ],
          uniqueConstraints: [
            ['key'],
          ],
          indexes: [
            ['organizationId', 'actorId', 'operationId'],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'createOrganization',
          description:
              'Create organization, creator membership, and optional default team.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'acceptInvitation',
          description:
              'Consume invitation and reserve member and team capacity exactly once.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'protectCreator',
          description: 'Preserve at least one creator-role member.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'mutateMembership',
          description:
              'Verify actor and target snapshots, preserve a creator, and '
              'cascade membership removal to teams.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'createInvitation',
          description:
              'Verify the actor snapshot, reserve invitation capacity, '
              'replace pending state, and persist deterministic replay.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'transitionInvitation',
          description:
              'Verify invitation and actor binding before a single-use '
              'state transition.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'mutateRole',
          description:
              'Create, update, rename, or delete a dynamic role with all '
              'assignment and replay invariants.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'mutateTeam',
          description:
              'Create, update, or delete a team with capacity, uniqueness, '
              'invitation cleanup, and member cascade invariants.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'mutateTeamMember',
          description:
              'Verify actor and team snapshots before capacity-bounded, '
              'unique team membership writes.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'cascadeOrganization',
          description: 'Delete all organization-owned records together.',
        ),
      ],
    ),
  ];

  Future<AuthOrganizationMutationResult<AuthOrganization>> createOrganization({
    required TContext context,
    required AuthUser user,
    required String name,
    required String slug,
    required String idempotencyKey,
    String? logo,
    Map<String, dynamic>? metadata,
  }) async {
    if (!options.allowUserToCreateOrganization ||
        options.creationPolicy != null &&
            !await options.creationPolicy!(user)) {
      throw AuthFlowException('organization_creation_forbidden');
    }
    return createOrganizationForUser(
      context: context,
      user: user,
      name: name,
      slug: slug,
      idempotencyKey: idempotencyKey,
      logo: logo,
      metadata: metadata,
    );
  }

  /// Trusted Dart-only operation for creating an organization for [user].
  Future<AuthOrganizationMutationResult<AuthOrganization>>
  createOrganizationForUser({
    required TContext context,
    required AuthUser user,
    required String name,
    required String slug,
    required String idempotencyKey,
    String? logo,
    Map<String, dynamic>? metadata,
  }) async {
    final now = DateTime.now().toUtc();
    var organization = AuthOrganization(
      id: secureRandomToken(length: 16),
      name: _required(name, 'invalid_organization_name'),
      slug: _slug(slug),
      logo: logo,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );
    organization = await _beforeOrganization(
      context,
      'create',
      user,
      organization,
    );
    var member = AuthOrganizationMember(
      id: secureRandomToken(length: 16),
      organizationId: organization.id,
      userId: user.id,
      roles: [_creatorRole],
      createdAt: now,
    );
    member = await _beforeMember(context, 'add', user, member, organization);
    await _validateRoles(organization.id, member.roles);
    if (!member.roles.contains(_creatorRole)) {
      throw AuthFlowException('invalid_role');
    }
    AuthOrganizationTeam? team;
    AuthOrganizationTeamMember? teamMember;
    if (options.teams.enabled && options.teams.createDefaultTeam) {
      team = AuthOrganizationTeam(
        id: secureRandomToken(length: 16),
        organizationId: organization.id,
        name: options.teams.defaultTeamName,
        createdAt: now,
        updatedAt: now,
      );
      team = await _beforeTeam(context, 'create', user, team, organization);
      teamMember = AuthOrganizationTeamMember(
        id: secureRandomToken(length: 16),
        teamId: team.id,
        userId: user.id,
        createdAt: now,
      );
      teamMember = await _beforeTeamMember(
        context,
        'add',
        user,
        teamMember,
        organization,
      );
    }
    final stored = await store.createOrganization(
      AuthOrganizationCreateTransaction(
        organization: organization,
        creatorMembership: member,
        organizationLimit: options.organizationLimit,
        defaultTeam: team,
        creatorTeamMembership: teamMember,
        idempotency: AuthOrganizationIdempotency(
          key: idempotencyKey,
          organizationId: organization.slug,
          actorId: user.id,
          operationId: 'organization.create',
          fingerprint: _fingerprint(
            {
              'organization': organization.toJson(),
              'member': member.toJson(),
              'team': team?.toJson(),
              'teamMember': teamMember?.toJson(),
            },
            volatileKeys: const {'id', 'createdAt', 'updatedAt'},
          ),
        ),
      ),
    );
    if (stored.replayed) {
      return AuthOrganizationMutationResult(
        data: stored.organization,
        warnings: const <AuthOrganizationWarning>[],
      );
    }
    final warnings = <AuthOrganizationWarning>[];
    warnings.addAll(
      await _afterOrganization(context, 'create', user, stored.organization),
    );
    warnings.addAll(
      await _afterMember(
        context,
        'add',
        user,
        stored.creatorMembership,
        stored.organization,
      ),
    );
    if (team != null) {
      warnings.addAll(
        await _afterTeam(context, 'create', user, team, stored.organization),
      );
    }
    if (teamMember != null) {
      warnings.addAll(
        await _afterTeamMember(
          context,
          'add',
          user,
          teamMember,
          stored.organization,
        ),
      );
    }
    warnings.addAll(
      await _emit(
        'organization.created',
        user,
        stored.organization.id,
        stored.organization.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(
      data: stored.organization,
      warnings: warnings,
    );
  }

  Future<bool> checkSlug(String slug) async =>
      await store.findOrganizationBySlug(_slug(slug)) == null;

  Future<List<AuthOrganization>> listOrganizations(String userId) =>
      Future.sync(() => store.listOrganizationsForUser(userId));

  Future<AuthOrganizationAuthorizationContext<TContext>> authorizeContext({
    required TContext context,
    required String userId,
    String? organizationId,
    String? activeOrganizationId,
    String? teamId,
  }) async {
    final id = (organizationId ?? activeOrganizationId)?.trim() ?? '';
    if (id.isEmpty) throw AuthFlowException('organization_not_selected');
    final organization = await store.findOrganization(id);
    if (organization == null) throw AuthFlowException('organization_not_found');
    final member = await store.findMember(id, userId);
    if (member == null) throw AuthFlowException('organization_forbidden');
    AuthOrganizationTeam? team;
    if (teamId != null && teamId.trim().isNotEmpty) {
      team = await store.findTeam(teamId);
      if (team == null || team.organizationId != id) {
        throw AuthFlowException('team_not_found');
      }
      if (await store.findTeamMember(team.id, userId) == null) {
        throw AuthFlowException('team_forbidden');
      }
    }
    return AuthOrganizationAuthorizationContext(
      context: context,
      userId: userId,
      organization: organization,
      membership: member,
      team: team,
    );
  }

  Future<bool> hasPermission({
    required TContext context,
    required String userId,
    required String organizationId,
    required String resource,
    required String action,
  }) async {
    final auth = await authorizeContext(
      context: context,
      userId: userId,
      organizationId: organizationId,
    );
    return accessControl.allows(
      store: store,
      member: auth.membership,
      resource: resource,
      action: action,
    );
  }

  Future<AuthOrganizationAuthorizationContext<TContext>> _requirePermission({
    required TContext context,
    required String userId,
    required String organizationId,
    required String resource,
    required String action,
  }) async {
    final auth = await authorizeContext(
      context: context,
      userId: userId,
      organizationId: organizationId,
    );
    final decision = await accessControl.authorize(
      store: store,
      member: auth.membership,
      resource: resource,
      action: action,
    );
    if (!decision.allowed) {
      throw AuthFlowException('organization_forbidden');
    }
    return AuthOrganizationAuthorizationContext<TContext>(
      context: auth.context,
      userId: auth.userId,
      organization: auth.organization,
      membership: auth.membership,
      team: auth.team,
      authorizationRoleSnapshots: decision.dynamicRoleSnapshots,
    );
  }

  Future<Object?> _invokeEndpoint(
    String id,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    if (id == 'organization.checkSlug') {
      return {'available': await checkSlug(_string(input, 'slug'))};
    }
    final user = invocation.user;
    if (user == null || user.id.trim().isEmpty) {
      throw AuthFlowException('unauthorized');
    }
    final organizationId =
        _optionalString(input, 'organizationId') ??
        invocation.activeOrganizationId;
    final activeId = organizationId?.trim();
    switch (id) {
      case 'organization.create':
        return (await createOrganization(
          context: invocation.context,
          user: user,
          name: _string(input, 'name'),
          slug: _string(input, 'slug'),
          idempotencyKey: _idempotencyKey(input),
          logo: _optionalString(input, 'logo'),
          metadata: _jsonMap(input['metadata']),
        )).toJson((value) => value.toJson());
      case 'organization.list':
        return {
          'organizations': (await listOrganizations(
            user.id,
          )).map((value) => value.toJson()).toList(),
        };
      case 'organization.get':
        final auth = await authorizeContext(
          context: invocation.context,
          userId: user.id,
          organizationId: activeId,
        );
        return auth.organization.toJson();
      case 'organization.getFull':
        final auth = await authorizeContext(
          context: invocation.context,
          userId: user.id,
          organizationId: activeId,
        );
        final requestedLimit = _int(
          input,
          'membersLimit',
          fallback: options.membershipLimit ?? 100,
        ).clamp(1, options.membershipLimit ?? 1000);
        final allMembers = await store.listMembers(auth.organization.id);
        final invitations = await store.listInvitations(auth.organization.id);
        final teams = options.teams.enabled
            ? await store.listTeams(auth.organization.id)
            : const <AuthOrganizationTeam>[];
        return AuthOrganizationDetails(
          organization: auth.organization,
          members: AuthOrganizationPage(
            items: List.unmodifiable(allMembers.take(requestedLimit)),
            total: allMembers.length,
            limit: requestedLimit,
            offset: 0,
          ),
          invitations: invitations,
          teams: teams,
        ).toJson();
      case 'organization.update':
        return (await _updateOrganization(
          invocation.context,
          user,
          activeId,
          input,
        )).toJson((value) => value.toJson());
      case 'organization.delete':
        return (await _deleteOrganization(
          invocation.context,
          user,
          activeId,
        )).toJson((value) => value.toJson());
      case 'organization.setActive':
        return _setActive(invocation, user, input);
      case 'organization.listMembers':
        return _listMembers(invocation.context, user, activeId, input);
      case 'organization.removeMember':
        return (await _removeMember(
          invocation.context,
          user,
          activeId,
          _string(input, 'userId'),
        )).toJson((value) => value.toJson());
      case 'organization.updateMemberRole':
        return (await _updateMemberRoles(
          invocation.context,
          user,
          activeId,
          _string(input, 'userId'),
          _roles(input),
        )).toJson((value) => value.toJson());
      case 'organization.getActiveMember':
        final auth = await authorizeContext(
          context: invocation.context,
          userId: user.id,
          organizationId: activeId,
        );
        return auth.membership.toJson();
      case 'organization.getActiveMemberRole':
        final auth = await authorizeContext(
          context: invocation.context,
          userId: user.id,
          organizationId: activeId,
        );
        return {'roles': auth.membership.roles};
      case 'organization.leave':
        return (await _removeMember(
          invocation.context,
          user,
          activeId,
          user.id,
          self: true,
        )).toJson((value) => value.toJson());
      case 'organization.inviteMember':
        return (await _invite(
          invocation.context,
          user,
          activeId,
          input,
        )).toJson((value) => value.toJson());
      case 'organization.acceptInvitation':
        return (await _acceptInvitation(
          invocation.context,
          user,
          invocation.emailVerified,
          _string(input, 'invitationId'),
        )).toJson((value) => value.toJson());
      case 'organization.rejectInvitation':
        return (await _respondToInvitation(
          invocation.context,
          user,
          invocation.emailVerified,
          _string(input, 'invitationId'),
          AuthOrganizationInvitationStatus.rejected,
        )).toJson((value) => value.toJson());
      case 'organization.cancelInvitation':
        return (await _cancelInvitation(
          invocation.context,
          user,
          _string(input, 'invitationId'),
        )).toJson((value) => value.toJson());
      case 'organization.getInvitation':
        return (await _getInvitation(
          user,
          invocation.emailVerified,
          _string(input, 'invitationId'),
        )).toJson();
      case 'organization.listInvitations':
        final auth = await _requirePermission(
          context: invocation.context,
          userId: user.id,
          organizationId: _requiredId(activeId),
          resource: 'invitation',
          action: 'read',
        );
        return {
          'invitations': (await store.listInvitations(
            auth.organization.id,
          )).map((value) => value.toJson()).toList(),
        };
      case 'organization.listUserInvitations':
        if (!invocation.emailVerified) {
          throw AuthFlowException('verified_email_required');
        }
        final email = _requiredEmail(user);
        return {
          'invitations': (await store.listInvitationsForEmail(
            email,
          )).map((value) => value.toJson()).toList(),
        };
      case 'organization.hasPermission':
        final id = _requiredId(activeId);
        return AuthOrganizationPermissionResult(
          allowed: await hasPermission(
            context: invocation.context,
            userId: user.id,
            organizationId: id,
            resource: _string(input, 'resource'),
            action: _string(input, 'action'),
          ),
          organizationId: id,
        ).toJson();
      case 'organization.createRole':
        return (await _createRole(
          invocation.context,
          user,
          activeId,
          input,
        )).toJson((value) => value.toJson());
      case 'organization.listRoles':
        final auth = await _requirePermission(
          context: invocation.context,
          userId: user.id,
          organizationId: _requiredId(activeId),
          resource: 'role',
          action: 'read',
        );
        return {
          'roles': (await store.listRoles(
            auth.organization.id,
          )).map((value) => value.toJson()).toList(),
          'staticRoles': accessControl.staticRoles,
        };
      case 'organization.getRole':
        final auth = await _requirePermission(
          context: invocation.context,
          userId: user.id,
          organizationId: _requiredId(activeId),
          resource: 'role',
          action: 'read',
        );
        final name = _string(input, 'name').toLowerCase();
        final dynamic = await store.findRole(auth.organization.id, name);
        if (dynamic != null) return dynamic.toJson();
        final staticRole = accessControl.staticRoles[name];
        if (staticRole == null) throw AuthFlowException('role_not_found');
        final now = DateTime.now().toUtc();
        return AuthOrganizationRole(
          id: 'static:$name',
          organizationId: auth.organization.id,
          name: name,
          permissions: staticRole,
          predefined: true,
          createdAt: now,
          updatedAt: now,
        ).toJson();
      case 'organization.updateRole':
        return (await _updateRole(
          invocation.context,
          user,
          activeId,
          input,
        )).toJson((value) => value.toJson());
      case 'organization.deleteRole':
        return (await _deleteRole(
          invocation.context,
          user,
          activeId,
          _string(input, 'name'),
        )).toJson((value) => value.toJson());
      case 'organization.createTeam':
        return (await _createTeam(
          invocation.context,
          user,
          activeId,
          input,
        )).toJson((value) => value.toJson());
      case 'organization.listTeams':
        return _listTeams(invocation.context, user, activeId);
      case 'organization.updateTeam':
        return (await _updateTeam(
          invocation.context,
          user,
          _string(input, 'teamId'),
          input,
        )).toJson((value) => value.toJson());
      case 'organization.removeTeam':
        return (await _removeTeam(
          invocation.context,
          user,
          _string(input, 'teamId'),
        )).toJson((value) => value.toJson());
      case 'organization.setActiveTeam':
        return _setActiveTeam(invocation, user, activeId, input);
      case 'organization.listUserTeams':
        final auth = await authorizeContext(
          context: invocation.context,
          userId: user.id,
          organizationId: activeId,
        );
        return {
          'teams': (await store.listTeamsForUser(
            auth.organization.id,
            user.id,
          )).map((value) => value.toJson()).toList(),
        };
      case 'organization.listTeamMembers':
        return _listTeamMembers(
          invocation.context,
          user,
          _string(input, 'teamId'),
        );
      case 'organization.addTeamMember':
        return (await trustedAddTeamMember(
          context: invocation.context,
          actor: user,
          teamId: _string(input, 'teamId'),
          userId: _string(input, 'userId'),
          idempotencyKey: _idempotencyKey(input),
        )).toJson((value) => value.toJson());
      case 'organization.removeTeamMember':
        return (await _removeTeamMember(
          invocation.context,
          user,
          _string(input, 'teamId'),
          _string(input, 'userId'),
        )).toJson((value) => value.toJson());
    }
    throw AuthFlowException('organization_operation_not_found');
  }

  Future<AuthOrganizationMutationResult<AuthOrganization>> _updateOrganization(
    TContext context,
    AuthUser user,
    String? id,
    Map<String, dynamic> input,
  ) async {
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'organization',
      action: 'update',
    );
    final data = _jsonMap(input['data']) ?? input;
    var updated = AuthOrganization(
      id: auth.organization.id,
      name: _optionalString(data, 'name') ?? auth.organization.name,
      slug: data.containsKey('slug')
          ? _slug(_string(data, 'slug'))
          : auth.organization.slug,
      logo: data.containsKey('logo')
          ? data['logo']?.toString()
          : auth.organization.logo,
      metadata: data.containsKey('metadata')
          ? _jsonMap(data['metadata'])
          : auth.organization.metadata,
      createdAt: auth.organization.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    updated = await _beforeOrganization(context, 'update', user, updated);
    updated = await store.updateOrganization(updated);
    final warnings = await _afterOrganization(context, 'update', user, updated);
    warnings.addAll(
      await _emit('organization.updated', user, updated.id, updated.toJson()),
    );
    return AuthOrganizationMutationResult(data: updated, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganization>> _deleteOrganization(
    TContext context,
    AuthUser user,
    String? id,
  ) async {
    if (options.disableOrganizationDeletion) {
      throw AuthFlowException('organization_deletion_disabled');
    }
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'organization',
      action: 'delete',
    );
    final transformed = await _beforeOrganization(
      context,
      'delete',
      user,
      auth.organization,
    );
    final deleted = await store.deleteOrganization(transformed.id);
    final warnings = await _afterOrganization(context, 'delete', user, deleted);
    warnings.addAll(
      await _emit('organization.deleted', user, deleted.id, deleted.toJson()),
    );
    return AuthOrganizationMutationResult(data: deleted, warnings: warnings);
  }

  Future<Map<String, dynamic>> _setActive(
    AuthOperationInvocation<TContext> invocation,
    AuthUser user,
    Map<String, dynamic> input,
  ) async {
    final requested = _optionalString(input, 'organizationId');
    if (requested == null) {
      await invocation.writeActiveSelection?.call(null, null);
      return {'organizationId': null, 'teamId': null};
    }
    final auth = await authorizeContext(
      context: invocation.context,
      userId: user.id,
      organizationId: requested,
    );
    await invocation.writeActiveSelection?.call(auth.organization.id, null);
    return {'organizationId': auth.organization.id, 'teamId': null};
  }

  Future<Map<String, dynamic>> _listMembers(
    TContext context,
    AuthUser user,
    String? id,
    Map<String, dynamic> input,
  ) async {
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'member',
      action: 'read',
    );
    final limit = _int(
      input,
      'limit',
      fallback: 100,
    ).clamp(1, options.membershipLimit ?? 1000);
    final offset = _int(input, 'offset').clamp(0, 1 << 31);
    final values = await store.listMembers(auth.organization.id);
    return AuthOrganizationPage(
      items: List.unmodifiable(values.skip(offset).take(limit)),
      total: values.length,
      limit: limit,
      offset: offset,
    ).toJson((member) => member.toJson());
  }

  /// Trusted Dart-only direct member addition.
  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  trustedAddMember({
    required TContext context,
    required AuthUser actor,
    required String organizationId,
    required String userId,
    Iterable<String> roles = const ['member'],
  }) async {
    final organization = await store.findOrganization(organizationId);
    if (organization == null) throw AuthFlowException('organization_not_found');
    await _validateRoles(organizationId, roles);
    final normalizedRoles = normalizeAuthOrganizationRoles(roles);
    if (normalizedRoles.contains(_creatorRole)) {
      final actorMember = await store.findMember(organizationId, actor.id);
      _requireCreatorAuthority(actorMember);
    }
    var member = AuthOrganizationMember(
      id: secureRandomToken(length: 16),
      organizationId: organizationId,
      userId: userId,
      roles: normalizedRoles,
      createdAt: DateTime.now().toUtc(),
    );
    member = await _beforeMember(context, 'add', actor, member, organization);
    await _validateRoles(organizationId, member.roles);
    if (member.roles.contains(_creatorRole)) {
      final actorMember = await store.findMember(organizationId, actor.id);
      _requireCreatorAuthority(actorMember);
    }
    member = await store.addMember(
      member,
      membershipLimit: options.membershipLimit,
    );
    final warnings = await _afterMember(
      context,
      'add',
      actor,
      member,
      organization,
    );
    warnings.addAll(
      await _emit(
        'organization.member.added',
        actor,
        organizationId,
        member.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: member, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>> _removeMember(
    TContext context,
    AuthUser actor,
    String? id,
    String userId, {
    bool self = false,
  }) async {
    final organizationId = _requiredId(id);
    final auth = await authorizeContext(
      context: context,
      userId: actor.id,
      organizationId: organizationId,
    );
    if (!self &&
        !await accessControl.allows(
          store: store,
          member: auth.membership,
          resource: 'member',
          action: 'delete',
        )) {
      throw AuthFlowException('organization_forbidden');
    }
    final member = await store.findMember(organizationId, userId);
    if (member == null) throw AuthFlowException('member_not_found');
    _requireCreatorAuthorityForRoles(auth.membership, member.roles);
    final transformed = await _beforeMember(
      context,
      self ? 'leave' : 'remove',
      actor,
      member,
      auth.organization,
    );
    final transformedMember = await store.findMember(
      organizationId,
      transformed.userId,
    );
    if (transformedMember == null) {
      throw AuthFlowException('member_not_found');
    }
    _requireCreatorAuthorityForRoles(auth.membership, transformedMember.roles);
    final mutationStore = _membershipMutationStore();
    final removed = await mutationStore.mutateOrganizationMembership(
      AuthOrganizationMembershipMutation(
        kind: AuthOrganizationMembershipMutationKind.remove,
        actorMembership: auth.membership,
        targetMembership: transformedMember,
        creatorRole: _creatorRole,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
      ),
    );
    final warnings = await _afterMember(
      context,
      self ? 'leave' : 'remove',
      actor,
      removed,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.member.removed',
        actor,
        organizationId,
        removed.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: removed, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  _updateMemberRoles(
    TContext context,
    AuthUser actor,
    String? id,
    String userId,
    Iterable<String> roles,
  ) async {
    final auth = await _requirePermission(
      context: context,
      userId: actor.id,
      organizationId: _requiredId(id),
      resource: 'member',
      action: 'update',
    );
    await _validateRoles(auth.organization.id, roles);
    final existing = await store.findMember(auth.organization.id, userId);
    if (existing == null) throw AuthFlowException('member_not_found');
    final normalizedRoles = normalizeAuthOrganizationRoles(roles);
    _requireCreatorAuthorityForRoles(auth.membership, [
      ...existing.roles,
      ...normalizedRoles,
    ]);
    var draft = existing.copyWith(roles: normalizedRoles);
    draft = await _beforeMember(
      context,
      'updateRole',
      actor,
      draft,
      auth.organization,
    );
    await _validateRoles(auth.organization.id, draft.roles);
    _requireCreatorAuthorityForRoles(auth.membership, [
      ...existing.roles,
      ...draft.roles,
    ]);
    final mutationStore = _membershipMutationStore();
    final updated = await mutationStore.mutateOrganizationMembership(
      AuthOrganizationMembershipMutation(
        kind: AuthOrganizationMembershipMutationKind.replaceRoles,
        actorMembership: auth.membership,
        targetMembership: existing,
        creatorRole: _creatorRole,
        replacementRoles: draft.roles,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
      ),
    );
    final warnings = await _afterMember(
      context,
      'updateRole',
      actor,
      updated,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.member.roleUpdated',
        actor,
        auth.organization.id,
        updated.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: updated, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>> _invite(
    TContext context,
    AuthUser actor,
    String? id,
    Map<String, dynamic> input,
  ) async {
    final auth = await _requirePermission(
      context: context,
      userId: actor.id,
      organizationId: _requiredId(id),
      resource: 'invitation',
      action: 'create',
    );
    final roles = _roles(input);
    await _validateRoles(auth.organization.id, roles);
    _requireCreatorAuthorityForRoles(auth.membership, roles);
    final now = DateTime.now().toUtc();
    var invitation = AuthOrganizationInvitation(
      id: options.invitationIdGenerator?.call() ?? secureRandomToken(),
      organizationId: auth.organization.id,
      email: _string(input, 'email'),
      roles: roles,
      inviterId: actor.id,
      status: AuthOrganizationInvitationStatus.pending,
      expiresAt: now.add(options.invitationExpiresIn),
      createdAt: now,
      teamId: _optionalString(input, 'teamId'),
    );
    invitation = await _beforeInvitation(
      context,
      'create',
      actor,
      invitation,
      auth.organization,
    );
    await _validateRoles(auth.organization.id, invitation.roles);
    _requireCreatorAuthorityForRoles(auth.membership, invitation.roles);
    await _validateInvitationTeam(invitation, auth.organization.id);
    await _rejectExistingMemberInvitation(invitation);
    final storedInvitation = await _atomicMutationStore()
        .executeOrganizationMutation(
          AuthOrganizationCreateInvitationCommand(
            actorMembership: auth.membership,
            invitation: invitation,
            invitationLimit: options.invitationLimit,
            replacePending: options.replacePendingInvitations,
            actorRoleSnapshots: auth.authorizationRoleSnapshots,
            idempotency: AuthOrganizationIdempotency(
              key: _idempotencyKey(input),
              organizationId: auth.organization.id,
              actorId: actor.id,
              operationId: 'organization.inviteMember',
              fingerprint: _fingerprint(
                invitation.toJson(),
                volatileKeys: const {'id', 'createdAt', 'expiresAt'},
              ),
            ),
          ),
        );
    invitation = storedInvitation.value;
    if (storedInvitation.replayed) {
      return AuthOrganizationMutationResult(
        data: invitation,
        warnings: const <AuthOrganizationWarning>[],
      );
    }
    final warnings = await _afterInvitation(
      context,
      'create',
      actor,
      invitation,
      auth.organization,
    );
    final sender = options.sendInvitation;
    if (sender != null) {
      try {
        await sender(
          AuthOrganizationInvitationDelivery(
            context: context,
            invitation: invitation,
            organization: auth.organization,
            inviter: actor,
          ),
        );
      } catch (error, stackTrace) {
        warnings.add(
          const AuthOrganizationWarning(code: 'invitation_delivery_failed'),
        );
        await _report(
          'invitation.delivery',
          error,
          stackTrace,
          auth.organization.id,
        );
      }
    }
    warnings.addAll(
      await _emit(
        'organization.invitation.created',
        actor,
        auth.organization.id,
        invitation.toJson(includeActionId: false),
      ),
    );
    return AuthOrganizationMutationResult(data: invitation, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationMember>>
  _acceptInvitation(
    TContext context,
    AuthUser user,
    bool emailVerified,
    String invitationId,
  ) async {
    final invitation = await store.findInvitation(invitationId);
    if (invitation == null) throw AuthFlowException('invitation_not_found');
    final email = _requiredEmail(user);
    if (normalizeAuthEmail(email) != invitation.email) {
      throw AuthFlowException('invitation_email_mismatch');
    }
    final customGeneratorNeedsVerification =
        options.invitationIdGenerator != null &&
        !options.invitationIdGeneratorIsOpaque;
    if ((options.requireVerifiedEmailForInvitations ||
            customGeneratorNeedsVerification) &&
        !emailVerified) {
      throw AuthFlowException('verified_email_required');
    }
    final organization = await store.findOrganization(
      invitation.organizationId,
    );
    if (organization == null) throw AuthFlowException('organization_not_found');
    final transformed = await _beforeInvitation(
      context,
      'accept',
      user,
      invitation,
      organization,
    );
    await _validateRoles(organization.id, transformed.roles);
    await _validateInvitationTeam(transformed, organization.id);
    var member = AuthOrganizationMember(
      id: secureRandomToken(length: 16),
      organizationId: invitation.organizationId,
      userId: user.id,
      roles: transformed.roles,
      createdAt: DateTime.now().toUtc(),
    );
    member = await _beforeMember(context, 'add', user, member, organization);
    await _validateRoles(organization.id, member.roles);
    AuthOrganizationTeamMember? teamMember;
    if (transformed.teamId != null) {
      teamMember = AuthOrganizationTeamMember(
        id: secureRandomToken(length: 16),
        teamId: transformed.teamId!,
        userId: user.id,
        createdAt: DateTime.now().toUtc(),
      );
      teamMember = await _beforeTeamMember(
        context,
        'add',
        user,
        teamMember,
        organization,
      );
    }
    final accepted = await store.acceptInvitation(
      AuthOrganizationInvitationAcceptance(
        invitationId: transformed.id,
        email: email,
        membership: member,
        membershipLimit: options.membershipLimit,
        teamMembership: teamMember,
        teamMemberLimit: options.teams.teamMemberLimit,
        now: DateTime.now().toUtc(),
      ),
    );
    final warnings = await _afterInvitation(
      context,
      'accept',
      user,
      accepted.invitation,
      organization,
    );
    warnings.addAll(
      await _afterMember(
        context,
        'add',
        user,
        accepted.membership,
        organization,
      ),
    );
    if (accepted.teamMembership != null) {
      warnings.addAll(
        await _afterTeamMember(
          context,
          'add',
          user,
          accepted.teamMembership!,
          organization,
        ),
      );
    }
    warnings.addAll(
      await _emit(
        'organization.invitation.accepted',
        user,
        organization.id,
        accepted.invitation.toJson(includeActionId: false),
      ),
    );
    return AuthOrganizationMutationResult(
      data: accepted.membership,
      warnings: warnings,
    );
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  _respondToInvitation(
    TContext context,
    AuthUser user,
    bool emailVerified,
    String invitationId,
    AuthOrganizationInvitationStatus status,
  ) async {
    final invitation = await _getInvitation(user, emailVerified, invitationId);
    final organization = await store.findOrganization(
      invitation.organizationId,
    );
    if (organization == null) throw AuthFlowException('organization_not_found');
    await _beforeInvitation(
      context,
      status.name,
      user,
      invitation,
      organization,
    );
    final storedUpdate = await _atomicMutationStore()
        .executeOrganizationMutation(
          AuthOrganizationTransitionInvitationCommand(
            expectedInvitation: invitation,
            status: status,
            now: DateTime.now().toUtc(),
            actorId: user.id,
            actorEmail: _requiredEmail(user),
          ),
        );
    final updated = storedUpdate.value;
    final warnings = await _afterInvitation(
      context,
      status.name,
      user,
      updated,
      organization,
    );
    warnings.addAll(
      await _emit(
        'organization.invitation.${status.name}',
        user,
        organization.id,
        updated.toJson(includeActionId: false),
      ),
    );
    return AuthOrganizationMutationResult(data: updated, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationInvitation>>
  _cancelInvitation(
    TContext context,
    AuthUser user,
    String invitationId,
  ) async {
    final invitation = await store.findInvitation(invitationId);
    if (invitation == null) throw AuthFlowException('invitation_not_found');
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: invitation.organizationId,
      resource: 'invitation',
      action: 'cancel',
    );
    await _beforeInvitation(
      context,
      'cancel',
      user,
      invitation,
      auth.organization,
    );
    final storedCancellation = await _atomicMutationStore()
        .executeOrganizationMutation(
          AuthOrganizationTransitionInvitationCommand(
            expectedInvitation: invitation,
            status: AuthOrganizationInvitationStatus.canceled,
            now: DateTime.now().toUtc(),
            actorId: user.id,
            actorMembership: auth.membership,
            actorRoleSnapshots: auth.authorizationRoleSnapshots,
          ),
        );
    final canceled = storedCancellation.value;
    final warnings = await _afterInvitation(
      context,
      'cancel',
      user,
      canceled,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.invitation.canceled',
        user,
        auth.organization.id,
        canceled.toJson(includeActionId: false),
      ),
    );
    return AuthOrganizationMutationResult(data: canceled, warnings: warnings);
  }

  Future<AuthOrganizationInvitation> _getInvitation(
    AuthUser user,
    bool emailVerified,
    String invitationId,
  ) async {
    final invitation = await store.findInvitation(invitationId);
    if (invitation == null) throw AuthFlowException('invitation_not_found');
    if (invitation.email != normalizeAuthEmail(_requiredEmail(user))) {
      throw AuthFlowException('invitation_email_mismatch');
    }
    final customGeneratorNeedsVerification =
        options.invitationIdGenerator != null &&
        !options.invitationIdGeneratorIsOpaque;
    if ((options.requireVerifiedEmailForInvitations ||
            customGeneratorNeedsVerification) &&
        !emailVerified) {
      throw AuthFlowException('verified_email_required');
    }
    return invitation;
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> _createRole(
    TContext context,
    AuthUser user,
    String? id,
    Map<String, dynamic> input,
  ) async {
    _requireDynamicRoles();
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'role',
      action: 'create',
    );
    final name = _roleName(_string(input, 'name'));
    if (accessControl.isKnownStaticRole(name)) {
      throw AuthFlowException('predefined_role');
    }
    final now = DateTime.now().toUtc();
    var role = AuthOrganizationRole(
      id: secureRandomToken(length: 16),
      organizationId: auth.organization.id,
      name: name,
      permissions: _permissions(input['permissions']),
      createdAt: now,
      updatedAt: now,
    );
    role = await _beforeRole(context, 'create', user, role, auth.organization);
    final storedRole = await _atomicMutationStore().executeOrganizationMutation(
      AuthOrganizationRoleMutationCommand(
        kind: AuthOrganizationRoleMutationKind.create,
        actorMembership: auth.membership,
        role: role,
        creatorRole: _creatorRole,
        roleLimit: options.dynamicRoleLimit,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
        idempotency: AuthOrganizationIdempotency(
          key: _idempotencyKey(input),
          organizationId: auth.organization.id,
          actorId: user.id,
          operationId: 'organization.createRole',
          fingerprint: _fingerprint(
            role.toJson(),
            volatileKeys: const {'id', 'createdAt', 'updatedAt'},
          ),
        ),
      ),
    );
    role = storedRole.value;
    if (storedRole.replayed) {
      return AuthOrganizationMutationResult(
        data: role,
        warnings: const <AuthOrganizationWarning>[],
      );
    }
    final warnings = await _afterRole(
      context,
      'create',
      user,
      role,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.role.created',
        user,
        auth.organization.id,
        role.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: role, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> _updateRole(
    TContext context,
    AuthUser user,
    String? id,
    Map<String, dynamic> input,
  ) async {
    _requireDynamicRoles();
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'role',
      action: 'update',
    );
    final previousName = _roleName(_string(input, 'name'));
    final existing = await store.findRole(auth.organization.id, previousName);
    if (existing == null) throw AuthFlowException('role_not_found');
    final nextName = _optionalString(input, 'newName') == null
        ? previousName
        : _roleName(_string(input, 'newName'));
    if (accessControl.isKnownStaticRole(nextName)) {
      throw AuthFlowException('predefined_role');
    }
    var role = existing.copyWith(
      name: nextName,
      permissions: input.containsKey('permissions')
          ? _permissions(input['permissions'])
          : null,
      updatedAt: DateTime.now().toUtc(),
    );
    role = await _beforeRole(context, 'update', user, role, auth.organization);
    role = (await _atomicMutationStore().executeOrganizationMutation(
      AuthOrganizationRoleMutationCommand(
        kind: AuthOrganizationRoleMutationKind.update,
        actorMembership: auth.membership,
        role: role,
        expectedRole: existing,
        previousName: previousName,
        creatorRole: _creatorRole,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
      ),
    )).value;
    final warnings = await _afterRole(
      context,
      'update',
      user,
      role,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.role.updated',
        user,
        auth.organization.id,
        role.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: role, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationRole>> _deleteRole(
    TContext context,
    AuthUser user,
    String? id,
    String name,
  ) async {
    _requireDynamicRoles();
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'role',
      action: 'delete',
    );
    final role = await store.findRole(auth.organization.id, _roleName(name));
    if (role == null) throw AuthFlowException('role_not_found');
    await _beforeRole(context, 'delete', user, role, auth.organization);
    final deleted = (await _atomicMutationStore().executeOrganizationMutation(
      AuthOrganizationRoleMutationCommand(
        kind: AuthOrganizationRoleMutationKind.delete,
        actorMembership: auth.membership,
        role: role,
        creatorRole: _creatorRole,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
      ),
    )).value;
    final warnings = await _afterRole(
      context,
      'delete',
      user,
      deleted,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.role.deleted',
        user,
        auth.organization.id,
        deleted.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: deleted, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> _createTeam(
    TContext context,
    AuthUser user,
    String? id,
    Map<String, dynamic> input,
  ) async {
    _requireTeams();
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'team',
      action: 'create',
    );
    final now = DateTime.now().toUtc();
    var team = AuthOrganizationTeam(
      id: secureRandomToken(length: 16),
      organizationId: auth.organization.id,
      name: _required(_string(input, 'name'), 'invalid_team_name'),
      attributes: _jsonMap(input['attributes']),
      createdAt: now,
      updatedAt: now,
    );
    team = await _beforeTeam(context, 'create', user, team, auth.organization);
    final storedTeam = await _atomicMutationStore().executeOrganizationMutation(
      AuthOrganizationTeamMutationCommand(
        kind: AuthOrganizationTeamMutationKind.create,
        actorMembership: auth.membership,
        team: team,
        teamLimit: options.teams.teamLimit,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
        idempotency: AuthOrganizationIdempotency(
          key: _idempotencyKey(input),
          organizationId: auth.organization.id,
          actorId: user.id,
          operationId: 'organization.createTeam',
          fingerprint: _fingerprint(
            team.toJson(),
            volatileKeys: const {'id', 'createdAt', 'updatedAt'},
          ),
        ),
      ),
    );
    team = storedTeam.value;
    if (storedTeam.replayed) {
      return AuthOrganizationMutationResult(
        data: team,
        warnings: const <AuthOrganizationWarning>[],
      );
    }
    final warnings = await _afterTeam(
      context,
      'create',
      user,
      team,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.team.created',
        user,
        auth.organization.id,
        team.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: team, warnings: warnings);
  }

  Future<Map<String, dynamic>> _listTeams(
    TContext context,
    AuthUser user,
    String? id,
  ) async {
    _requireTeams();
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: _requiredId(id),
      resource: 'team',
      action: 'read',
    );
    return {
      'teams': (await store.listTeams(
        auth.organization.id,
      )).map((team) => team.toJson()).toList(),
    };
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> _updateTeam(
    TContext context,
    AuthUser user,
    String teamId,
    Map<String, dynamic> input,
  ) async {
    _requireTeams();
    final team = await store.findTeam(teamId);
    if (team == null) throw AuthFlowException('team_not_found');
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: team.organizationId,
      resource: 'team',
      action: 'update',
    );
    var updated = team.copyWith(
      name: _string(input, 'name'),
      updatedAt: DateTime.now().toUtc(),
    );
    updated = await _beforeTeam(
      context,
      'update',
      user,
      updated,
      auth.organization,
    );
    updated = (await _atomicMutationStore().executeOrganizationMutation(
      AuthOrganizationTeamMutationCommand(
        kind: AuthOrganizationTeamMutationKind.update,
        actorMembership: auth.membership,
        team: updated,
        expectedTeam: team,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
      ),
    )).value;
    final warnings = await _afterTeam(
      context,
      'update',
      user,
      updated,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.team.updated',
        user,
        auth.organization.id,
        updated.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: updated, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationTeam>> _removeTeam(
    TContext context,
    AuthUser user,
    String teamId,
  ) async {
    _requireTeams();
    final team = await store.findTeam(teamId);
    if (team == null) throw AuthFlowException('team_not_found');
    final auth = await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: team.organizationId,
      resource: 'team',
      action: 'delete',
    );
    await _beforeTeam(context, 'delete', user, team, auth.organization);
    final deleted = (await _atomicMutationStore().executeOrganizationMutation(
      AuthOrganizationTeamMutationCommand(
        kind: AuthOrganizationTeamMutationKind.delete,
        actorMembership: auth.membership,
        team: team,
        allowLastTeam: options.teams.allowRemovingLastTeam,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
      ),
    )).value;
    final warnings = await _afterTeam(
      context,
      'delete',
      user,
      deleted,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.team.deleted',
        user,
        auth.organization.id,
        deleted.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: deleted, warnings: warnings);
  }

  Future<Map<String, dynamic>> _setActiveTeam(
    AuthOperationInvocation<TContext> invocation,
    AuthUser user,
    String? organizationId,
    Map<String, dynamic> input,
  ) async {
    _requireTeams();
    final teamId = _optionalString(input, 'teamId');
    final auth = await authorizeContext(
      context: invocation.context,
      userId: user.id,
      organizationId: organizationId,
    );
    if (teamId == null) {
      await invocation.writeActiveSelection?.call(auth.organization.id, null);
      return {'organizationId': auth.organization.id, 'teamId': null};
    }
    final team = await store.findTeam(teamId);
    if (team == null ||
        team.organizationId != auth.organization.id ||
        await store.findTeamMember(team.id, user.id) == null) {
      throw AuthFlowException('team_forbidden');
    }
    await invocation.writeActiveSelection?.call(auth.organization.id, team.id);
    return {'organizationId': auth.organization.id, 'teamId': team.id};
  }

  Future<Map<String, dynamic>> _listTeamMembers(
    TContext context,
    AuthUser user,
    String teamId,
  ) async {
    _requireTeams();
    final team = await store.findTeam(teamId);
    if (team == null) throw AuthFlowException('team_not_found');
    await _requirePermission(
      context: context,
      userId: user.id,
      organizationId: team.organizationId,
      resource: 'team-member',
      action: 'read',
    );
    return {
      'members': (await store.listTeamMembers(
        teamId,
      )).map((member) => member.toJson()).toList(),
    };
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  trustedAddTeamMember({
    required TContext context,
    required AuthUser actor,
    required String teamId,
    required String userId,
    required String idempotencyKey,
  }) async {
    _requireTeams();
    final team = await store.findTeam(teamId);
    if (team == null) throw AuthFlowException('team_not_found');
    final auth = await _requirePermission(
      context: context,
      userId: actor.id,
      organizationId: team.organizationId,
      resource: 'team-member',
      action: 'create',
    );
    var member = AuthOrganizationTeamMember(
      id: secureRandomToken(length: 16),
      teamId: teamId,
      userId: userId,
      createdAt: DateTime.now().toUtc(),
    );
    member = await _beforeTeamMember(
      context,
      'add',
      actor,
      member,
      auth.organization,
    );
    final storedMember = await _atomicMutationStore()
        .executeOrganizationMutation(
          AuthOrganizationTeamMemberMutationCommand(
            kind: AuthOrganizationTeamMemberMutationKind.add,
            actorMembership: auth.membership,
            team: team,
            teamMember: member,
            memberLimit: options.teams.teamMemberLimit,
            actorRoleSnapshots: auth.authorizationRoleSnapshots,
            idempotency: AuthOrganizationIdempotency(
              key: idempotencyKey,
              organizationId: auth.organization.id,
              actorId: actor.id,
              operationId: 'organization.addTeamMember',
              fingerprint: _fingerprint(
                member.toJson(),
                volatileKeys: const {'id', 'createdAt'},
              ),
            ),
          ),
        );
    member = storedMember.value;
    if (storedMember.replayed) {
      return AuthOrganizationMutationResult(
        data: member,
        warnings: const <AuthOrganizationWarning>[],
      );
    }
    final warnings = await _afterTeamMember(
      context,
      'add',
      actor,
      member,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.teamMember.added',
        actor,
        auth.organization.id,
        member.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: member, warnings: warnings);
  }

  Future<AuthOrganizationMutationResult<AuthOrganizationTeamMember>>
  _removeTeamMember(
    TContext context,
    AuthUser actor,
    String teamId,
    String userId,
  ) async {
    _requireTeams();
    final team = await store.findTeam(teamId);
    if (team == null) throw AuthFlowException('team_not_found');
    final auth = await _requirePermission(
      context: context,
      userId: actor.id,
      organizationId: team.organizationId,
      resource: 'team-member',
      action: 'delete',
    );
    final existing = await store.findTeamMember(teamId, userId);
    if (existing == null) throw AuthFlowException('team_member_not_found');
    await _beforeTeamMember(
      context,
      'remove',
      actor,
      existing,
      auth.organization,
    );
    final removed = (await _atomicMutationStore().executeOrganizationMutation(
      AuthOrganizationTeamMemberMutationCommand(
        kind: AuthOrganizationTeamMemberMutationKind.remove,
        actorMembership: auth.membership,
        team: team,
        teamMember: existing,
        actorRoleSnapshots: auth.authorizationRoleSnapshots,
      ),
    )).value;
    final warnings = await _afterTeamMember(
      context,
      'remove',
      actor,
      removed,
      auth.organization,
    );
    warnings.addAll(
      await _emit(
        'organization.teamMember.removed',
        actor,
        auth.organization.id,
        removed.toJson(),
      ),
    );
    return AuthOrganizationMutationResult(data: removed, warnings: warnings);
  }

  Future<void> _validateRoles(
    String organizationId,
    Iterable<String> roles,
  ) async {
    final normalized = normalizeAuthOrganizationRoles(roles);
    if (normalized.isEmpty) throw AuthFlowException('invalid_role');
    for (final role in normalized) {
      if (accessControl.isKnownStaticRole(role)) continue;
      if (!options.dynamicRoles ||
          await store.findRole(organizationId, role) == null) {
        throw AuthFlowException('invalid_role');
      }
    }
  }

  String get _creatorRole {
    final normalized = normalizeAuthOrganizationRoles([options.creatorRole]);
    if (normalized.isEmpty) throw AuthFlowException('invalid_role');
    return normalized.single;
  }

  void _requireCreatorAuthority(AuthOrganizationMember? actorMembership) {
    if (actorMembership == null ||
        !actorMembership.roles.contains(_creatorRole)) {
      throw AuthFlowException('organization_forbidden');
    }
  }

  void _requireCreatorAuthorityForRoles(
    AuthOrganizationMember actorMembership,
    Iterable<String> affectedRoles,
  ) {
    if (normalizeAuthOrganizationRoles(affectedRoles).contains(_creatorRole)) {
      _requireCreatorAuthority(actorMembership);
    }
  }

  AuthOrganizationMembershipMutationStore _membershipMutationStore() {
    final target = store;
    if (target is! AuthOrganizationMembershipMutationStore) {
      throw StateError(
        'The organization store cannot atomically authorize membership '
        'mutations while preserving an owner.',
      );
    }
    return target as AuthOrganizationMembershipMutationStore;
  }

  AuthOrganizationAtomicMutationStore _atomicMutationStore() {
    final target = store;
    if (target is! AuthOrganizationAtomicMutationStore) {
      throw StateError(
        'The organization store cannot atomically authorize organization '
        'mutations and enforce their durable invariants.',
      );
    }
    return target as AuthOrganizationAtomicMutationStore;
  }

  Future<void> _validateInvitationTeam(
    AuthOrganizationInvitation invitation,
    String organizationId,
  ) async {
    final teamId = invitation.teamId;
    if (teamId == null) return;
    _requireTeams();
    final team = await store.findTeam(teamId);
    if (team == null || team.organizationId != organizationId) {
      throw AuthFlowException('team_not_found');
    }
  }

  Future<void> _rejectExistingMemberInvitation(
    AuthOrganizationInvitation invitation,
  ) async {
    final userStore = _userStore;
    if (userStore == null) {
      throw StateError(
        'OrganizationPlugin must be registered with AuthRuntime or receive '
        'a userStore before invitations can be created.',
      );
    }
    final user = await userStore.findByEmail(invitation.email);
    if (user != null &&
        await store.findMember(invitation.organizationId, user.id) != null) {
      throw AuthFlowException('member_exists');
    }
  }

  Future<AuthOrganization> _beforeOrganization(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganization value,
  ) async =>
      await options.hooks.beforeOrganization?.call(
        AuthOrganizationHookContext(
          context: context,
          action: action,
          user: user,
          data: value,
          organization: value,
        ),
      ) ??
      value;
  Future<AuthOrganizationMember> _beforeMember(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationMember value,
    AuthOrganization organization,
  ) async =>
      await options.hooks.beforeMember?.call(
        AuthOrganizationHookContext(
          context: context,
          action: action,
          user: user,
          data: value,
          organization: organization,
        ),
      ) ??
      value;
  Future<AuthOrganizationInvitation> _beforeInvitation(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationInvitation value,
    AuthOrganization organization,
  ) async =>
      await options.hooks.beforeInvitation?.call(
        AuthOrganizationHookContext(
          context: context,
          action: action,
          user: user,
          data: value,
          organization: organization,
        ),
      ) ??
      value;
  Future<AuthOrganizationRole> _beforeRole(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationRole value,
    AuthOrganization organization,
  ) async =>
      await options.hooks.beforeRole?.call(
        AuthOrganizationHookContext(
          context: context,
          action: action,
          user: user,
          data: value,
          organization: organization,
        ),
      ) ??
      value;
  Future<AuthOrganizationTeam> _beforeTeam(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationTeam value,
    AuthOrganization organization,
  ) async =>
      await options.hooks.beforeTeam?.call(
        AuthOrganizationHookContext(
          context: context,
          action: action,
          user: user,
          data: value,
          organization: organization,
        ),
      ) ??
      value;
  Future<AuthOrganizationTeamMember> _beforeTeamMember(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationTeamMember value,
    AuthOrganization organization,
  ) async =>
      await options.hooks.beforeTeamMember?.call(
        AuthOrganizationHookContext(
          context: context,
          action: action,
          user: user,
          data: value,
          organization: organization,
        ),
      ) ??
      value;

  Future<List<AuthOrganizationWarning>> _afterOrganization(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganization value,
  ) => _runAfter(
    'organization.$action',
    value.id,
    () => options.hooks.afterOrganization?.call(
      AuthOrganizationHookContext(
        context: context,
        action: action,
        user: user,
        data: value,
        organization: value,
      ),
    ),
  );
  Future<List<AuthOrganizationWarning>> _afterMember(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationMember value,
    AuthOrganization organization,
  ) => _runAfter(
    'member.$action',
    organization.id,
    () => options.hooks.afterMember?.call(
      AuthOrganizationHookContext(
        context: context,
        action: action,
        user: user,
        data: value,
        organization: organization,
      ),
    ),
  );
  Future<List<AuthOrganizationWarning>> _afterInvitation(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationInvitation value,
    AuthOrganization organization,
  ) => _runAfter(
    'invitation.$action',
    organization.id,
    () => options.hooks.afterInvitation?.call(
      AuthOrganizationHookContext(
        context: context,
        action: action,
        user: user,
        data: value,
        organization: organization,
      ),
    ),
  );
  Future<List<AuthOrganizationWarning>> _afterRole(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationRole value,
    AuthOrganization organization,
  ) => _runAfter(
    'role.$action',
    organization.id,
    () => options.hooks.afterRole?.call(
      AuthOrganizationHookContext(
        context: context,
        action: action,
        user: user,
        data: value,
        organization: organization,
      ),
    ),
  );
  Future<List<AuthOrganizationWarning>> _afterTeam(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationTeam value,
    AuthOrganization organization,
  ) => _runAfter(
    'team.$action',
    organization.id,
    () => options.hooks.afterTeam?.call(
      AuthOrganizationHookContext(
        context: context,
        action: action,
        user: user,
        data: value,
        organization: organization,
      ),
    ),
  );
  Future<List<AuthOrganizationWarning>> _afterTeamMember(
    TContext context,
    String action,
    AuthUser user,
    AuthOrganizationTeamMember value,
    AuthOrganization organization,
  ) => _runAfter(
    'teamMember.$action',
    organization.id,
    () => options.hooks.afterTeamMember?.call(
      AuthOrganizationHookContext(
        context: context,
        action: action,
        user: user,
        data: value,
        organization: organization,
      ),
    ),
  );

  Future<List<AuthOrganizationWarning>> _runAfter(
    String operation,
    String organizationId,
    FutureOr<void>? Function() callback,
  ) async {
    try {
      await callback();
      return <AuthOrganizationWarning>[];
    } catch (error, stackTrace) {
      await _report(operation, error, stackTrace, organizationId);
      return [const AuthOrganizationWarning(code: 'after_commit_hook_failed')];
    }
  }

  Future<List<AuthOrganizationWarning>> _emit(
    String type,
    AuthUser actor,
    String? organizationId,
    Map<String, dynamic> payload,
  ) async {
    final sink = options.emitEvent;
    if (sink == null) return <AuthOrganizationWarning>[];
    try {
      await sink(
        AuthOrganizationLifecycleEvent(
          type: type,
          actorUserId: actor.id,
          organizationId: organizationId,
          occurredAt: DateTime.now().toUtc(),
          payload: payload,
        ),
      );
      return <AuthOrganizationWarning>[];
    } catch (error, stackTrace) {
      await _report('event.$type', error, stackTrace, organizationId);
      return [const AuthOrganizationWarning(code: 'audit_event_failed')];
    }
  }

  Future<void> _report(
    String operation,
    Object error,
    StackTrace stackTrace,
    String? organizationId,
  ) async {
    try {
      await options.reportFailure?.call(
        AuthOrganizationInternalFailure(
          operation: operation,
          error: error,
          stackTrace: stackTrace,
          organizationId: organizationId,
        ),
      );
    } catch (_) {
      // Reporting is isolated from committed operation correctness.
    }
  }

  void _requireDynamicRoles() {
    if (!options.dynamicRoles) {
      throw AuthFlowException('dynamic_roles_disabled');
    }
  }

  void _requireTeams() {
    if (!options.teams.enabled) throw AuthFlowException('teams_disabled');
  }
}

String _idempotencyKey(Map<String, dynamic> input) {
  final value = input['idempotencyKey'];
  if (value is! String || value.trim().isEmpty) {
    throw AuthFlowException('invalid_idempotency_key');
  }
  return value.trim();
}

String _fingerprint(
  Object? value, {
  Set<String> volatileKeys = const <String>{},
}) => sha256
    .convert(
      utf8.encode(jsonEncode(_canonicalOrganizationValue(value, volatileKeys))),
    )
    .toString();

Object? _canonicalOrganizationValue(Object? value, Set<String> volatileKeys) {
  if (value is Map) {
    final keys =
        value.keys
            .map((key) => key.toString())
            .where((key) => !volatileKeys.contains(key))
            .toList(growable: false)
          ..sort();
    return <String, Object?>{
      for (final key in keys)
        key: _canonicalOrganizationValue(value[key], volatileKeys),
    };
  }
  if (value is Iterable) {
    return value
        .map((item) => _canonicalOrganizationValue(item, volatileKeys))
        .toList(growable: false);
  }
  return value;
}

final class _InMemoryOrganizationDeletionOperation
    implements AuthInMemoryUserDeletionOperation {
  const _InMemoryOrganizationDeletionOperation({
    required this.store,
    required this.user,
    required this.creatorRole,
  });

  final AuthOrganizationUserDeletionStore store;
  final AuthUser user;
  final String creatorRole;

  @override
  Object captureState() =>
      (store as AuthInMemoryDeletionState).captureDeletionState();

  @override
  Future<void> apply() async {
    await store.deleteUserData(
      user.id,
      email: user.email,
      creatorRole: creatorRole,
    );
  }

  @override
  Future<void> restoreState(Object state) async {
    await (store as AuthInMemoryDeletionState).restoreDeletionState(state);
  }
}

const AuthOperationCodec<Map<String, dynamic>> _mapCodec = AuthOperationCodec(
  decode: _identityMap,
  encode: _identityMap,
);
const AuthOperationCodec<Object?> _objectCodec = AuthOperationCodec(
  decode: _decodeObject,
  encode: _identityObject,
);

Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _decodeObject(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

String _required(String value, String code) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw AuthFlowException(code);
  return normalized;
}

String _slug(String value) {
  final slug = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
    throw AuthFlowException('invalid_organization_slug');
  }
  return slug;
}

String _roleName(String value) {
  final name = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(name)) {
    throw AuthFlowException('invalid_role');
  }
  return name;
}

String _string(Map<String, dynamic> input, String key) {
  final value = input[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw AuthFlowException('invalid_$key');
  return value;
}

String? _optionalString(Map<String, dynamic> input, String key) {
  if (!input.containsKey(key) || input[key] == null) return null;
  final value = input[key].toString().trim();
  return value.isEmpty ? null : value;
}

String _requiredId(String? value) {
  final id = value?.trim() ?? '';
  if (id.isEmpty) throw AuthFlowException('organization_not_selected');
  return id;
}

String _requiredEmail(AuthUser user) {
  final email = normalizeAuthEmail(user.email ?? '');
  if (email.isEmpty) throw AuthFlowException('email_required');
  return email;
}

int _int(Map<String, dynamic> input, String key, {int fallback = 0}) {
  final value = input[key];
  return value is int ? value : int.tryParse('$value') ?? fallback;
}

Map<String, dynamic>? _jsonMap(Object? value) => value is Map
    ? <String, dynamic>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      }
    : null;

Iterable<String> _roles(Map<String, dynamic> input) {
  final value = input['roles'] ?? input['role'];
  if (value is Iterable && value is! String) {
    return value.map((item) => '$item');
  }
  if (value != null) return ['$value'];
  return const ['member'];
}

Map<String, Iterable<String>> _permissions(Object? value) {
  if (value is! Map) throw AuthFlowException('invalid_permissions');
  final result = <String, Iterable<String>>{};
  for (final entry in value.entries) {
    final actions = entry.value;
    if (actions is! Iterable || actions is String) {
      throw AuthFlowException('invalid_permissions');
    }
    result['${entry.key}'] = actions.map((action) => '$action');
  }
  if (result.isEmpty) throw AuthFlowException('invalid_permissions');
  return result;
}
