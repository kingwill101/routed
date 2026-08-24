import 'client.dart';
import 'models.dart';

/// Adds the provider-discovery API to an [AuthClient].
final class AuthProviderClientPlugin
    implements AuthClientPlugin<AuthProviderClient> {
  /// Creates the provider client plugin.
  const AuthProviderClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'providers';

  /// Installs the provider client backed by [context].
  @override
  AuthProviderClient install(AuthClientPluginContext context) =>
      AuthProviderClient(_core(context));
}

/// Client for discovering providers exposed by the auth server.
final class AuthProviderClient {
  /// Creates a provider client backed by the shared client transport.
  AuthProviderClient(this._core);
  final AuthClientCore _core;

  /// Returns the provider metadata advertised by the server.
  Future<List<AuthClientProvider>> list() => _core.getProviders();
}

/// Adds username-and-password operations to an [AuthClient].
final class AuthCredentialsClientPlugin
    implements AuthClientPlugin<AuthCredentialsClient> {
  /// Creates a credentials plugin for [provider].
  const AuthCredentialsClientPlugin({this.provider = 'credentials'});

  /// Provider identifier used for credential requests.
  final String provider;

  /// Stable registry identifier for this provider-specific plugin.
  @override
  String get id => 'credentials:$provider';

  /// Installs the credentials client backed by [context].
  @override
  AuthCredentialsClient install(AuthClientPluginContext context) =>
      AuthCredentialsClient(_core(context), provider: provider);
}

/// Client for registering and signing in with credentials.
final class AuthCredentialsClient {
  /// Creates a credentials client for [provider].
  AuthCredentialsClient(this._core, {this.provider = 'credentials'});
  final AuthClientCore _core;

  /// Provider identifier used for credential requests.
  final String provider;

  /// Signs in with an email address or username and [password].
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

  /// Registers a user with an email address or username and [password].
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

/// Adds OAuth authorization-code operations to an [AuthClient].
final class AuthOAuthClientPlugin implements AuthClientPlugin<AuthOAuthClient> {
  /// Creates the OAuth client plugin.
  const AuthOAuthClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'oauth';

  /// Installs the OAuth client backed by [context].
  @override
  AuthOAuthClient install(AuthClientPluginContext context) =>
      AuthOAuthClient(_core(context));
}

/// Client for starting and completing OAuth authorization flows.
final class AuthOAuthClient {
  /// Creates an OAuth client backed by the shared client transport.
  AuthOAuthClient(this._core);
  final AuthClientCore _core;

  /// Builds the authorization URI for [provider].
  Future<Uri> begin({required String provider, String? callbackUrl}) =>
      _core.beginOAuth(provider: provider, callbackUrl: callbackUrl);

  /// Completes an OAuth callback using [code] and optional [state].
  Future<AuthClientAuthResult> complete({
    required String provider,
    required String code,
    String? state,
  }) => _core.completeOAuth(provider: provider, code: code, state: state);
}

/// Adds session-management operations to an [AuthClient].
final class AuthSessionClientPlugin
    implements AuthClientPlugin<AuthSessionClient> {
  /// Creates the session client plugin.
  const AuthSessionClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'session';

  /// Installs the session client backed by [context].
  @override
  AuthSessionClient install(AuthClientPluginContext context) =>
      AuthSessionClient(_core(context));
}

/// Client for reading and mutating the current user's sessions.
final class AuthSessionClient {
  /// Creates a session client backed by the shared client transport.
  AuthSessionClient(this._core);
  final AuthClientCore _core;

  /// Returns a CSRF token for state-changing browser requests.
  Future<String> getCsrfToken() => _core.getCsrfToken();

  /// Returns the current session, or `null` when the client is signed out.
  Future<AuthSession?> current() => _core.getSession();

  /// Lists the sessions belonging to the current user.
  Future<List<AuthClientSession>> list() => _core.getSessions();

  /// Revokes the session identified by [sessionId].
  Future<void> revoke(String sessionId) => _core.revokeSession(sessionId);

