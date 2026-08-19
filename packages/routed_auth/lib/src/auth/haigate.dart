// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:server_auth/server_auth.dart'
    show
        AuthGateCallback,
        AuthGateObserver,
        AuthGateRegistry,
        AuthGateService,
        AuthGateViolation,
        AuthFlowException,
        AuthOrganizationAuthorizationContext,
        OrganizationFeature,
        PolicyBinding,
        syncManagedPolicyBindings,
        AuthPrincipal;
import 'package:routed_auth/src/auth/session_auth.dart';
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/response.dart';
import 'package:routed_core/src/router/types.dart';
import 'package:routed_sessions/routed_sessions.dart';

/// A function that provides a payload for a specific ability in the given
/// [EngineContext].
typedef GatePayloadProvider =
    Object? Function(EngineContext ctx, String ability);

/// Backward-compatible alias for denied authorization exceptions.
typedef GateViolation = AuthGateViolation<EngineContext>;

/// A handler function that is called when a gate denies access.
typedef GateDeniedHandler =
    FutureOr<Response?> Function(
      AuthGateViolation<EngineContext> violation,
      EngineContext ctx,
    );

/// Global gate registry used by [Haigate].
final AuthGateRegistry<EngineContext> gateRegistry =
    AuthGateRegistry<EngineContext>();
final Set<String> _managedPolicyAbilities = <String>{};

/// Registers policy bindings into [gateRegistry] with stable ability tracking.
Set<String> registerPoliciesWithHaigate(List<PolicyBinding> bindings) {
  return syncManagedPolicyBindings<EngineContext>(
    gateRegistry,
    bindings,
    managed: _managedPolicyAbilities,
  );
}

class Haigate {
  Haigate._();

  static final AuthGateService<EngineContext> _service =
      AuthGateService<EngineContext>(
        registry: gateRegistry,
        principalResolver: (EngineContext context) {
          try {
            return SessionAuth.current(context);
          } on StateError {
            return null;
          }
        },
      );

  static final AuthGateRegistry<EngineContext> _registry = _service.registry;

  static AuthGateRegistry<EngineContext> get registry => _registry;

  /// Resolves and revalidates explicit tenant membership for this request.
  static Future<AuthOrganizationAuthorizationContext<EngineContext>>
  organizationContext({
    required EngineContext ctx,
    required OrganizationFeature<EngineContext> feature,
    String? organizationId,
    String? teamId,
  }) async {
    final principal = SessionAuth.current(ctx);
    if (principal == null) throw AuthFlowException('unauthorized');
    final sessionOrganizationId = ctx.hasSession
        ? ctx.getSession<String>('__routed.auth.activeOrganizationId')?.trim()
        : null;
    final requestedOrganizationId = organizationId != null
        ? organizationId.trim()
        : sessionOrganizationId;
    final inheritsActiveTeam =
        teamId == null &&
        requestedOrganizationId != null &&
        requestedOrganizationId == sessionOrganizationId;
    final requestedTeamId = teamId != null
        ? (teamId.trim().isEmpty ? null : teamId.trim())
        : inheritsActiveTeam && ctx.hasSession
        ? ctx.getSession<String>('__routed.auth.activeTeamId')?.trim()
        : null;
    try {
      return await feature.authorizeContext(
        context: ctx,
        userId: principal.id,
        organizationId: requestedOrganizationId,
        teamId: requestedTeamId,
      );
    } on AuthFlowException catch (error) {
      final staleInheritedTeam =
          inheritsActiveTeam &&
          requestedTeamId?.isNotEmpty == true &&
          (error.code == 'team_not_found' || error.code == 'team_forbidden');
      if (!staleInheritedTeam) rethrow;
      ctx.removeSession('__routed.auth.activeTeamId');
      return feature.authorizeContext(
        context: ctx,
        userId: principal.id,
        organizationId: requestedOrganizationId,
      );
    }
  }

  /// Checks an organization permission without copying organization roles into
  /// the global [AuthPrincipal].
  static Future<bool> canInOrganization({
    required EngineContext ctx,
    required OrganizationFeature<EngineContext> feature,
    required String resource,
    required String action,
    String? organizationId,
    String? teamId,
  }) async {
    final principal = SessionAuth.current(ctx);
    if (principal == null) return false;
    try {
      final organization = await organizationContext(
        ctx: ctx,
        feature: feature,
        organizationId: organizationId,
        teamId: teamId,
      );
      return await feature.hasPermission(
        context: ctx,
        userId: principal.id,
        organizationId: organization.organization.id,
        resource: resource,
        action: action,
      );
    } on AuthFlowException {
      return false;
    }
  }

  /// Allows the authenticated resource owner, otherwise checks a tenant role.
  static Future<bool> ownsOrCanInOrganization({
    required EngineContext ctx,
    required OrganizationFeature<EngineContext> feature,
    required String resourceOwnerId,
    required String resource,
    required String action,
    String? organizationId,
    String? teamId,
  }) async {
    final principal = SessionAuth.current(ctx);
    if (principal?.id == resourceOwnerId.trim()) return true;
    return canInOrganization(
      ctx: ctx,
      feature: feature,
      resource: resource,
      action: action,
      organizationId: organizationId,
      teamId: teamId,
    );
  }

  static void register(
    String ability,
    AuthGateCallback<EngineContext> callback,
  ) {
    _registry.register(ability, callback);
  }

  static void registerAll(
    Map<String, AuthGateCallback<EngineContext>> entries,
  ) {
    _registry.registerAll(entries);
  }

  static void unregister(String ability) {
    _service.unregister(ability);
  }

  static void addObserver(AuthGateObserver<EngineContext> observer) {
    _service.addObserver(observer);
  }

  static void removeObserver(AuthGateObserver<EngineContext> observer) {
    _service.removeObserver(observer);
  }

  static Future<bool> can(
    String ability, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    return _service.can(
      ability,
      context: ctx,
      principal: principal,
      payload: payload,
    );
  }

  static Future<void> authorize(
    String ability, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
    String? message,
  }) async {
    await _service.authorize(
      ability,
      context: ctx,
      principal: principal,
      payload: payload,
      message: message,
    );
  }

  static Future<bool> any(
    Iterable<String> abilities, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    return _service.any(
      abilities,
      context: ctx,
      principal: principal,
      payload: payload,
    );
  }

  static Future<bool> all(
    Iterable<String> abilities, {
    required EngineContext ctx,
    AuthPrincipal? principal,
    Object? payload,
  }) async {
    return _service.all(
      abilities,
      context: ctx,
      principal: principal,
      payload: payload,
    );
  }

  static Middleware middleware(
    List<String> abilities, {
    GatePayloadProvider? payloadProvider,
    GateDeniedHandler? onDenied,
    int deniedStatusCode = HttpStatus.forbidden,
    String? deniedMessage,
  }) {
    final requested = abilities
        .map((ability) => ability.trim())
        .where((ability) => ability.isNotEmpty)
        .toList(growable: false);

    return (EngineContext ctx, Next next) async {
      final violation = await _service.firstDenied(
        requested,
        context: ctx,
        payloadResolver: payloadProvider == null
            ? null
            : (context, ability) => payloadProvider(context, ability),
        message: deniedMessage,
      );
      if (violation != null) {
        final custom = await onDenied?.call(violation, ctx);
        if (custom != null) {
          return custom;
        }
        ctx.response
          ..statusCode = deniedStatusCode
          ..write(deniedMessage ?? 'Forbidden by gate: ${violation.ability}');
        return ctx.response;
      }
      return next();
    };
  }
}
