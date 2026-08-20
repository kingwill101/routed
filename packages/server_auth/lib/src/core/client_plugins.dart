import 'client.dart';
import 'models.dart';

final class AuthProviderClientPlugin
    implements AuthClientPlugin<AuthProviderClient> {
  const AuthProviderClientPlugin();

  @override
  String get id => 'providers';

  @override
  AuthProviderClient install(AuthClientPluginContext context) =>
      AuthProviderClient(_core(context));
}

final class AuthProviderClient {
  AuthProviderClient(this._core);
  final AuthClientCore _core;

  Future<List<AuthClientProvider>> list() => _core.getProviders();
}

final class AuthCredentialsClientPlugin
    implements AuthClientPlugin<AuthCredentialsClient> {
  const AuthCredentialsClientPlugin({this.provider = 'credentials'});

  final String provider;

  @override
  String get id => 'credentials:$provider';

  @override
  AuthCredentialsClient install(AuthClientPluginContext context) =>
      AuthCredentialsClient(_core(context), provider: provider);
}

final class AuthCredentialsClient {
  AuthCredentialsClient(this._core, {this.provider = 'credentials'});
  final AuthClientCore _core;
  final String provider;

  Future<AuthSession> signIn({
    String? email,
    String? username,
    required String password,
    Map<String, dynamic>? attributes,
  }) => _core.signInWithCredentials(
    provider: provider,
    email: email,
    username: username,
    password: password,
    attributes: attributes,
  );

  Future<AuthSession> register({
    String? email,
    String? username,
    required String password,
    Map<String, dynamic>? attributes,
  }) => _core.registerWithCredentials(
    provider: provider,
    email: email,
    username: username,
    password: password,
    attributes: attributes,
  );
}

final class AuthOAuthClientPlugin implements AuthClientPlugin<AuthOAuthClient> {
  const AuthOAuthClientPlugin();

  @override
  String get id => 'oauth';

  @override
  AuthOAuthClient install(AuthClientPluginContext context) =>
      AuthOAuthClient(_core(context));
}

final class AuthOAuthClient {
  AuthOAuthClient(this._core);
  final AuthClientCore _core;

  Future<Uri> begin({required String provider, String? callbackUrl}) =>
      _core.beginOAuth(provider: provider, callbackUrl: callbackUrl);

  Future<AuthClientAuthResult> complete({
    required String provider,
    required String code,
    String? state,
  }) => _core.completeOAuth(provider: provider, code: code, state: state);
}

final class AuthSessionClientPlugin
    implements AuthClientPlugin<AuthSessionClient> {
  const AuthSessionClientPlugin();

  @override
  String get id => 'session';

  @override
  AuthSessionClient install(AuthClientPluginContext context) =>
      AuthSessionClient(_core(context));
}

final class AuthSessionClient {
  AuthSessionClient(this._core);
  final AuthClientCore _core;

  Future<String> getCsrfToken() => _core.getCsrfToken();
  Future<AuthSession?> current() => _core.getSession();
  Future<List<AuthClientSession>> list() => _core.getSessions();
  Future<void> revoke(String sessionId) => _core.revokeSession(sessionId);
  Future<int> revokeOthers() => _core.revokeOtherSessions();
  Future<void> signOut() => _core.signOut();
}

final class AuthAnonymousClientPlugin
    implements AuthClientPlugin<AuthAnonymousClient> {
  const AuthAnonymousClientPlugin();

  @override
  String get id => 'anonymous';

  @override
  AuthAnonymousClient install(AuthClientPluginContext context) =>
      AuthAnonymousClient(_core(context));
}

final class AuthAnonymousClient {
  AuthAnonymousClient(this._core);
  final AuthClientCore _core;

  Future<AuthSession> signIn() => _core.signInAnonymously();
  Future<void> deleteUser() => _core.deleteAnonymousUser();
}