  /// Revokes all other sessions for the current user.
  Future<int> revokeOthers() => _core.revokeOtherSessions();

  /// Signs out and revokes the current session.
  Future<void> signOut() => _core.signOut();
}

/// Adds anonymous-account operations to an [AuthClient].
final class AuthAnonymousClientPlugin
    implements AuthClientPlugin<AuthAnonymousClient> {
  /// Creates the anonymous-account client plugin.
  const AuthAnonymousClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'anonymous';

  /// Installs the anonymous-account client backed by [context].
  @override
  AuthAnonymousClient install(AuthClientPluginContext context) =>
      AuthAnonymousClient(_core(context));
}

/// Client for creating and deleting anonymous accounts.
final class AuthAnonymousClient {
  /// Creates an anonymous-account client backed by the shared client transport.
  AuthAnonymousClient(this._core);
  final AuthClientCore _core;

  /// Creates an anonymous account and signs it in.
  Future<AuthSession> signIn() => _core.signInAnonymously();

  /// Deletes the current anonymous account.
  Future<void> deleteUser() => _core.deleteAnonymousUser();
}

/// Adds RFC 8628 device-authorization operations to an [AuthClient].
final class AuthDeviceAuthorizationClientPlugin
    implements AuthClientPlugin<AuthDeviceAuthorizationClient> {
  /// Creates the device-authorization client plugin.
  const AuthDeviceAuthorizationClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'device_authorization';

  /// Installs the device-authorization client backed by [context].
  @override
  AuthDeviceAuthorizationClient install(AuthClientPluginContext context) =>
      AuthDeviceAuthorizationClient(_core(context));
}

/// Client for starting, polling, approving, and denying device authorization.
final class AuthDeviceAuthorizationClient {
  /// Creates a device-authorization client backed by the shared client transport.
  AuthDeviceAuthorizationClient(this._core);
  final AuthClientCore _core;

  /// Requests a device code for [clientId] and [scopes].
  Future<AuthClientDeviceAuthorization> authorize({
    required String clientId,
    Iterable<String> scopes = const <String>[],
  }) => _core.requestDeviceAuthorization(clientId: clientId, scopes: scopes);

  /// Polls the token endpoint once for [deviceCode].
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

  /// Approves a pending device authorization using [userCode].
  Future<void> approve({required String userCode}) =>
      _core.approveDeviceAuthorization(userCode: userCode);

  /// Denies a pending device authorization using [userCode].
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

/// Adds API-key management operations to an [AuthClient].
final class AuthApiKeyClientPlugin
    implements AuthClientPlugin<AuthApiKeyClient> {
  /// Creates the API-key client plugin.
  const AuthApiKeyClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'api_key';

  /// Installs the API-key client backed by [context].
  @override
  AuthApiKeyClient install(AuthClientPluginContext context) =>
      AuthApiKeyClient(_core(context));
}

/// Client for issuing and managing API keys for the current user.
final class AuthApiKeyClient {
  /// Creates an API-key client backed by the shared client transport.
  AuthApiKeyClient(this._core);
  final AuthClientCore _core;

  /// Lists the current user's API-key metadata.
  Future<List<AuthClientApiKey>> list() => _core.getApiKeys();

  /// Creates a key with [name], [scopes], and optional [expiresAt].
  Future<AuthClientIssuedApiKey> create({
    required String name,
    Iterable<String> scopes = const <String>[],
    DateTime? expiresAt,
  }) => _core.createApiKey(name: name, scopes: scopes, expiresAt: expiresAt);

  /// Revokes the API key identified by [id].
  Future<void> revoke({required String id}) => _core.revokeApiKey(id: id);

  /// Rotates the API key identified by [id].
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

