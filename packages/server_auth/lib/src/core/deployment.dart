import 'account_deletion.dart';
import 'api_key.dart';
import 'auth_config.dart';
import 'email_change.dart';
import 'options.dart';
import 'password_reset.dart';
import 'runtime_posture.dart';

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

  final AuthPasswordResetSender<TContext>? passwordReset;
  final AuthEmailChangeSender<TContext>? emailChange;
  final AuthAccountDeletionSender<TContext>? accountDeletion;

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

  final AuthOptions<TContext> options;
  final AuthConfig configuration;
  final AuthProxyPolicy proxyPolicy;

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

  final AuthApiKeyPlugin<TContext> apiKeys;
}
