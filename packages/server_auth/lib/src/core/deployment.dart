import 'package:server_auth/src/core/account_deletion.dart';
import 'package:server_auth/src/core/api_key.dart';
import 'package:server_auth/src/core/auth_config.dart';
import 'package:server_auth/src/core/email_change.dart';
import 'package:server_auth/src/core/options.dart';
import 'package:server_auth/src/core/password_reset.dart';
import 'package:server_auth/src/core/runtime_posture.dart';

/// Application-owned delivery behavior for account lifecycle operations.
///
/// Production presets require an explicit instance. Applications can either
/// provide all supported delivery callbacks or deliberately disable these
/// optional routes. No callback is synthesized and no raw token is logged.
final class AuthLifecycleDelivery<TContext> {
  /// Enables only the lifecycle delivery capabilities supplied by the app.
  ///
  /// Omitted callbacks leave their corresponding routes unavailable; presets
  /// never synthesize delivery or force unrelated lifecycle capabilities to
  /// be enabled together.
  const AuthLifecycleDelivery({
    this.passwordReset,
    this.emailChange,
    this.accountDeletion,
  });

  /// Explicitly disables every optional lifecycle delivery capability.
  const AuthLifecycleDelivery.disabled() : this();

  /// Callback delivering password-reset tokens, when enabled.
  final AuthPasswordResetSender<TContext>? passwordReset;

  /// Callback delivering email-change tokens, when enabled.
  final AuthEmailChangeSender<TContext>? emailChange;

  /// Callback delivering account-deletion tokens, when enabled.
  final AuthAccountDeletionSender<TContext>? accountDeletion;

  /// Whether at least one lifecycle delivery callback is configured.
  bool get hasAny =>
      passwordReset != null || emailChange != null || accountDeletion != null;
}

/// A typed auth deployment assembled from framework-neutral runtime options.
///
/// The bundle remains inspectable: callers bind [options] to their runtime,
/// pass [configuration] to their framework auth provider, and apply
/// [proxyPolicy] to the HTTP server or security provider.
class AuthDeployment<TContext> {
  /// Creates an advanced custom bundle without applying a preset.
  AuthDeployment.custom({
    required this.options,
    required this.configuration,
    required this.proxyPolicy,
  }) {
    final boundary = options.productionBoundary;
    if (options.runtimeMode == AuthRuntimeMode.production &&
        (boundary == null || !boundary.proxyPolicy.equivalentTo(proxyPolicy))) {
      throw ArgumentError.value(
        proxyPolicy,
        'proxyPolicy',
        'must match the production boundary carried by AuthOptions',
      );
    }
  }

  /// Runtime options consumed by the framework adapter.
  final AuthOptions<TContext> options;

  /// Typed adapter configuration for JWT, sessions, gates, and guards.
  final AuthConfig configuration;

  /// Proxy-trust policy applied by the framework boundary.
  final AuthProxyPolicy proxyPolicy;

  /// Whether this deployment requires durable persistence.
  bool get requiresDurableStore =>
      options.runtimeMode == AuthRuntimeMode.production;
}

/// Service deployment that retains its API-key plugin for middleware wiring.
final class AuthApiKeyDeployment<TContext> extends AuthDeployment<TContext> {
  /// Creates an advanced custom API-key bundle without applying a preset.
  AuthApiKeyDeployment.custom({
    required super.options,
    required super.configuration,
    required super.proxyPolicy,
    required this.apiKeys,
  }) : super.custom();

  /// API-key plugin retained for middleware wiring.
  final AuthApiKeyPlugin<TContext> apiKeys;
}