  /// Exchanges the presented API key for a normal auth session.
  Future<AuthSession> exchangeForSession() => _core.exchangeApiKeyForSession();
}

/// Adds WebAuthn passkey operations to an [AuthClient].
final class AuthWebAuthnClientPlugin
    implements AuthClientPlugin<AuthWebAuthnClient> {
  /// Creates the WebAuthn client plugin.
  const AuthWebAuthnClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'webauthn';

  /// Installs the WebAuthn client backed by [context].
  @override
  AuthWebAuthnClient install(AuthClientPluginContext context) =>
      AuthWebAuthnClient(_core(context));
}

/// Client for registering and authenticating with passkeys.
final class AuthWebAuthnClient {
  /// Creates a WebAuthn client backed by the shared client transport.
  AuthWebAuthnClient(this._core);
  final AuthClientCore _core;

  /// Starts a passkey-registration ceremony.
  Future<AuthClientWebAuthnRegistrationOptions> beginRegistration() =>
      _core.beginWebAuthnRegistration();

  /// Completes passkey registration with the browser [credential].
  Future<AuthClientWebAuthnCredential> completeRegistration({
    required Map<String, dynamic> credential,
    String? name,
  }) => _core.completeWebAuthnRegistration(credential: credential, name: name);

  /// Starts a passkey-authentication ceremony for an optional [userId].
  Future<AuthClientWebAuthnAuthenticationOptions> beginAuthentication({
    String? userId,
  }) => _core.beginWebAuthnAuthentication(userId: userId);

  /// Completes passkey authentication with the browser [credential].
  Future<AuthClientWebAuthnAuthenticationResult> completeAuthentication({
    required Map<String, dynamic> credential,
    String? userId,
  }) => _core.completeWebAuthnAuthentication(
    credential: credential,
    userId: userId,
  );

  /// Lists registered passkeys for the current user.
  Future<List<AuthClientWebAuthnCredential>> list() =>
      _core.getWebAuthnCredentials();

  /// Deletes the passkey identified by [credentialId].
  Future<void> delete({required String credentialId}) =>
      _core.deleteWebAuthnCredential(credentialId: credentialId);

  /// Renames the passkey identified by [credentialId] to [name].
  Future<AuthClientWebAuthnCredential> rename({
    required String credentialId,
    required String name,
  }) => _core.renameWebAuthnCredential(credentialId: credentialId, name: name);
}

/// Adds two-factor authentication operations to an [AuthClient].
final class AuthTwoFactorClientPlugin
    implements AuthClientPlugin<AuthTwoFactorClient> {
  /// Creates the two-factor client plugin.
  const AuthTwoFactorClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'two_factor';

  /// Installs the two-factor client backed by [context].
  @override
  AuthTwoFactorClient install(AuthClientPluginContext context) =>
      AuthTwoFactorClient(_core(context));
}

/// Client for enrolling, verifying, and disabling two-factor authentication.
final class AuthTwoFactorClient {
  /// Creates a two-factor client backed by the shared client transport.
  AuthTwoFactorClient(this._core);
  final AuthClientCore _core;

  /// Returns the current two-factor status.
  Future<AuthClientTwoFactorStatus> status() => _core.getTwoFactorStatus();

  /// Starts enrollment with an optional authenticator [accountLabel].
  Future<AuthClientTwoFactorEnrollment> beginEnrollment({
    String? accountLabel,
  }) => _core.beginTwoFactorEnrollment(accountLabel: accountLabel);

  /// Verifies enrollment with the one-time [code].
  Future<AuthClientTwoFactorRecoveryCodes> verifyEnrollment({
    required String code,
  }) => _core.verifyTwoFactorEnrollment(code: code);

  /// Verifies a normal sign-in two-factor code.
  Future<void> verify({required String code}) =>
      _core.verifyTwoFactor(code: code);

  /// Completes a TOTP challenge and optionally trusts the device.
  Future<AuthSession> verifyChallenge({
    required String challengeToken,
    required String code,
    bool trustDevice = false,
  }) => _core.verifyTwoFactorChallenge(
    challengeToken: challengeToken,
    code: code,
    trustDevice: trustDevice,
  );