final class AuthDeviceAuthorizationClientPlugin
    implements AuthClientPlugin<AuthDeviceAuthorizationClient> {
  const AuthDeviceAuthorizationClientPlugin();

  @override
  String get id => 'device_authorization';

  @override
  AuthDeviceAuthorizationClient install(AuthClientPluginContext context) =>
      AuthDeviceAuthorizationClient(_core(context));
}

final class AuthDeviceAuthorizationClient {
  AuthDeviceAuthorizationClient(this._core);
  final AuthClientCore _core;

  Future<AuthClientDeviceAuthorization> authorize({
    required String clientId,
    Iterable<String> scopes = const <String>[],
  }) => _core.requestDeviceAuthorization(clientId: clientId, scopes: scopes);

  Future<AuthClientDeviceAccessToken> poll({
    required String clientId,
    required String deviceCode,
  }) => _core.pollDeviceToken(clientId: clientId, deviceCode: deviceCode);

  /// Polls until the device authorization succeeds or reaches a terminal
  /// server or local state.
  ///
  /// The first request waits for the server-issued [authorization] interval.
  /// Retryable `authorization_pending` and `slow_down` responses are handled
  /// according to RFC 8628. Other [AuthClientException] values are terminal and
  /// are rethrown. Local cancellation, caller stopping, and deadlines throw
  /// [AuthDeviceAuthorizationPollingStoppedException].
  Future<AuthClientDeviceAccessToken> pollUntilComplete({
    required String clientId,
    required AuthClientDeviceAuthorization authorization,
    AuthDeviceAuthorizationPollingOptions? options,
  }) async {
    final settings = options ?? AuthDeviceAuthorizationPollingOptions();
    final startedAt = settings.clock().toUtc();
    final authorizationDeadline = (authorization.receivedAt ?? startedAt).add(
      authorization.expiresIn,
    );
    final callerDeadline = settings.deadline?.toUtc();
    final effectiveDeadline =
        callerDeadline != null && callerDeadline.isBefore(authorizationDeadline)
        ? callerDeadline
        : authorizationDeadline;
    final deadlineReason = effectiveDeadline == authorizationDeadline
        ? AuthDeviceAuthorizationPollingStopReason.authorizationExpired
        : AuthDeviceAuthorizationPollingStopReason.deadlineReached;

    var attempts = 0;
    var interval = authorization.interval;
    AuthClientException? lastError;

    while (true) {
      _throwIfDevicePollingCancelled(settings.controller, attempts);
      final context = AuthDeviceAuthorizationPollingContext(
        attempts: attempts,
        interval: interval,
        deadline: effectiveDeadline,
        lastError: lastError,
      );
      final shouldContinue = settings.shouldContinue;
      if (shouldContinue != null &&
          !await Future<bool>.value(shouldContinue(context))) {
        throw AuthDeviceAuthorizationPollingStoppedException(
          reason: AuthDeviceAuthorizationPollingStopReason.stoppedByCaller,
          attempts: attempts,
        );
      }

      await _waitForDevicePoll(
        interval: interval,
        deadline: effectiveDeadline,
        deadlineReason: deadlineReason,
        attempts: attempts,
        settings: settings,
      );
      attempts += 1;

      try {
        return await poll(
          clientId: clientId,
          deviceCode: authorization.deviceCode,
        );
      } on AuthClientException catch (error) {
        if (error.code != 'authorization_pending' &&
            error.code != 'slow_down') {
          rethrow;
        }
        if (error.code == 'slow_down') {
          interval += const Duration(seconds: 5);
        }
        final retryAfter = error.retryAfter;
        if (retryAfter != null && retryAfter > interval) {
          interval = retryAfter;
        }
        lastError = error;
      }
    }
  }

  Future<void> approve({required String userCode}) =>
      _core.approveDeviceAuthorization(userCode: userCode);

  Future<void> deny({required String userCode}) =>
      _core.denyDeviceAuthorization(userCode: userCode);
}

