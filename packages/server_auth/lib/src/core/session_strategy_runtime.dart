import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'callbacks.dart';
import 'jwt.dart';
import 'models.dart';
import 'session.dart';

/// Result of updating an auth session for a selected strategy.
class AuthSessionUpdateResolution {
  const AuthSessionUpdateResolution({required this.session, this.jwtCookie});

  /// Updated auth session payload.
  final AuthSession session;

  /// Issued JWT cookie when strategy is [AuthSessionStrategy.jwt].
  final Cookie? jwtCookie;
}

/// Result of resolving an auth session for a selected strategy.
class AuthSessionResolution {
  const AuthSessionResolution({this.session, this.refreshCookie});

  /// Resolved auth session; `null` when no session is available.
  final AuthSession? session;

  /// Reissued JWT cookie when refresh was required.
  final Cookie? refreshCookie;
}

/// Result of resolving sign-out behavior for a selected strategy.
class AuthSignOutResolution {
  const AuthSignOutResolution({this.expiredJwtCookie});

  /// Expired JWT cookie to attach for JWT strategy sign-out.
  final Cookie? expiredJwtCookie;
}

/// Resolves `updateSession` behavior for auth session strategies.
///
/// Session strategy uses callback hooks for framework-specific session writes.
///
/// JWT strategy uses [issueAuthJwtSessionWithCallbacks] and returns the issued
/// auth cookie in [AuthSessionUpdateResolution.jwtCookie].
Future<AuthSessionUpdateResolution>
resolveAuthSessionUpdateForStrategyWithCallbacks<TContext>({
  required AuthSessionStrategy strategy,
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required AuthPrincipal principal,
  required JwtSessionOptions jwtOptions,
  FutureOr<void> Function(AuthPrincipal principal)? persistSessionPrincipal,
  void Function()? applySessionMaxAge,
  void Function(DateTime issuedAtUtc)? writeSessionIssuedAt,
  DateTime? Function()? resolveSessionExpiry,
  DateTime? now,
}) async {
  final user = AuthUser.fromPrincipal(principal);
  switch (strategy) {
    case AuthSessionStrategy.session:
      applySessionMaxAge?.call();
      if (persistSessionPrincipal != null) {
        await Future<void>.value(persistSessionPrincipal(principal));
      }
      writeSessionIssuedAt?.call((now ?? DateTime.now()).toUtc());
      return AuthSessionUpdateResolution(
        session: AuthSession(
          user: user,
          expiresAt: resolveSessionExpiry?.call(),
          strategy: AuthSessionStrategy.session,
        ),
      );
    case AuthSessionStrategy.jwt:
      final issued = await issueAuthJwtSessionWithCallbacks<TContext>(
        callbacks: callbacks,
        context: context,
        options: jwtOptions,
        user: user,
        strategy: AuthSessionStrategy.jwt,
      );
      return AuthSessionUpdateResolution(
        session: issued.session,
        jwtCookie: issued.issued.cookie,
      );
  }
}

/// Resolves `resolveSession` behavior for auth session strategies.
///
/// Session strategy uses callback hooks for framework-specific principal/session
/// IO and session refresh touch semantics.
///
/// JWT strategy verifies and optionally refreshes token claims through
/// [resolveAuthJwtClaimsWithCallbacks].
Future<AuthSessionResolution>
resolveAuthSessionForStrategyWithCallbacks<TContext>({
  required AuthSessionStrategy strategy,
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required JwtSessionOptions jwtOptions,
  required Duration? sessionUpdateAge,
  AuthPrincipal? Function()? readSessionPrincipal,
  void Function()? applySessionMaxAge,
  String? Function()? readSessionIssuedAt,
  void Function(DateTime issuedAtUtc)? writeSessionIssuedAt,
  void Function()? touchSession,
  DateTime? Function()? resolveSessionExpiry,
  String? Function()? readJwtToken,
  http.Client? httpClient,
  DateTime? now,
}) async {
  switch (strategy) {
    case AuthSessionStrategy.session:
      final principal = readSessionPrincipal?.call();
      if (principal == null) {
        return const AuthSessionResolution();
      }

      applySessionMaxAge?.call();
      syncAuthSessionRefresh(
        issuedAtValue: readSessionIssuedAt?.call(),
        updateAge: sessionUpdateAge,
        now: now,
        writeIssuedAt: (issuedAtUtc) => writeSessionIssuedAt?.call(issuedAtUtc),
        touchSession: touchSession,
      );
      return AuthSessionResolution(
        session: AuthSession(
          user: AuthUser.fromPrincipal(principal),
          expiresAt: resolveSessionExpiry?.call(),
          strategy: AuthSessionStrategy.session,
        ),
      );
    case AuthSessionStrategy.jwt:
      final resolved = await resolveAuthJwtSessionWithRefresh(
        token: readJwtToken?.call(),
        options: jwtOptions,
        updateAge: sessionUpdateAge,
        httpClient: httpClient,
        now: now,
        resolveClaims: (claims, user) =>
            resolveAuthJwtClaimsWithCallbacks<TContext>(
              callbacks: callbacks,
              context: context,
              user: user,
              strategy: AuthSessionStrategy.jwt,
              token: claims,
            ),
      );
      if (resolved == null) {
        return const AuthSessionResolution();
      }
      return AuthSessionResolution(
        session: AuthSession(
          user: resolved.user,
          expiresAt: resolved.expiresAt,
          strategy: AuthSessionStrategy.jwt,
          token: resolved.token,
        ),
        refreshCookie: resolved.refreshCookie,
      );
  }
}

/// Resolves sign-out behavior for auth session strategies.
///
/// Session strategy executes [logoutSession].
///
/// JWT strategy returns an expired JWT cookie that callers can attach.
Future<AuthSignOutResolution> resolveAuthSignOutForStrategy({
  required AuthSessionStrategy strategy,
  required String jwtCookieName,
  FutureOr<void> Function()? logoutSession,
  String jwtCookiePath = '/',
}) async {
  switch (strategy) {
    case AuthSessionStrategy.session:
      if (logoutSession != null) {
        await Future<void>.value(logoutSession());
      }
      return const AuthSignOutResolution();
    case AuthSessionStrategy.jwt:
      return AuthSignOutResolution(
        expiredJwtCookie: buildExpiredJwtTokenCookie(
          jwtCookieName,
          path: jwtCookiePath,
        ),
      );
  }
}
