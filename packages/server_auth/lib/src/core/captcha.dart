import 'dart:async';

import 'package:server_auth/src/core/exceptions.dart';
import 'package:server_auth/src/core/plugin.dart';
import 'package:server_auth/src/core/providers.dart';
import 'package:server_auth/src/core/tokens.dart' show hashOpaqueToken;

/// Stable ID for the opt-in captcha policy plugin.
const authCaptchaPluginId = 'captcha';

/// Generic public error returned for every captcha rejection, malformed token,
/// provider exception, and provider timeout.
const authCaptchaFailedErrorCode = 'captcha_failed';

/// Controls whether the application-owned verifier or this plugin owns token
/// replay prevention.
enum AuthCaptchaTokenUsePolicy {
  /// Lets the configured captcha provider reject replayed tokens.
  providerManaged,

  /// Rejects a token after this process accepts it once.
  oneTime,
}

/// Typed limits for the captcha provider boundary.
final class AuthCaptchaPluginConfig {
  /// Creates the limits used by a [CaptchaPlugin].
  const AuthCaptchaPluginConfig({
    this.providerTimeout = const Duration(seconds: 3),
    this.maxTokenLength = 4096,
    this.tokenUsePolicy = AuthCaptchaTokenUsePolicy.providerManaged,
    this.replayRetention = const Duration(minutes: 10),
    this.maxTrackedTokens = 4096,
    this.clock,
  }) : assert(
         maxTokenLength > 0 && maxTokenLength <= 16384,
         'maxTokenLength must be between 1 and 16384',
       ),
       assert(
         maxTrackedTokens > 0 && maxTrackedTokens <= 100000,
         'maxTrackedTokens must be between 1 and 100000',
       );

  /// Maximum time allowed for one application-owned vendor verification.
  final Duration providerTimeout;

  /// Maximum UTF-16 code-unit length accepted for a client captcha token.
  final int maxTokenLength;

  /// Whether replay prevention is delegated to the application provider or
  /// enforced by this process before a token can be verified twice.
  final AuthCaptchaTokenUsePolicy tokenUsePolicy;

  /// How long an accepted one-time token digest remains blocked.
  final Duration replayRetention;

  /// Bound on accepted one-time token digests retained by this process.
  final int maxTrackedTokens;

  /// Injectable clock for deterministic replay tests.
  final DateTime Function()? clock;
}

/// Typed input passed to an application-owned captcha verifier.
///
/// [token] is a request secret. It must only be used for the vendor call and
/// must never be logged, persisted, returned, or included in an exception.
final class AuthCaptchaVerificationRequest<TContext> {
  /// Creates the bounded request passed to [AuthCaptchaVerifier.verify].
  const AuthCaptchaVerificationRequest({
    required this.context,
    required this.token,
    required this.operation,
    required this.provider,
    this.identifier,
  });

  /// Application context associated with the protected operation.
  final TContext context;

  /// The provider token supplied by the client.
  final String token;

  /// The credential operation being protected.
  final AuthCredentialPolicyOperation operation;

  /// The auth provider handling the credential operation.
  final AuthProvider provider;

  /// The normalized credential identifier, when one was supplied.
  final String? identifier;
}

/// Typed result returned by an application-owned captcha verifier.
final class AuthCaptchaVerificationResult {
  /// Creates a result with the explicit [accepted] decision.
  const AuthCaptchaVerificationResult({required this.accepted});

  /// Creates an accepted verification result.
  const AuthCaptchaVerificationResult.accepted() : accepted = true;

  /// Creates a rejected verification result.
  const AuthCaptchaVerificationResult.rejected() : accepted = false;

  /// Whether the captcha provider accepted the token.
  final bool accepted;
}

/// Application-owned captcha vendor boundary.
///
/// The application decides how to call its chosen vendor. The auth package
/// supplies only bounded input, a timeout, and a stable accepted/rejected
/// result contract; it does not depend on a captcha SDK or HTTP API.
abstract interface class AuthCaptchaVerifier<TContext> {
  /// Verifies a captcha token with the application-selected provider.
  FutureOr<AuthCaptchaVerificationResult> verify(
    AuthCaptchaVerificationRequest<TContext> request,
  );
}

