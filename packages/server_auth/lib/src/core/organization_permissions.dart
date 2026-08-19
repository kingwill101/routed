import 'organization_models.dart';
import 'organization_store.dart';

typedef AuthOrganizationPermissionSet = Map<String, Iterable<String>>;

/// Static and organization-specific role resolver.
final class AuthOrganizationAccessControl {
  AuthOrganizationAccessControl({
    Map<String, AuthOrganizationPermissionSet>? staticRoles,
    this.dynamicRoles = false,
  }) : staticRoles = Map<String, Map<String, List<String>>>.unmodifiable({
         for (final entry in {...defaultRoles, ...?staticRoles}.entries)
           entry.key.trim().toLowerCase(): normalizeAuthOrganizationPermissions(
             entry.value,
           ),
       });

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

  final Map<String, Map<String, List<String>>> staticRoles;
  final bool dynamicRoles;

  Future<bool> allows({
    required AuthOrganizationStore store,
    required AuthOrganizationMember member,
    required String resource,
    required String action,
  }) async {
    final normalizedResource = resource.trim().toLowerCase();
    final normalizedAction = action.trim().toLowerCase();
    if (normalizedResource.isEmpty || normalizedAction.isEmpty) return false;
    for (final roleName in member.roles) {
      final staticPermissions = staticRoles[roleName];
      if (_allows(staticPermissions, normalizedResource, normalizedAction)) {
        return true;
      }
      if (dynamicRoles) {
        final role = await store.findRole(member.organizationId, roleName);
        if (_allows(role?.permissions, normalizedResource, normalizedAction)) {
          return true;
        }
      }
    }
    return false;
  }

  bool isKnownStaticRole(String role) =>
      staticRoles.containsKey(role.trim().toLowerCase());
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
      }) ==
      true;
}

/// Explicit tenant authorization context. Organization roles stay separate
/// from global principal roles.
final class AuthOrganizationAuthorizationContext<TContext> {
  const AuthOrganizationAuthorizationContext({
    required this.context,
    required this.userId,
    required this.organization,
    required this.membership,
    this.team,
  });

  final TContext context;
  final String userId;
  final AuthOrganization organization;
  final AuthOrganizationMember membership;
  final AuthOrganizationTeam? team;

  bool ownsUser(String resourceUserId) => userId == resourceUserId.trim();
}
