import 'dart:async';
import 'dart:io';

import 'package:server_auth/server_auth.dart'
    show
        AuthGateCallback,
        AuthGateObserver,
        AuthGateRegistry,
        AuthGateService,
        AuthGateViolation,
        AuthPrincipal;
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';

/// A function that provides a payload for a specific ability in the given
/// [EngineContext].
typedef GatePayloadProvider =
    Object? Function(EngineContext ctx, String ability);

/// A handler function that is called when a gate denies access.
typedef GateDeniedHandler =
    FutureOr<Response?> Function(
      AuthGateViolation<EngineContext> violation,
      EngineContext ctx,
    );

/// Global gate registry used by [Haigate].
final AuthGateRegistry<EngineContext> gateRegistry =
    AuthGateRegistry<EngineContext>();

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