Future<void> _waitForDevicePoll({
  required Duration interval,
  required DateTime deadline,
  required AuthDeviceAuthorizationPollingStopReason deadlineReason,
  required int attempts,
  required AuthDeviceAuthorizationPollingOptions settings,
}) async {
  final now = settings.clock().toUtc();
  final remaining = deadline.difference(now);
  if (remaining <= Duration.zero) {
    throw AuthDeviceAuthorizationPollingStoppedException(
      reason: deadlineReason,
      attempts: attempts,
    );
  }

  final delay = interval < remaining ? interval : remaining;
  final controller = settings.controller;
  if (controller == null) {
    await settings.delay(delay);
  } else {
    await Future.any<void>(<Future<void>>[
      settings.delay(delay),
      controller.whenCancelled,
    ]);
    _throwIfDevicePollingCancelled(controller, attempts);
  }

  if (!settings.clock().toUtc().isBefore(deadline)) {
    throw AuthDeviceAuthorizationPollingStoppedException(
      reason: deadlineReason,
      attempts: attempts,
    );
  }
}

void _throwIfDevicePollingCancelled(
  AuthDeviceAuthorizationPollingController? controller,
  int attempts,
) {
  if (controller?.isCancelled ?? false) {
    throw AuthDeviceAuthorizationPollingStoppedException(
      reason: AuthDeviceAuthorizationPollingStopReason.cancelled,
      attempts: attempts,
    );
  }
}

final class AuthApiKeyClientPlugin
    implements AuthClientPlugin<AuthApiKeyClient> {
  const AuthApiKeyClientPlugin();

  @override
  String get id => 'api_key';

  @override
  AuthApiKeyClient install(AuthClientPluginContext context) =>
      AuthApiKeyClient(_core(context));
}

final class AuthApiKeyClient {
  AuthApiKeyClient(this._core);
  final AuthClientCore _core;

  Future<List<AuthClientApiKey>> list() => _core.getApiKeys();

  Future<AuthClientIssuedApiKey> create({
    required String name,
    Iterable<String> scopes = const <String>[],
    DateTime? expiresAt,
  }) => _core.createApiKey(name: name, scopes: scopes, expiresAt: expiresAt);

  Future<void> revoke({required String id}) => _core.revokeApiKey(id: id);

  Future<AuthClientIssuedApiKey> rotate({
    required String id,
    String? name,
    Iterable<String>? scopes,
    DateTime? expiresAt,
  }) => _core.rotateApiKey(
    id: id,
    name: name,
    scopes: scopes,
    expiresAt: expiresAt,
  );

  Future<AuthSession> exchangeForSession() => _core.exchangeApiKeyForSession();
}

final class AuthWebAuthnClientPlugin
    implements AuthClientPlugin<AuthWebAuthnClient> {
  const AuthWebAuthnClientPlugin();

  @override
  String get id => 'webauthn';

  @override
  AuthWebAuthnClient install(AuthClientPluginContext context) =>
      AuthWebAuthnClient(_core(context));
}

final class AuthWebAuthnClient {
  AuthWebAuthnClient(this._core);
  final AuthClientCore _core;

  Future<AuthClientWebAuthnRegistrationOptions> beginRegistration() =>
      _core.beginWebAuthnRegistration();

  Future<AuthClientWebAuthnCredential> completeRegistration({
    required Map<String, dynamic> credential,
    String? name,
  }) => _core.completeWebAuthnRegistration(credential: credential, name: name);

  Future<AuthClientWebAuthnAuthenticationOptions> beginAuthentication({
    String? userId,
  }) => _core.beginWebAuthnAuthentication(userId: userId);

  Future<AuthClientWebAuthnAuthenticationResult> completeAuthentication({
    required Map<String, dynamic> credential,
    String? userId,
  }) => _core.completeWebAuthnAuthentication(
    credential: credential,
    userId: userId,
  );

  Future<List<AuthClientWebAuthnCredential>> list() =>
      _core.getWebAuthnCredentials();

  Future<void> delete({required String credentialId}) =>
      _core.deleteWebAuthnCredential(credentialId: credentialId);

  Future<AuthClientWebAuthnCredential> rename({
    required String credentialId,
    required String name,
  }) => _core.renameWebAuthnCredential(credentialId: credentialId, name: name);
}