/// Opt-in captcha protection for credential registration and sign-in.
final class CaptchaPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthCredentialPolicyContributor<TContext> {
  /// Creates a captcha policy plugin backed by [verifier].
  CaptchaPlugin({
    required this.verifier,
    this.config = const AuthCaptchaPluginConfig(),
  }) {
    _validateConfig(config);
  }

  /// Application-owned verifier used for vendor calls.
  final AuthCaptchaVerifier<TContext> verifier;

  /// Bounds and replay policy applied before verification.
  final AuthCaptchaPluginConfig config;
  final Map<String, DateTime> _acceptedTokenDigests = <String, DateTime>{};
  final Set<String> _inFlightTokenDigests = <String>{};
  bool _configured = false;

  @override
  String get id => authCaptchaPluginId;

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract.none();

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _configured = true;
  }

  @override
  Future<void> enforceCredentialPolicy(
    AuthCredentialPolicyRequest<TContext> request,
  ) async {
    _ensureConfigured();
    final token = request.verificationToken;
    if (token == null ||
        token.trim().isEmpty ||
        token.length > config.maxTokenLength) {
      throw AuthFlowException(authCaptchaFailedErrorCode);
    }

    final verificationRequest = AuthCaptchaVerificationRequest<TContext>(
      context: request.context,
      token: token,
      operation: request.operation,
      provider: request.provider,
      identifier: request.identifier,
    );
    if (config.tokenUsePolicy == AuthCaptchaTokenUsePolicy.providerManaged) {
      await _verify(verificationRequest);
      return;
    }

    final now = _now();
    _purgeExpired(now);
    final digest = hashOpaqueToken(token);
    if (_acceptedTokenDigests.containsKey(digest) ||
        !_inFlightTokenDigests.add(digest)) {
      throw AuthFlowException(authCaptchaFailedErrorCode);
    }
    try {
      await _verify(verificationRequest);
      final acceptedAt = _now();
      _purgeExpired(acceptedAt);
      if (_acceptedTokenDigests.length >= config.maxTrackedTokens) {
        throw AuthFlowException(authCaptchaFailedErrorCode);
      }
      _acceptedTokenDigests[digest] = acceptedAt.add(config.replayRetention);
    } finally {
      _inFlightTokenDigests.remove(digest);
    }
  }

  Future<void> _verify(AuthCaptchaVerificationRequest<TContext> request) async {
    try {
      final result = await Future<AuthCaptchaVerificationResult>.sync(
        () => verifier.verify(request),
      ).timeout(config.providerTimeout);
      if (!result.accepted) {
        throw AuthFlowException(authCaptchaFailedErrorCode);
      }
    } catch (_) {
      throw AuthFlowException(authCaptchaFailedErrorCode);
    }
  }

  void _purgeExpired(DateTime now) {
    _acceptedTokenDigests.removeWhere(
      (_, expiresAt) => !now.isBefore(expiresAt),
    );
  }

  DateTime _now() => (config.clock?.call() ?? DateTime.now()).toUtc();

  void _ensureConfigured() {
    if (!_configured) {
      throw StateError('CaptchaPlugin must be configured by AuthRuntime.');
    }
  }

  static void _validateConfig(AuthCaptchaPluginConfig config) {
    if (config.providerTimeout <= Duration.zero ||
        config.providerTimeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(
        config.providerTimeout,
        'config.providerTimeout',
        'must be greater than zero and at most 30 seconds',
      );
    }
    if (config.maxTokenLength <= 0 || config.maxTokenLength > 16384) {
      throw ArgumentError.value(
        config.maxTokenLength,
        'config.maxTokenLength',
        'must be between 1 and 16384',
      );
    }
    if (config.replayRetention <= Duration.zero ||
        config.replayRetention > const Duration(days: 1)) {
      throw ArgumentError.value(
        config.replayRetention,
        'config.replayRetention',
        'must be greater than zero and at most one day',
      );
    }
    if (config.maxTrackedTokens <= 0 || config.maxTrackedTokens > 100000) {
      throw ArgumentError.value(
        config.maxTrackedTokens,
        'config.maxTrackedTokens',
        'must be between 1 and 100000',
      );
    }
  }
}