  /// Completes a two-factor challenge with a recovery code.
  Future<AuthSession> verifyRecoveryChallenge({
    required String challengeToken,
    required String recoveryCode,
  }) => _core.verifyTwoFactorRecoveryChallenge(
    challengeToken: challengeToken,
    recoveryCode: recoveryCode,
  );

  /// Revokes all trusted two-factor devices.
  Future<void> revokeTrustedDevices() => _core.revokeTwoFactorTrustedDevices();

  /// Performs a recent-authentication step-up with [code].
  Future<AuthClientTwoFactorStepUp> verifyStepUp({required String code}) =>
      _core.verifyTwoFactorStepUp(code: code);

  /// Revokes the current two-factor step-up.
  Future<void> revokeStepUp() => _core.revokeTwoFactorStepUp();

  /// Consumes a two-factor recovery [code].
  Future<void> useRecoveryCode({required String code}) =>
      _core.useTwoFactorRecoveryCode(code: code);

  /// Generates new recovery codes after verifying [code].
  Future<AuthClientTwoFactorRecoveryCodes> regenerateRecoveryCodes({
    required String code,
  }) => _core.regenerateTwoFactorRecoveryCodes(code: code);

  /// Disables two-factor authentication after verifying [code].
  Future<void> disable({required String code}) =>
      _core.disableTwoFactor(code: code);
}

/// Adds linked-account operations to an [AuthClient].
final class AuthAccountClientPlugin
    implements AuthClientPlugin<AuthAccountClient> {
  /// Creates the linked-account client plugin.
  const AuthAccountClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'account';

  /// Installs the linked-account client backed by [context].
  @override
  AuthAccountClient install(AuthClientPluginContext context) =>
      AuthAccountClient(_core(context));
}

/// Client for viewing, unlinking, and deleting linked provider accounts.
final class AuthAccountClient {
  /// Creates a linked-account client backed by the shared client transport.
  AuthAccountClient(this._core);
  final AuthClientCore _core;

  /// Lists the provider accounts linked to the current user.
  Future<List<AuthAccount>> linked() => _core.getLinkedAccounts();

  /// Unlinks a provider account.
  Future<void> unlink({
    required String providerId,
    required String providerAccountId,
    String? currentPassword,
  }) => _core.unlinkAccount(
    providerId: providerId,
    providerAccountId: providerAccountId,
    currentPassword: currentPassword,
  );

  /// Deletes the current account after verifying [currentPassword].
  Future<void> delete({required String currentPassword}) =>
      _core.deleteAccount(currentPassword: currentPassword);
}

/// Adds password-management operations to an [AuthClient].
final class AuthPasswordClientPlugin
    implements AuthClientPlugin<AuthPasswordClient> {
  /// Creates the password client plugin.
  const AuthPasswordClientPlugin();

  /// Stable registry identifier for this plugin.
  @override
  String get id => 'password';

  /// Installs the password client backed by [context].
  @override
  AuthPasswordClient install(AuthClientPluginContext context) =>
      AuthPasswordClient(_core(context));
}

/// Client for changing passwords and confirming email changes.
final class AuthPasswordClient {
  /// Creates a password client backed by the shared client transport.
  AuthPasswordClient(this._core);
  final AuthClientCore _core;

  /// Changes the password for [identifier].
  Future<void> change({
    required String identifier,
    required String currentPassword,
    required String newPassword,
  }) => _core.changePassword(
    identifier: identifier,
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  /// Re-authenticates the current user with [currentPassword].
  Future<void> reauthenticate({
    String? identifier,
    required String currentPassword,
  }) => _core.reauthenticate(
    identifier: identifier,
    currentPassword: currentPassword,
  );

  /// Requests a change to [newEmail].
  Future<void> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? identifier,
  }) => _core.requestEmailChange(
    newEmail: newEmail,
    currentPassword: currentPassword,
    identifier: identifier,
  );

  /// Confirms a pending email change using [token].
  Future<AuthUser> confirmEmailChange({required String token}) =>
      _core.confirmEmailChange(token: token);
}

AuthClientCore _core(AuthClientPluginContext context) =>
    AuthClientCore.fromTransport(context.transport);