final class AuthTwoFactorClientPlugin
    implements AuthClientPlugin<AuthTwoFactorClient> {
  const AuthTwoFactorClientPlugin();

  @override
  String get id => 'two_factor';

  @override
  AuthTwoFactorClient install(AuthClientPluginContext context) =>
      AuthTwoFactorClient(_core(context));
}

final class AuthTwoFactorClient {
  AuthTwoFactorClient(this._core);
  final AuthClientCore _core;

  Future<AuthClientTwoFactorStatus> status() => _core.getTwoFactorStatus();

  Future<AuthClientTwoFactorEnrollment> beginEnrollment({
    String? accountLabel,
  }) => _core.beginTwoFactorEnrollment(accountLabel: accountLabel);

  Future<AuthClientTwoFactorRecoveryCodes> verifyEnrollment({
    required String code,
  }) => _core.verifyTwoFactorEnrollment(code: code);

  Future<void> verify({required String code}) =>
      _core.verifyTwoFactor(code: code);

  Future<AuthSession> verifyChallenge({
    required String challengeToken,
    required String code,
    bool trustDevice = false,
  }) => _core.verifyTwoFactorChallenge(
    challengeToken: challengeToken,
    code: code,
    trustDevice: trustDevice,
  );

  Future<AuthSession> verifyRecoveryChallenge({
    required String challengeToken,
    required String recoveryCode,
  }) => _core.verifyTwoFactorRecoveryChallenge(
    challengeToken: challengeToken,
    recoveryCode: recoveryCode,
  );

  Future<void> revokeTrustedDevices() => _core.revokeTwoFactorTrustedDevices();

  Future<AuthClientTwoFactorStepUp> verifyStepUp({required String code}) =>
      _core.verifyTwoFactorStepUp(code: code);

  Future<void> revokeStepUp() => _core.revokeTwoFactorStepUp();

  Future<void> useRecoveryCode({required String code}) =>
      _core.useTwoFactorRecoveryCode(code: code);

  Future<AuthClientTwoFactorRecoveryCodes> regenerateRecoveryCodes({
    required String code,
  }) => _core.regenerateTwoFactorRecoveryCodes(code: code);

  Future<void> disable({required String code}) =>
      _core.disableTwoFactor(code: code);
}

final class AuthAccountClientPlugin
    implements AuthClientPlugin<AuthAccountClient> {
  const AuthAccountClientPlugin();

  @override
  String get id => 'account';

  @override
  AuthAccountClient install(AuthClientPluginContext context) =>
      AuthAccountClient(_core(context));
}

final class AuthAccountClient {
  AuthAccountClient(this._core);
  final AuthClientCore _core;

  Future<List<AuthAccount>> linked() => _core.getLinkedAccounts();

  Future<void> unlink({
    required String providerId,
    required String providerAccountId,
    required String currentPassword,
  }) => _core.unlinkAccount(
    providerId: providerId,
    providerAccountId: providerAccountId,
    currentPassword: currentPassword,
  );

  Future<void> delete({required String currentPassword}) =>
      _core.deleteAccount(currentPassword: currentPassword);
}

final class AuthPasswordClientPlugin
    implements AuthClientPlugin<AuthPasswordClient> {
  const AuthPasswordClientPlugin();

  @override
  String get id => 'password';

  @override
  AuthPasswordClient install(AuthClientPluginContext context) =>
      AuthPasswordClient(_core(context));
}

final class AuthPasswordClient {
  AuthPasswordClient(this._core);
  final AuthClientCore _core;

  Future<void> change({
    required String identifier,
    required String currentPassword,
    required String newPassword,
  }) => _core.changePassword(
    identifier: identifier,
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  Future<void> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? identifier,
  }) => _core.requestEmailChange(
    newEmail: newEmail,
    currentPassword: currentPassword,
    identifier: identifier,
  );

  Future<AuthUser> confirmEmailChange({required String token}) =>
      _core.confirmEmailChange(token: token);
}

AuthClientCore _core(AuthClientPluginContext context) =>
    AuthClientCore.fromTransport(context.transport);
