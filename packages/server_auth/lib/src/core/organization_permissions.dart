import 'package:server_auth/src/core/organization_models.dart';
import 'package:server_auth/src/core/organization_store.dart';

/// Permissions assigned to auth organization permission set.
typedef AuthOrganizationPermissionSet = Map<String, Iterable<String>>;

/// Static and organization-specific role resolver.
final class AuthOrganizationAccessControl {
  /// Creates an instance of AuthOrganizationAccessControl.
  AuthOrganizationAccessControl({
    Map<String, AuthOrganizationPermissionSet>? staticRoles,
    this.dynamicRoles = false,
  }) : staticRoles = Map<String, Map<String, List<String>>>.unmodifiable({
         for (final entry in {...defaultRoles, ...?staticRoles}.entries)
           entry.key.trim().toLowerCase(): normalizeAuthOrganizationPermissions(
             entry.value,
           ),
       });

  /// The roles assigned to this value.
  static const Map<String, AuthOrganizationPermissionSet> defaultRoles = {
    'owner': {
      'organization': ['create', 'read', 'update', 'delete'],
      'member': ['create', 'read', 'update', 'delete'],
      'invitation': ['create', 'read', 'cancel'],
      'role': ['create', 'read', 'update', 'delete'],
      'team': ['create', 'read', 'update', 'delete'],
      'team-member': ['create', 'read', 'delete'],
    },
    'admin': {
      'organization': ['read', 'update'],
      'member': ['create', 'read', 'update', 'delete'],
      'invitation': ['create', 'read', 'cancel'],
      'role': ['read'],
      'team': ['create', 'read', 'update', 'delete'],
      'team-member': ['create', 'read', 'delete'],
    },
    'member': {
      'organization': ['read'],
      'member': ['read'],
      'invitation': ['read'],
      'role': ['read'],
      'team': ['read'],
      'team-member': ['read'],
    },
  };

  /// The roles assigned to this value.
  final Map<String, Map<String, List<String>>> staticRoles;

  /// The roles assigned to this value.
  final bool dynamicRoles;

  /// Checks whether the requested operation is authorized.
  Future<bool> allows({
    required AuthOrganizationStore store,
    required AuthOrganizationMember member,
    required String resource,
    required String action,
  }) async => (await authorize(
    store: store,
    member: member,
    resource: resource,
    action: action,
  )).allowed;

  /// Checks whether the requested operation is authorized.
  Future<AuthOrganizationPermissionDecision> authorize({
    required AuthOrganizationStore store,
    required AuthOrganizationMember member,
    required String resource,
    required String action,
  }) async {
    final normalizedResource = resource.trim().toLowerCase();
    final normalizedAction = action.trim().toLowerCase();
    if (normalizedResource.isEmpty || normalizedAction.isEmpty) {
      return const AuthOrganizationPermissionDecision(allowed: false);
    }
    final snapshots = <AuthOrganizationRole>[];
    for (final roleName in member.roles) {
      final staticPermissions = staticRoles[roleName];
      if (_allows(staticPermissions, normalizedResource, normalizedAction)) {
        return AuthOrganizationPermissionDecision(
          allowed: true,
          dynamicRoleSnapshots: snapshots,
        );
      }
      if (dynamicRoles) {
        final role = await store.findRole(member.organizationId, roleName);
        if (role != null) snapshots.add(role);
        if (_allows(role?.permissions, normalizedResource, normalizedAction)) {
          return AuthOrganizationPermissionDecision(
            allowed: true,
            dynamicRoleSnapshots: snapshots,
          );
        }
      }
    }
    return AuthOrganizationPermissionDecision(
      allowed: false,
      dynamicRoleSnapshots: snapshots,
    );
  }

  /// Returns whether this value is known static role.
  bool isKnownStaticRole(String role) =>
      staticRoles.containsKey(role.trim().toLowerCase());
}

/// Authentication data for auth organization permission decision.
final class AuthOrganizationPermissionDecision {
  /// Creates an instance of AuthOrganizationPermissionDecision.
  const AuthOrganizationPermissionDecision({
    required this.allowed,
    this.dynamicRoleSnapshots = const <AuthOrganizationRole>[],
  });

  /// The allowed associated with this value.
  final bool allowed;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> dynamicRoleSnapshots;
}

bool _allows(
  Map<String, Iterable<String>>? permissions,
  String resource,
  String action,
) {
  if (permissions == null) return false;
  final actions = permissions[resource] ?? permissions['*'];
  return actions?.any((value) {
        final normalized = value.trim().toLowerCase();
        return normalized == action || normalized == '*';
      }) ??
      false;
}

/// Explicit tenant authorization context. Organization roles stay separate
/// from global principal roles.
final class AuthOrganizationAuthorizationContext<TContext> {
  /// Creates an instance of AuthOrganizationAuthorizationContext.
  const AuthOrganizationAuthorizationContext({
    required this.context,
    required this.userId,
    required this.organization,
    required this.membership,
    this.team,
    this.authorizationRoleSnapshots = const <AuthOrganizationRole>[],
  });

  /// The host context associated with this operation.
  final TContext context;

  /// The identifier of the user.
  final String userId;

  /// The organization associated with this value.
  final AuthOrganization organization;

  /// The membership associated with this value.
  final AuthOrganizationMember membership;

  /// The team associated with this value.
  final AuthOrganizationTeam? team;

  /// The roles assigned to this value.
  final List<AuthOrganizationRole> authorizationRoleSnapshots;

  /// Performs the owns user operation.
  bool ownsUser(String resourceUserId) => userId == resourceUserId.trim();
}
