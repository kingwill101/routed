import 'dart:async';

import 'package:http/http.dart' as http;

import 'authentication_methods.dart';
import 'email_auth_backend.dart';
import 'exceptions.dart' show AuthFlowException;
import 'jwt.dart' show JwtOptions, JwtVerifier;
import 'models.dart';
import 'oauth.dart';
import 'oauth_challenge_store.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'store.dart';
import 'tokens.dart'
    show
        constantTimeStringEquals,
        hashOpaqueToken,
        pkceS256CodeChallenge,
        secureRandomToken;
import 'users.dart'
    show
        authUsersDiffer,
        mergeAuthUser,
        normalizeAuthEmail,
        resolveAuthAccountId;
import 'verification_token_store.dart';

/// Framework-specific auth callback context.
typedef AuthContext = dynamic;

/// {@template server_auth_provider_overview}
/// Base metadata for a server auth provider.
///
/// Providers describe the authentication mechanism and the identifiers exposed
/// by `AuthRoutes` at `/auth/providers`.
/// {@endtemplate}
///
/// {@template server_auth_oauth_provider}
/// OAuth 2.0 provider configuration.
///
/// ## Required fields
/// - `id` and `name` are visible to clients.
/// - `authorizationEndpoint` and `tokenEndpoint` power the OAuth handshake.
/// - `profile` maps provider-specific profile data into an `AuthUser`.
///
/// ## Typed profiles
/// - `profileParser` converts a raw profile map into a typed profile.
/// - `profileSerializer` converts the typed profile back into a map for
///   metadata storage.
///
/// ## Optional hooks
/// - `onStateGenerated` lets you persist extra state tied to the OAuth flow.
/// - `onProfile` lets you override the mapped user.
/// - `profileRequest` can enrich the profile (for example, extra API calls).
/// {@endtemplate}
///
/// {@template server_auth_credentials_provider}
/// Credentials provider configuration.
///
/// Provide `authorize` to validate username/email/password input. When omitted,
/// the configured password credential record store and [PasswordHasher] are
/// used.
///
/// Provide `register` to create new users. When omitted, the
/// configured password credential record store and [PasswordHasher] are used.
/// {@endtemplate}

/// Supported provider kinds.
///
/// - [oauth] - Standard OAuth 2.0 authorization code flow.
/// - [oidc] - OpenID Connect (extends OAuth 2.0 with identity layer).
/// - [email] - Magic link / passwordless email authentication.
/// - [credentials] - Username/password or custom credential authentication.
/// - [webauthn] - Passkeys, biometric, and hardware key authentication.
enum AuthProviderType {
  /// Standard OAuth 2.0 authorization code flow.
  oauth,

  /// OpenID Connect (extends OAuth 2.0 with identity layer).
  oidc,

  /// Magic link / passwordless email authentication.
  email,

  /// Username/password or custom credential authentication.
  credentials,

  /// Passkeys, biometric, and hardware key authentication.
  webauthn,
}

/// Maps a provider profile payload to an `AuthUser`.
typedef AuthProfileMapper<TProfile extends Object> =
    AuthUser Function(TProfile profile);

/// Parses a raw OAuth profile payload into a typed profile.
typedef OAuthProfileParser<TProfile extends Object> =
    TProfile Function(Map<String, dynamic> profile);

/// Serializes a typed profile into a JSON-friendly map.
typedef OAuthProfileSerializer<TProfile extends Object> =
    Map<String, dynamic> Function(TProfile profile);

/// Called after OAuth state is generated.
typedef OAuthStateCallback<TProfile extends Object> =
    FutureOr<void> Function(
      AuthContext context,
      OAuthProvider<TProfile> provider,
      String state,
    );

/// Called after the OAuth profile is loaded.
typedef OAuthProfileCallback<TProfile extends Object> =
    FutureOr<AuthUser?> Function(
      AuthContext context,
      OAuthProvider<TProfile> provider,
      TProfile profile,
    );

/// Called to enrich or replace the OAuth profile data.
typedef OAuthProfileRequest<TProfile extends Object> =
    FutureOr<TProfile> Function(
      AuthContext context,
      OAuthProvider<TProfile> provider,
      OAuthTokenResponse token,
      http.Client httpClient,
      TProfile profile,
    );

/// Custom userinfo request callback for providers that require non-standard
/// userinfo fetching (e.g., POST instead of GET, custom headers, etc.).
///
/// Returns the raw profile data as a map. This is called instead of the
/// default GET request to `userInfoEndpoint` when provided.
typedef OAuthUserInfoRequest =
    FutureOr<Map<String, dynamic>> Function(
      OAuthTokenResponse token,
      http.Client httpClient,
      Uri endpoint,
    );

/// Portable provider surface used by magic-link route decisions and helpers.
///
/// Concrete implementations are server plugins. The interface exists only so
/// framework-neutral helpers do not depend on one host's context type.
abstract interface class AuthMagicLinkProvider implements AuthProvider {
  Duration get tokenExpiry;
  String Function()? get tokenGenerator;

  FutureOr<void> sendVerification(
    AuthContext context,
    AuthEmailRequest request,
  );
}

/// Authorizes credential-based sign-in.
typedef CredentialsAuthorize =
    FutureOr<AuthUser?> Function(
      AuthContext context,
      CredentialsProvider provider,
      AuthCredentials credentials,
    );

/// Registers a new user from credential input.
typedef CredentialsRegister =
    FutureOr<AuthUser?> Function(
      AuthContext context,
      CredentialsProvider provider,
      AuthCredentials credentials,
    );

/// Resolves credential sign-in via provider callback or password records.
Future<AuthUser?> authorizeCredentialsSignIn({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required CredentialsProvider provider,
  required AuthContext context,
  required AuthCredentials credentials,
  PasswordPolicy passwordPolicy = const PasswordPolicy(),
}) async {
  if (provider.authorize != null) {
    final user = await Future.sync(
      () => provider.authorize!(context, provider, credentials),
    );
    return _usableAuthUser(user);
  }
  final identifier = _credentialIdentifier(credentials);
  final password = credentials.password;
  if (identifier == null ||
      password == null ||
      password.isEmpty ||
      !passwordPolicy.allowsAuthentication(password)) {
    return null;
  }
  final credential = await Future.sync(
    () => store.credentials.findByIdentifier(identifier),
  );
  if (credential == null || !credential.enabled) {
    return null;
  }
  final verification = passwordHasher.verify(password, credential.passwordHash);
  if (!verification.matches) {
    return null;
  }
  if (verification.needsRehash) {
    await Future.sync(
      () => store.credentials.update(
        credential.copyWith(
          passwordHash: passwordHasher.hash(password),
          updatedAt: DateTime.now().toUtc(),
        ),
      ),
    );
  }
  final user = await Future.sync(() => store.users.findById(credential.userId));
  return _usableAuthUser(user);
}

/// Resolves credential sign-in and throws [AuthFlowException] when rejected.
Future<AuthUser> requireAuthorizedCredentialsSignIn({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required CredentialsProvider provider,
  required AuthContext context,
  required AuthCredentials credentials,
  PasswordPolicy passwordPolicy = const PasswordPolicy(),
  String invalidCode = 'invalid_credentials',
}) async {
  final user = await authorizeCredentialsSignIn(
    store: store,
    passwordHasher: passwordHasher,
    provider: provider,
    context: context,
    credentials: credentials,
    passwordPolicy: passwordPolicy,
  );
  if (user == null) {
    throw AuthFlowException(invalidCode);
  }
  return user;
}

/// Resolves credential registration via provider callback or password records.
Future<AuthUser?> authorizeCredentialsRegistration({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required CredentialsProvider provider,
  required AuthContext context,
  required AuthCredentials credentials,
  PasswordPolicy passwordPolicy = const PasswordPolicy(),
}) async {
  if (provider.register != null) {
    final user = await Future.sync(
      () => provider.register!(context, provider, credentials),
    );
    return _usableAuthUser(user);
  }
  final identifier = _credentialIdentifier(credentials);
  final password = credentials.password;
  if (identifier == null ||
      password == null ||
      passwordPolicy.validateRegistration(password) != null) {
    return null;
  }
  final now = DateTime.now().toUtc();
  final normalizedEmail = credentials.email == null
      ? null
      : normalizeAuthEmail(credentials.email!);
  final user = AuthUser(
    id: secureRandomToken(length: 16),
    email: normalizedEmail == null || normalizedEmail.isEmpty
        ? null
        : normalizedEmail,
    name: credentials.username?.trim() ?? normalizedEmail,
  );
  final credential = AuthPasswordCredential(
    id: secureRandomToken(length: 16),
    userId: user.id,
    identifier: identifier,
    passwordHash: passwordHasher.hash(password),
    createdAt: now,
    updatedAt: now,
  );
  return Future.sync(() => store.credentials.register(user, credential));
}

/// Resolves credential registration and throws [AuthFlowException] when
/// registration fails.
Future<AuthUser> requireAuthorizedCredentialsRegistration({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required CredentialsProvider provider,
  required AuthContext context,
  required AuthCredentials credentials,
  PasswordPolicy passwordPolicy = const PasswordPolicy(),
  String invalidCode = 'registration_failed',
}) async {
  final user = await authorizeCredentialsRegistration(
    store: store,
    passwordHasher: passwordHasher,
    provider: provider,
    context: context,
    credentials: credentials,
    passwordPolicy: passwordPolicy,
  );
  if (user == null) {
    throw AuthFlowException(invalidCode);
  }
  return user;
}

String? _credentialIdentifier(AuthCredentials credentials) {
  final email = credentials.email;
  final username = credentials.username;
  final identifier = email == null || normalizeAuthEmail(email).isEmpty
      ? username
      : normalizeAuthEmail(email);
  final normalized = identifier?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

AuthUser? _usableAuthUser(AuthUser? user) {
  if (user == null || user.id.trim().isEmpty) {
    return null;
  }
  return user;
}

/// {@macro server_auth_provider_overview}
class AuthProvider {
  const AuthProvider({
    required this.id,
    required this.name,
    required this.type,
  });

  /// Provider identifier used in callback routes.
  final String id;

  /// Human-readable provider name.
  final String name;

  /// Provider category.
  final AuthProviderType type;

  /// Summary payload used by `/auth/providers`.
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'type': type.name};
  }

  /// Creates a provider metadata projection safe for events and audit logs.
  ///
  /// OAuth client credentials and other provider implementation details are
  /// intentionally not copied into the projection.
  AuthProvider redacted() => AuthProvider(id: id, name: name, type: type);

  /// Builds this provider's authoritative usable-method inventory.
  AuthAuthenticationMethodInventoryContributor? authenticationMethodInventory(
    AuthStore store,
  ) => null;
}

/// Validates the provider identities used by auth routes and persistence.
///
/// Provider IDs are used as route parameters, session/challenge namespaces,
/// and persistence keys. They must therefore be non-empty, already trimmed,
/// and unique within one auth runtime.
void validateAuthProviderConfiguration(Iterable<AuthProvider> providers) {
  final ids = <String>{};
  for (final provider in providers) {
    final id = provider.id;
    if (id.trim().isEmpty || id != id.trim()) {
      throw ArgumentError.value(
        id,
        'providers',
        'provider IDs must be non-empty and trimmed',
      );
    }
    if (!ids.add(id)) {
      throw ArgumentError.value(id, 'providers', 'provider IDs must be unique');
    }
  }
}

/// Resolves an auth provider by [id] from [providers].
AuthProvider? resolveAuthProviderById(
  Iterable<AuthProvider> providers,
  String id,
) {
  final expected = id.trim();
  if (expected.isEmpty) {
    return null;
  }
  for (final provider in providers) {
    if (provider.id == expected) {
      return provider;
    }
  }
  return null;
}

/// Resolves an auth provider by optional [id], returning `null` when absent.
AuthProvider? resolveAuthProviderByOptionalId(
  Iterable<AuthProvider> providers,
  String? id,
) {
  if (id == null) {
    return null;
  }
  return resolveAuthProviderById(providers, id);
}

/// Builds JSON-friendly provider summaries for `/auth/providers` responses.
List<Map<String, dynamic>> authProviderSummaries(
  Iterable<AuthProvider> providers,
) {
  return providers.map((provider) => provider.toJson()).toList(growable: false);
}

/// Merges [additional] providers into [base] by unique provider id.
///
/// Existing providers in [base] win collisions.
List<AuthProvider> mergeAuthProvidersById(
  Iterable<AuthProvider> base,
  Iterable<AuthProvider> additional,
) {
  final baseProviders = <AuthProvider>[...base];
  final additionalProviders = <AuthProvider>[...additional];
  validateAuthProviderConfiguration(baseProviders);
  validateAuthProviderConfiguration(additionalProviders);
  final merged = <AuthProvider>[...baseProviders];
  final ids = merged.map((provider) => provider.id).toSet();
  for (final provider in additionalProviders) {
    if (!ids.contains(provider.id)) {
      merged.add(provider);
      ids.add(provider.id);
    }
  }
  return merged;
}

/// Session key for provider OAuth state.
String authProviderStateSessionKey(String stateKey, String providerId) {
  return '$stateKey.$providerId';
}

/// Session key for provider PKCE verifier.
String authProviderPkceSessionKey(String pkceKey, String providerId) {
  return '$pkceKey.$providerId';
}

/// Session key for the OIDC nonce associated with a provider flow.
String authProviderNonceSessionKey(String nonceKey, String providerId) {
  return '$nonceKey.$providerId';
}

/// Session key for provider callback URL.
String authProviderCallbackSessionKey(String callbackKey, String providerId) {
  return '$callbackKey.$providerId';
}

/// Session key for email callback URL.
String authEmailCallbackSessionKey(String callbackKey) {
  return '$callbackKey.email';
}

/// OAuth callback session values loaded for a provider.
class AuthOAuthCallbackSessionValues {
  const AuthOAuthCallbackSessionValues({
    required this.expectedState,
    required this.codeVerifier,
    required this.nonce,
    required this.callbackUrl,
  });

  final String? expectedState;
  final String? codeVerifier;
  final String? nonce;
  final String? callbackUrl;
}

/// Loads OAuth callback state/verifier/callback URL values from session.
AuthOAuthCallbackSessionValues resolveOAuthCallbackSessionValues({
  required String providerId,
  required String stateKey,
  required String pkceKey,
  String nonceKey = '_auth.nonce',
  required String callbackKey,
  required String? Function(String key) readSession,
}) {
  return AuthOAuthCallbackSessionValues(
    expectedState: readSession(
      authProviderStateSessionKey(stateKey, providerId),
    ),
    codeVerifier: readSession(authProviderPkceSessionKey(pkceKey, providerId)),
    nonce: readSession(authProviderNonceSessionKey(nonceKey, providerId)),
    callbackUrl: readSession(
      authProviderCallbackSessionKey(callbackKey, providerId),
    ),
  );
}

/// Ensures OAuth callback [receivedState] matches [expectedState].
///
/// Throws [AuthFlowException] with `invalid_state` when validation fails.
void ensureOAuthStateMatches({
  required String? expectedState,
  required String? receivedState,
}) {
  if (expectedState == null ||
      receivedState == null ||
      !constantTimeStringEquals(expectedState, receivedState)) {
    throw AuthFlowException('invalid_state');
  }
}

const Set<String> _oauthAuthorizationReservedParameters = <String>{
  'response_type',
  'client_id',
  'redirect_uri',
  'state',
  'nonce',
  'scope',
  'code_challenge',
  'code_challenge_method',
  'callbackUrl',
};

const Set<String> _oauthTokenReservedParameters = <String>{
  'grant_type',
  'code',
  'redirect_uri',
  'scope',
  'code_verifier',
  'client_id',
  'client_secret',
  'refresh_token',
};

/// Builds OAuth authorization query parameters for [provider].
Map<String, String> buildOAuthAuthorizationParameters<TProfile extends Object>(
  OAuthProvider<TProfile> provider, {
  required String state,
  String? codeChallenge,
  String? nonce,
  String? callbackUrl,
}) {
  final codeChallengeMethod = codeChallenge == null ? null : 'S256';
  final params = <String, String>{
    for (final entry in provider.authorizationParams.entries)
      if (!_oauthAuthorizationReservedParameters.contains(entry.key))
        entry.key: entry.value,
    'response_type': 'code',
    'client_id': provider.clientId,
    'redirect_uri': provider.redirectUri,
    'state': state,
    'nonce': ?nonce,
    if (provider.scopes.isNotEmpty) 'scope': provider.scopes.join(' '),
    'code_challenge': ?codeChallenge,
    'code_challenge_method': ?codeChallengeMethod,
  };
  if (callbackUrl != null && callbackUrl.isNotEmpty) {
    params['callbackUrl'] = callbackUrl;
  }
  return params;
}

/// Prepared OAuth authorization start payload.
class AuthOAuthAuthorizationStart {
  const AuthOAuthAuthorizationStart({
    required this.state,
    this.nonce,
    this.codeVerifier,
    this.codeChallenge,
    required this.parameters,
  });

  final String state;
  final String? nonce;
  final String? codeVerifier;
  final String? codeChallenge;
  final Map<String, String> parameters;
}

/// Result of preparing OAuth authorization and persisted session values.
class AuthOAuthAuthorizationResolution {
  const AuthOAuthAuthorizationResolution({
    required this.state,
    this.nonce,
    this.codeVerifier,
    this.codeChallenge,
    required this.parameters,
    required this.authorizationUri,
  });

  final String state;
  final String? nonce;
  final String? codeVerifier;
  final String? codeChallenge;
  final Map<String, String> parameters;
  final Uri authorizationUri;
}

/// Prepares OAuth state, PKCE values, and authorization parameters.
AuthOAuthAuthorizationStart prepareOAuthAuthorizationStart<
  TProfile extends Object
>(OAuthProvider<TProfile> provider, {String? callbackUrl}) {
  final state = secureRandomToken();
  final nonce = provider.type == AuthProviderType.oidc
      ? secureRandomToken()
      : null;
  String? verifier;
  String? challenge;
  if (provider.usePkce) {
    verifier = secureRandomToken(length: 48);
    challenge = pkceS256CodeChallenge(verifier);
  }

  return AuthOAuthAuthorizationStart(
    state: state,
    nonce: nonce,
    codeVerifier: verifier,
    codeChallenge: challenge,
    parameters: buildOAuthAuthorizationParameters(
      provider,
      state: state,
      codeChallenge: challenge,
      nonce: nonce,
      callbackUrl: callbackUrl,
    ),
  );
}

/// Prepares and persists OAuth authorization state for framework adapters.
///
/// When [challengeStore] is provided, state, PKCE, nonce, and callback values
/// are kept in the typed one-time challenge store. Otherwise the legacy
/// session callbacks are used for adapters that have not adopted that store.
Future<AuthOAuthAuthorizationResolution>
resolveOAuthAuthorizationStart<TContext, TProfile extends Object>({
  required TContext context,
  required OAuthProvider<TProfile> provider,
  required String stateKey,
  required String pkceKey,
  String nonceKey = '_auth.nonce',
  required String callbackKey,
  required void Function(String key, String value) writeSession,
  AuthOAuthChallengeStore? challengeStore,
  Duration challengeTtl = const Duration(minutes: 10),
  String? callbackUrl,
}) async {
  if (challengeStore != null && challengeTtl <= Duration.zero) {
    throw ArgumentError.value(challengeTtl, 'challengeTtl');
  }
  final start = prepareOAuthAuthorizationStart(
    provider,
    callbackUrl: callbackUrl,
  );

  // Keep a browser-bound copy in the framework session even when the
  // one-time challenge is persisted durably. The durable store owns replay
  // protection and the PKCE material; the session copy makes the binding
  // resilient when a host/browser drops the auxiliary state cookie during a
  // cross-site redirect.
  writeSession(
    authProviderStateSessionKey(stateKey, provider.id),
    start.state,
  );

  if (provider.onStateGenerated != null) {
    await Future.sync(
      () => provider.onStateGenerated!(context, provider, start.state),
    );
  }

  if (challengeStore != null) {
    await Future.sync(
      () => challengeStore.save(
        AuthOAuthChallenge(
          providerId: provider.id,
          state: start.state,
          codeVerifier: start.codeVerifier,
          nonce: start.nonce,
          callbackUrl: callbackUrl,
          expiresAt: DateTime.now().toUtc().add(challengeTtl),
        ),
      ),
    );
  } else {
    if (start.codeVerifier != null) {
      writeSession(
        authProviderPkceSessionKey(pkceKey, provider.id),
        start.codeVerifier!,
      );
    }

    if (start.nonce != null) {
      writeSession(
        authProviderNonceSessionKey(nonceKey, provider.id),
        start.nonce!,
      );
    }

    if (callbackUrl != null && callbackUrl.isNotEmpty) {
      writeSession(
        authProviderCallbackSessionKey(callbackKey, provider.id),
        callbackUrl,
      );
    }
  }

  return AuthOAuthAuthorizationResolution(
    state: start.state,
    nonce: start.nonce,
    codeVerifier: start.codeVerifier,
    codeChallenge: start.codeChallenge,
    parameters: start.parameters,
    authorizationUri: provider.authorizationEndpoint.replace(
      queryParameters: start.parameters,
    ),
  );
}

/// Builds an [OAuth2Client] from provider metadata.
OAuth2Client oauthClientForProvider<TProfile extends Object>(
  OAuthProvider<TProfile> provider, {
  http.Client? httpClient,
}) {
  return OAuth2Client(
    tokenEndpoint: provider.tokenEndpoint,
    clientId: provider.clientId,
    clientSecret: provider.clientSecret,
    httpClient: httpClient,
    useBasicAuth: provider.useBasicAuth,
    requestTimeout: provider.requestTimeout,
  );
}

/// Exchanges an authorization code for provider tokens.
Future<OAuthTokenResponse>
exchangeOAuthAuthorizationCode<TProfile extends Object>(
  OAuthProvider<TProfile> provider, {
  required String code,
  String? codeVerifier,
  http.Client? httpClient,
}) {
  final scope = provider.scopes.isEmpty ? null : provider.scopes.join(' ');
  return oauthClientForProvider(
    provider,
    httpClient: httpClient,
  ).exchangeAuthorizationCode(
    code: code,
    redirectUri: Uri.parse(provider.redirectUri),
    codeVerifier: codeVerifier,
    scope: scope,
    additionalParameters: provider.tokenParams.isEmpty
        ? null
        : <String, String>{
            for (final entry in provider.tokenParams.entries)
              if (!_oauthTokenReservedParameters.contains(entry.key))
                entry.key: entry.value,
          },
  );
}

/// Builds an [AuthAccount] from OAuth token/profile payloads.
AuthAccount buildOAuthAuthAccount({
  required String providerId,
  required String providerAccountId,
  required String userId,
  required OAuthTokenResponse token,
  required Map<String, dynamic> metadata,
  DateTime? expiresAt,
}) {
  final account = AuthAccount(
    providerId: providerId,
    providerAccountId: providerAccountId,
    userId: userId,
    accessToken: token.accessToken,
    refreshToken: token.refreshToken,
    expiresAt: expiresAt,
    metadata: metadata,
  );
  validateAuthAccountForLink(account);
  return account;
}

/// Consumes an email verification token from the configured typed store.
Future<AuthVerificationToken?> consumeAuthVerificationToken({
  required AuthStore store,
  AuthVerificationTokenStore? tokenStore,
  required String identifier,
  required String token,
}) async {
  final tokens = tokenStore ?? store.verificationTokens;
  return Future.sync(() => tokens.consume(identifier, token));
}

/// Deletes existing verification tokens from the configured typed store.
Future<void> clearAuthVerificationTokens({
  required AuthStore store,
  AuthVerificationTokenStore? tokenStore,
  required String identifier,
}) async {
  final tokens = tokenStore ?? store.verificationTokens;
  await Future.sync(() => tokens.delete(identifier));
}

/// Persists a verification token in the configured typed store.
Future<void> persistAuthVerificationToken({
  required AuthStore store,
  AuthVerificationTokenStore? tokenStore,
  required AuthVerificationToken verification,
}) async {
  final tokens = tokenStore ?? store.verificationTokens;
  await Future.sync(() => tokens.save(verification));
}

/// Prepared payload for email verification sign-in flows.
class AuthEmailVerificationPayload {
  const AuthEmailVerificationPayload({
    required this.token,
    required this.expiresAt,
    required this.record,
    required this.request,
    required this.pendingResult,
  });

  final String token;
  final DateTime expiresAt;
  final AuthMagicLinkRecord record;
  final AuthEmailRequest request;
  final AuthResult pendingResult;
}

/// Prepares token, request, and pending session payloads for email sign-in.
AuthEmailVerificationPayload prepareAuthEmailVerificationPayload({
  required AuthMagicLinkProvider provider,
  required String email,
  required String callbackUrl,
  required AuthSessionStrategy sessionStrategy,
  String Function()? generateToken,
  DateTime? now,
}) {
  final normalizedEmail = normalizeAuthOneTimeEmail(email);
  final tokenGenerator = provider.tokenGenerator ?? generateToken;
  final token = tokenGenerator?.call() ?? secureRandomToken();
  if (token.trim().isEmpty) {
    throw ArgumentError.value(
      token,
      'token',
      'must be non-empty when generated for email verification',
    );
  }
  final current = now ?? DateTime.now();
  final expiresAt = current.add(provider.tokenExpiry);
  final request = AuthEmailRequest(
    email: normalizedEmail,
    token: token,
    callbackUrl: callbackUrl,
    expiresAt: expiresAt,
  );
  final session = AuthSession(
    user: AuthUser(id: '', email: normalizedEmail),
    expiresAt: expiresAt,
    strategy: sessionStrategy,
  );
  return AuthEmailVerificationPayload(
    token: token,
    expiresAt: expiresAt,
    record: AuthMagicLinkRecord(
      providerId: provider.id,
      email: normalizedEmail,
      tokenHash: hashOpaqueToken(token),
      issuedAt: current,
      expiresAt: expiresAt,
    ),
    request: request,
    pendingResult: AuthResult(user: session.user, session: session),
  );
}

/// Result of resolving an email sign-in user.
class AuthEmailUserResolution {
  const AuthEmailUserResolution({required this.user, required this.isNewUser});

  final AuthUser user;
  final bool isNewUser;
}

/// Loads an existing user by [email] or creates a new record.
Future<AuthEmailUserResolution> resolveAuthUserByEmailOrCreate({
  required AuthStore store,
  required String email,
}) async {
  final normalizedEmail = normalizeAuthOneTimeEmail(email);
  final result = await Future.sync(
    () => store.users.createOrFindByEmail(
      AuthUser(id: normalizedEmail, email: normalizedEmail),
    ),
  );
  if (result.user.id.trim().isEmpty) {
    throw AuthFlowException('user_resolution_failed');
  }
  return AuthEmailUserResolution(user: result.user, isNewUser: result.created);
}

/// Starts an email verification sign-in flow and dispatches the provider
/// verification request.
Future<AuthEmailVerificationPayload> startAuthEmailSignIn<TContext>({
  required AuthMagicLinkBackend backend,
  required AuthMagicLinkProvider provider,
  required TContext context,
  required String email,
  required String callbackUrl,
  required AuthSessionStrategy sessionStrategy,
  String Function()? generateToken,
  void Function(String key, String value)? writeSession,
  String? callbackKey,
  DateTime? now,
}) async {
  final normalizedEmail = normalizeAuthOneTimeEmail(email);
  final payload = prepareAuthEmailVerificationPayload(
    provider: provider,
    email: normalizedEmail,
    callbackUrl: callbackUrl,
    sessionStrategy: sessionStrategy,
    generateToken: generateToken,
    now: now,
  );

  if (writeSession != null && callbackKey != null && callbackUrl.isNotEmpty) {
    writeSession(authEmailCallbackSessionKey(callbackKey), callbackUrl);
  }

  await Future.sync(
    () => backend.issueMagicLink(AuthMagicLinkIssueCommand(payload.record)),
  );
  await Future.sync(() => provider.sendVerification(context, payload.request));

  return payload;
}

/// Result of resolving an email verification callback into sign-in payloads.
class AuthEmailVerificationSignInResolution {
  const AuthEmailVerificationSignInResolution({
    required this.user,
    required this.isNewUser,
    required this.callbackUrl,
  });

  final AuthUser user;
  final bool isNewUser;
  final String? callbackUrl;
}

/// Resolves an email verification callback token into sign-in user data.
///
/// Returns `null` when the token cannot be consumed.
Future<AuthEmailVerificationSignInResolution?>
resolveAuthEmailVerificationSignIn({
  required AuthMagicLinkBackend backend,
  required String providerId,
  required String email,
  required String token,
  String Function()? generateUserId,
  DateTime? now,
  String? callbackKey,
  String? Function(String key)? readSession,

  /// A browser-bound copy of the verification token, supplied by the
  /// framework adapter (for example from an HttpOnly state cookie).
  String? expectedBrowserToken,

  /// Requires the adapter to provide a browser-bound token before consuming
  /// the one-time verification token.
  bool requireBrowserToken = false,
}) async {
  final normalizedEmail = normalizeAuthOneTimeEmail(email);
  if (token.trim().isEmpty || token.length > 4096) return null;
  if (requireBrowserToken &&
      (expectedBrowserToken == null ||
          !constantTimeStringEquals(expectedBrowserToken, token))) {
    return null;
  }
  final consumed = await Future.sync(
    () => backend.consumeMagicLink(
      AuthMagicLinkConsumeCommand(
        providerId: providerId,
        email: normalizedEmail,
        tokenHash: hashOpaqueToken(token),
        now: now ?? DateTime.now(),
        candidate: AuthUser(
          id: generateUserId?.call() ?? secureRandomToken(length: 24),
          email: normalizedEmail,
        ),
      ),
    ),
  );
  if (consumed.status != AuthMagicLinkConsumeStatus.consumed ||
      consumed.user == null) {
    return null;
  }
  final callbackUrl = callbackKey == null || readSession == null
      ? null
      : readSession(authEmailCallbackSessionKey(callbackKey));

  return AuthEmailVerificationSignInResolution(
    user: consumed.user!,
    isNewUser: consumed.created,
    callbackUrl: callbackUrl,
  );
}

/// Loads a provider profile from userinfo or an ID token payload.
Future<Map<String, dynamic>> loadOAuthProfile<TProfile extends Object>(
  OAuthProvider<TProfile> provider, {
  required OAuthTokenResponse token,
  required http.Client httpClient,
  String? oidcNonce,
}) async {
  if (provider.userInfoEndpoint == null) {
    final idToken = token.raw['id_token']?.toString();
    if (provider.type == AuthProviderType.oidc &&
        (idToken == null || idToken.isEmpty)) {
      throw AuthFlowException('oidc_id_token_missing');
    }
    if (idToken != null && idToken.isNotEmpty) {
      final issuer = provider.oidcIssuer;
      final jwksUri = provider.oidcJwksUri;
      if (issuer == null || jwksUri == null) {
        throw AuthFlowException('oidc_validation_unconfigured');
      }
      try {
        final payload = await JwtVerifier(
          options: JwtOptions(
            issuer: issuer.toString(),
            audience: [provider.clientId],
            requiredClaims: const ['sub', 'iss', 'aud', 'exp'],
            jwksUri: jwksUri,
            algorithms: provider.oidcAlgorithms,
          ),
          httpClient: httpClient,
        ).verifyToken(idToken);
        if (oidcNonce == null || payload.claims['nonce'] != oidcNonce) {
          throw AuthFlowException('oidc_nonce_mismatch');
        }
        return payload.claims;
      } on AuthFlowException {
        rethrow;
      } catch (_) {
        throw AuthFlowException('id_token_invalid');
      }
    }
    return <String, dynamic>{};
  }

  if (provider.userInfoRequest != null) {
    try {
      return await Future.sync(
        () => provider.userInfoRequest!(
          token,
          httpClient,
          provider.userInfoEndpoint!,
        ),
      ).timeout(provider.requestTimeout);
    } catch (_) {
      throw AuthFlowException('userinfo_failed');
    }
  }

  try {
    return await oauthClientForProvider(
      provider,
      httpClient: httpClient,
    ).fetchUserInfo(provider.userInfoEndpoint!, token.accessToken);
  } catch (_) {
    throw AuthFlowException('userinfo_failed');
  }
}

/// Result of resolving an OAuth-mapped user against persisted identities.
class AuthOAuthUserResolution {
  const AuthOAuthUserResolution({
    required this.user,
    required this.isNewUser,
    required this.userUpdated,
  });

  final AuthUser user;
  final bool isNewUser;
  final bool userUpdated;
}

/// Result of resolving provider OAuth callback data into auth sign-in payloads.
class AuthOAuthSignInResolution {
  const AuthOAuthSignInResolution({
    required this.user,
    required this.isNewUser,
    required this.userUpdated,
    required this.account,
    required this.profile,
  });

  final AuthUser user;
  final bool isNewUser;
  final bool userUpdated;
  final AuthAccount account;
  final Map<String, dynamic> profile;
}

/// Result of resolving an OAuth callback into sign-in payloads and callback
/// redirect metadata.
class AuthOAuthCallbackSignInResolution {
  const AuthOAuthCallbackSignInResolution({
    required this.signIn,
    required this.callbackUrl,
  });

  final AuthOAuthSignInResolution signIn;
  final String? callbackUrl;
}

/// Atomically links an OAuth account and rejects a canonical link owned by a
/// different user.
Future<AuthAccount> linkOAuthAccountOrThrow({
  required AuthStore store,
  required AuthAccount account,
}) async {
  validateAuthAccountForLink(account);
  final linkedAccount = await Future.sync(() => store.accounts.link(account));
  if (linkedAccount.providerId != account.providerId ||
      linkedAccount.providerAccountId != account.providerAccountId ||
      linkedAccount.userId != account.userId) {
    throw AuthFlowException('account_link_conflict');
  }
  return linkedAccount;
}

/// Resolves OAuth-mapped users against existing account/email records.
///
/// [emailVerified] indicates whether the provider asserted ownership of the
/// profile email address (e.g. Discord's `verified` / Google's
/// `email_verified`). Email-based linking is only attempted when it is true,
/// so an unverified provider email can never take over a local account.
Future<AuthOAuthUserResolution> resolveOAuthUserForAccount({
  required AuthStore store,
  required String providerId,
  required String accountId,
  required AuthUser mappedUser,
  bool emailVerified = false,
}) async {
  final normalizedProviderId = providerId.trim();
  final normalizedAccountId = accountId.trim();
  if (normalizedProviderId.isEmpty) {
    throw ArgumentError.value(providerId, 'providerId', 'must be non-empty');
  }
  if (normalizedAccountId.isEmpty) {
    throw ArgumentError.value(accountId, 'accountId', 'must be non-empty');
  }
  final existingAccount = await Future.sync(
    () => store.accounts.find(normalizedProviderId, normalizedAccountId),
  );

  final normalizedMappedUser = _ensureAuthUserId(
    _normalizeAuthUserEmail(mappedUser),
    normalizedAccountId,
  );
  final trustedMappedUser = emailVerified
      ? normalizedMappedUser
      : _withoutAuthEmail(normalizedMappedUser);
  var resolvedUser = trustedMappedUser;
  var isNewUser = false;
  var userUpdated = false;

  // An existing account link always wins: resolve the user it points to.
  AuthUser? linkedUser;
  if (existingAccount != null && existingAccount.userId != null) {
    linkedUser = await Future.sync(
      () => store.users.findById(existingAccount.userId!),
    );
  }

  if (linkedUser != null) {
    resolvedUser = linkedUser;
  } else if (emailVerified &&
      normalizedMappedUser.email != null &&
      normalizedMappedUser.email!.isNotEmpty) {
    // Email matching is only allowed when the provider verified the address,
    // preventing account takeover via unverified OAuth emails. The store
    // operation is atomic so concurrent callbacks cannot create duplicates.
    final result = await Future.sync(
      () => store.users.createOrFindByEmail(trustedMappedUser),
    );
    resolvedUser = result.user;
    isNewUser = result.created;
  } else {
    // No matching record: persist the mapped user. This runs even when the
    // mapped user carries a non-empty provider ID (Discord, GitHub, ...)
    // so first-time OAuth users are never left unpersisted.
    resolvedUser = await Future.sync(
      () => store.users.create(trustedMappedUser),
    );
    isNewUser = true;
  }

  if (!isNewUser) {
    final mergedUser = mergeAuthUser(resolvedUser, trustedMappedUser);
    if (authUsersDiffer(resolvedUser, mergedUser)) {
      final stored = await Future.sync(() => store.users.update(mergedUser));
      if (stored != null) {
        resolvedUser = stored;
        userUpdated = true;
      }
    }
  }

  if (resolvedUser.id.trim().isEmpty) {
    throw AuthFlowException('user_resolution_failed');
  }

  return AuthOAuthUserResolution(
    user: resolvedUser,
    isNewUser: isNewUser,
    userUpdated: userUpdated,
  );
}

AuthUser _ensureAuthUserId(AuthUser user, String fallbackId) {
  if (user.id.trim().isNotEmpty) {
    return user;
  }
  return AuthUser(
    id: fallbackId,
    email: user.email,
    name: user.name,
    image: user.image,
    roles: user.roles,
    attributes: user.attributes,
  );
}

AuthUser _normalizeAuthUserEmail(AuthUser user) {
  final email = user.email;
  if (email == null) {
    return user;
  }
  final normalized = normalizeAuthEmail(email);
  if (normalized == email) {
    return user;
  }
  return AuthUser(
    id: user.id,
    email: normalized,
    name: user.name,
    image: user.image,
    roles: user.roles,
    attributes: user.attributes,
  );
}

AuthUser _withoutAuthEmail(AuthUser user) {
  if (user.email == null) {
    return user;
  }
  return AuthUser(
    id: user.id,
    name: user.name,
    image: user.image,
    roles: user.roles,
    attributes: user.attributes,
  );
}

/// Resolves OAuth callback payloads into user/account/profile sign-in data.
Future<AuthOAuthSignInResolution>
resolveOAuthSignInForProvider<TContext, TProfile extends Object>({
  required AuthStore store,
  required TContext context,
  required OAuthProvider<TProfile> provider,
  required String code,
  String? codeVerifier,
  String? oidcNonce,
  required http.Client httpClient,
  String Function()? fallbackAccountId,
}) async {
  late OAuthTokenResponse tokenResponse;
  try {
    tokenResponse = await exchangeOAuthAuthorizationCode(
      provider,
      code: code,
      codeVerifier: codeVerifier,
      httpClient: httpClient,
    );
  } catch (_) {
    throw AuthFlowException('token_exchange_failed');
  }

  final rawProfile = await loadOAuthProfile(
    provider,
    token: tokenResponse,
    httpClient: httpClient,
    oidcNonce: oidcNonce,
  );
  late final TProfile enrichedProfile;
  late final AuthUser user;
  late final Map<String, dynamic> profileMap;
  try {
    final parsedProfile = provider.parseProfile(rawProfile);
    enrichedProfile = await Future.sync(
      () => provider.enrichProfile(
        context,
        tokenResponse,
        httpClient,
        parsedProfile,
      ),
    );
    final mappedUser = provider.mapProfile(enrichedProfile);
    final overrideUser = await Future.sync(
      () => provider.overrideProfile(context, enrichedProfile),
    );
    user = overrideUser ?? mappedUser;
    profileMap = provider.serializeProfile(enrichedProfile);
  } on AuthFlowException {
    rethrow;
  } catch (_) {
    throw AuthFlowException('profile_invalid');
  }
  final emailVerified =
      profileMap['verified'] == true || profileMap['email_verified'] == true;
  final accountId = resolveAuthAccountId(
    profileMap,
    user,
    fallbackId: fallbackAccountId ?? secureRandomToken,
    emailVerified: emailVerified,
  );
  final accountExpiresAt = oauthTokenExpiryFromSeconds(tokenResponse.expiresIn);

  final userResolution = await resolveOAuthUserForAccount(
    store: store,
    providerId: provider.id,
    accountId: accountId,
    mappedUser: user,
    // Only link to a local account by email when the provider asserted
    // ownership of the address (Discord `verified`, Google `email_verified`,
    // GitHub `verified`, ...). Unverified profile emails must never take over
    // an existing local user.
    emailVerified: emailVerified,
  );

  final account = buildOAuthAuthAccount(
    providerId: provider.id,
    providerAccountId: accountId,
    userId: userResolution.user.id,
    token: tokenResponse,
    expiresAt: accountExpiresAt,
    metadata: profileMap,
  );
  await linkOAuthAccountOrThrow(store: store, account: account);

  return AuthOAuthSignInResolution(
    user: userResolution.user,
    isNewUser: userResolution.isNewUser,
    userUpdated: userResolution.userUpdated,
    account: account,
    profile: profileMap,
  );
}

/// Resolves a full OAuth callback flow including state validation and account
/// linking.
Future<AuthOAuthCallbackSignInResolution>
resolveOAuthCallbackSignInForProvider<TContext, TProfile extends Object>({
  required AuthStore store,
  required TContext context,
  required OAuthProvider<TProfile> provider,
  required String code,
  required String? receivedState,
  required String stateKey,
  required String pkceKey,
  String nonceKey = '_auth.nonce',
  required String callbackKey,
  required String? Function(String key) readSession,
  void Function(String key)? removeSession,
  FutureOr<AuthOAuthChallenge?> Function(String providerId, String state)?
  consumeChallenge,

  /// A browser-bound copy of the received state, supplied by the framework
  /// adapter (for example from an HttpOnly state cookie).
  String? expectedBrowserState,

  /// Requires the adapter to provide a browser-bound state value. This keeps
  /// a durable challenge store from accepting a callback initiated by another
  /// browser.
  bool requireBrowserState = false,
  required http.Client httpClient,
  String Function()? fallbackAccountId,
}) async {
  if (requireBrowserState) {
    // Reject an unbound callback before consuming the durable challenge. An
    // attacker must not be able to turn a failed login-CSRF attempt into a
    // denial of service for the browser that started the OAuth flow.
    ensureOAuthStateMatches(
      expectedState: expectedBrowserState,
      receivedState: receivedState,
    );
  }

  final AuthOAuthCallbackSessionValues sessionValues;
  if (consumeChallenge != null) {
    final challenge = receivedState == null
        ? null
        : await Future.sync(() => consumeChallenge(provider.id, receivedState));
    if (challenge == null) {
      throw AuthFlowException('invalid_state');
    }
    sessionValues = AuthOAuthCallbackSessionValues(
      expectedState: challenge.state,
      codeVerifier: challenge.codeVerifier,
      nonce: challenge.nonce,
      callbackUrl: challenge.callbackUrl,
    );
    // The durable challenge is the replay guard, but the mirrored framework
    // state should be removed from the browser session once that challenge is
    // consumed as well.
    removeSession?.call(authProviderStateSessionKey(stateKey, provider.id));
  } else {
    sessionValues = resolveOAuthCallbackSessionValues(
      providerId: provider.id,
      stateKey: stateKey,
      pkceKey: pkceKey,
      nonceKey: nonceKey,
      callbackKey: callbackKey,
      readSession: readSession,
    );
    ensureOAuthStateMatches(
      expectedState: sessionValues.expectedState,
      receivedState: receivedState,
    );

    removeSession?.call(authProviderStateSessionKey(stateKey, provider.id));
    removeSession?.call(authProviderPkceSessionKey(pkceKey, provider.id));
    removeSession?.call(authProviderNonceSessionKey(nonceKey, provider.id));
    removeSession?.call(
      authProviderCallbackSessionKey(callbackKey, provider.id),
    );
  }
  ensureOAuthStateMatches(
    expectedState: sessionValues.expectedState,
    receivedState: receivedState,
  );
  final signIn = await resolveOAuthSignInForProvider<TContext, TProfile>(
    store: store,
    context: context,
    provider: provider,
    code: code,
    codeVerifier: sessionValues.codeVerifier,
    oidcNonce: sessionValues.nonce,
    httpClient: httpClient,
    fallbackAccountId: fallbackAccountId,
  );

  return AuthOAuthCallbackSignInResolution(
    signIn: signIn,
    callbackUrl: sessionValues.callbackUrl,
  );
}

/// {@macro server_auth_oauth_provider}
class OAuthProvider<TProfile extends Object> extends AuthProvider {
  OAuthProvider({
    required super.id,
    required super.name,
    required this.clientId,
    required this.clientSecret,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.profile,
    required this.redirectUri,
    super.type = AuthProviderType.oauth,
    this.userInfoEndpoint,
    this.oidcIssuer,
    this.oidcJwksUri,
    this.oidcAlgorithms = const <String>['RS256'],
    this.requestTimeout = const Duration(seconds: 10),
    this.userInfoRequest,
    this.scopes = const <String>[],
    this.authorizationParams = const <String, String>{},
    this.tokenParams = const <String, String>{},
    this.usePkce = true,
    this.useBasicAuth = true,
    this.profileParser,
    this.profileSerializer,
    this.onStateGenerated,
    this.onProfile,
    this.profileRequest,
  }) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be greater than zero',
      );
    }
  }

  /// OAuth client identifier.
  final String clientId;

  /// OAuth client secret.
  final String clientSecret;

  /// Authorization endpoint for the provider.
  final Uri authorizationEndpoint;

  /// Token exchange endpoint for the provider.
  final Uri tokenEndpoint;

  /// Userinfo endpoint (optional if ID token contains claims).
  final Uri? userInfoEndpoint;

  /// Issuer used to validate an OIDC ID token.
  final Uri? oidcIssuer;

  /// JWKS endpoint used to validate an OIDC ID token.
  final Uri? oidcJwksUri;

  /// Signature algorithms accepted for OIDC ID tokens.
  final List<String> oidcAlgorithms;

  /// Timeout applied to provider token and user-info requests.
  final Duration requestTimeout;

  /// Custom userinfo request callback for providers that require non-standard
  /// userinfo fetching (e.g., POST instead of GET).
  ///
  /// When provided alongside `userInfoEndpoint`, this callback is used instead
  /// of the default GET request. This is useful for providers like Dropbox
  /// that require POST requests to their userinfo endpoint.
  final OAuthUserInfoRequest? userInfoRequest;

  /// OAuth scopes to request.
  final List<String> scopes;

  /// Extra authorization parameters appended to the request.
  final Map<String, String> authorizationParams;

  /// Extra token request parameters appended to the exchange.
  final Map<String, String> tokenParams;

  /// Enables PKCE for the authorization code flow.
  final bool usePkce;

  /// Uses HTTP basic auth for the token exchange.
  final bool useBasicAuth;

  /// Converts raw profile payloads to typed profiles.
  final OAuthProfileParser<TProfile>? profileParser;

  /// Converts typed profiles to JSON-friendly maps.
  final OAuthProfileSerializer<TProfile>? profileSerializer;

  /// Maps the provider profile payload into an `AuthUser`.
  final AuthProfileMapper<TProfile> profile;

  /// Redirect URI registered with the provider.
  final String redirectUri;

  /// Optional hook for custom state handling.
  final OAuthStateCallback<TProfile>? onStateGenerated;

  /// Optional hook for profile overrides.
  final OAuthProfileCallback<TProfile>? onProfile;

  /// Optional hook to enrich profile payloads with extra API calls.
  final OAuthProfileRequest<TProfile>? profileRequest;

  /// Parses the raw profile response into the typed profile.
  TProfile parseProfile(Map<String, dynamic> profile) {
    if (profileParser != null) {
      return profileParser!(profile);
    }
    return profile as TProfile;
  }

  /// Serializes the typed profile into a JSON-friendly map.
  Map<String, dynamic> serializeProfile(TProfile profile) {
    if (profileSerializer != null) {
      return profileSerializer!(profile);
    }
    if (profile is Map<String, dynamic>) {
      return profile;
    }
    return <String, dynamic>{};
  }

  /// Maps the typed profile into an `AuthUser`.
  AuthUser mapProfile(TProfile profile) => this.profile(profile);

  /// Runs the optional profile override hook.
  FutureOr<AuthUser?> overrideProfile(AuthContext context, TProfile profile) {
    if (onProfile == null) {
      return null;
    }
    return onProfile!(context, this, profile);
  }

  /// Runs the optional profile enrichment hook.
  FutureOr<TProfile> enrichProfile(
    AuthContext context,
    OAuthTokenResponse token,
    http.Client httpClient,
    TProfile profile,
  ) {
    if (profileRequest == null) {
      return profile;
    }
    return profileRequest!(context, this, token, httpClient, profile);
  }
}

/// {@macro server_auth_credentials_provider}
class CredentialsProvider extends AuthProvider {
  CredentialsProvider({
    super.id = 'credentials',
    super.name = 'Credentials',
    this.authorize,
    this.register,
  }) : super(type: AuthProviderType.credentials);

  /// Custom authorization callback for credentials.
  final CredentialsAuthorize? authorize;

  /// Custom registration callback for credentials.
  final CredentialsRegister? register;

  @override
  AuthAuthenticationMethodInventoryContributor authenticationMethodInventory(
    AuthStore store,
  ) => _PasswordAuthenticationMethodInventory(store, id);
}

final class _PasswordAuthenticationMethodInventory
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  const _PasswordAuthenticationMethodInventory(this.store, this.providerId);

  final AuthStore store;
  final String providerId;

  @override
  String get authenticationMethodNamespace => 'password:$providerId';

  @override
  Object get authenticationMethodStore => store.credentials;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.password,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async {
    final credential = await findAuthCredentialForUser(store, userId);
    return AuthAuthenticationMethodSnapshot.complete([
      if (credential?.enabled == true)
        AuthAuthenticationMethod.password(
          credential!.id,
          providerId: providerId,
        ),
    ]);
  }
}

/// Email verification payload shared with provider callbacks.
class AuthEmailRequest {
  AuthEmailRequest({
    required this.email,
    required this.token,
    required this.callbackUrl,
    required this.expiresAt,
  });

  /// User email address.
  final String email;

  /// Verification token.
  final String token;

  /// Callback URL to complete the sign-in.
  final String callbackUrl;

  /// Expiration timestamp for the token.
  final DateTime expiresAt;
}

/// Relying party configuration for WebAuthn.
///
/// The relying party represents your application/domain to the authenticator.
class WebAuthnRelyingParty {
  const WebAuthnRelyingParty({
    required this.id,
    required this.name,
    required this.origin,
  });

  /// Relying party ID (typically the domain name).
  final String id;

  /// Human-readable name of the relying party.
  final String name;

  /// Origin URL (protocol + domain).
  final String origin;
}

/// Authenticator device stored for a user.
class WebAuthnAuthenticator {
  const WebAuthnAuthenticator({
    required this.credentialId,
    required this.publicKey,
    required this.counter,
    this.userId,
    this.transports,
    this.createdAt,
    this.lastUsedAt,
    this.name,
  });

  /// Unique credential identifier.
  final String credentialId;

  /// COSE public key bytes (base64 encoded).
  final String publicKey;

  /// Signature counter for replay protection.
  final int counter;

  /// Associated user ID.
  final String? userId;

  /// Supported transports (usb, nfc, ble, internal).
  final List<String>? transports;

  /// When the authenticator was registered.
  final DateTime? createdAt;

  /// When the authenticator was last used.
  final DateTime? lastUsedAt;

  /// Optional friendly name for the authenticator.
  final String? name;

  Map<String, dynamic> toJson() => {
    'credential_id': credentialId,
    'public_key': publicKey,
    'counter': counter,
    'user_id': userId,
    'transports': transports,
    'created_at': createdAt?.toIso8601String(),
    'last_used_at': lastUsedAt?.toIso8601String(),
    'name': name,
  };

  factory WebAuthnAuthenticator.fromJson(Map<String, dynamic> json) {
    final rawCounter = json['counter'];
    final rawTransports = json['transports'];
    return WebAuthnAuthenticator(
      credentialId: json['credential_id']?.toString() ?? '',
      publicKey: json['public_key']?.toString() ?? '',
      counter: rawCounter is int && rawCounter >= 0 ? rawCounter : 0,
      userId: json['user_id']?.toString(),
      transports: rawTransports is List
          ? rawTransports.whereType<String>().toList(growable: false)
          : null,
      createdAt: _tryParseWebAuthnDate(json['created_at']),
      lastUsedAt: _tryParseWebAuthnDate(json['last_used_at']),
      name: json['name']?.toString(),
    );
  }
}

DateTime? _tryParseWebAuthnDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

/// Callback to retrieve user info for WebAuthn registration/authentication.
typedef WebAuthnGetUserInfo =
    FutureOr<WebAuthnUserInfo?> Function(
      AuthContext context,
      WebAuthnProvider provider,
      Map<String, dynamic> request,
    );

/// Callback to get the relying party configuration.
typedef WebAuthnGetRelyingParty =
    WebAuthnRelyingParty Function(
      AuthContext context,
      WebAuthnProvider provider,
    );

/// User info returned by WebAuthn getUserInfo callback.
class WebAuthnUserInfo {
  const WebAuthnUserInfo({required this.user, required this.exists});

  /// The user (new or existing).
  final AuthUser user;

  /// Whether the user already exists in the database.
  final bool exists;
}

/// {@template server_auth_webauthn_provider}
/// WebAuthn (Passkey) provider configuration.
///
/// Enables passwordless authentication using passkeys, biometrics, and
/// hardware security keys following the WebAuthn standard.
///
/// ## Required callbacks
/// - [getUserInfo] retrieves user information for registration/authentication.
/// - [getRelyingParty] returns the relying party (domain) configuration.
///
/// ## Configuration
/// - [timeout] controls the authentication ceremony timeout.
/// - [enableConditionalUI] enables autofill-assisted sign-in.
/// - [formFields] defines fields shown in the default sign-in form.
/// {@endtemplate}
class WebAuthnProvider extends AuthProvider {
  WebAuthnProvider({
    super.id = 'webauthn',
    super.name = 'Passkey',
    required this.getUserInfo,
    required this.getRelyingParty,
    this.timeout = const Duration(minutes: 5),
    this.enableConditionalUI = true,
    this.formFields = const {
      'email': WebAuthnFormField(label: 'Email', required: true),
    },
    this.registrationOptions = const WebAuthnRegistrationOptions(),
    this.authenticationOptions = const WebAuthnAuthenticationOptions(),
  }) : super(type: AuthProviderType.webauthn);

  /// Retrieves user info for the WebAuthn ceremony.
  final WebAuthnGetUserInfo getUserInfo;

  /// Returns the relying party configuration.
  final WebAuthnGetRelyingParty getRelyingParty;

  /// Timeout for WebAuthn ceremonies.
  final Duration timeout;

  /// Whether to enable conditional UI (autofill-assisted passkeys).
  final bool enableConditionalUI;

  /// Form fields displayed in the default sign-in form.
  final Map<String, WebAuthnFormField> formFields;

  /// Registration-specific options.
  final WebAuthnRegistrationOptions registrationOptions;

  /// Authentication-specific options.
  final WebAuthnAuthenticationOptions authenticationOptions;
}

/// Form field configuration for WebAuthn sign-in forms.
class WebAuthnFormField {
  const WebAuthnFormField({
    this.label,
    this.required = false,
    this.type = 'text',
    this.autocomplete,
  });

  /// Label shown in the form.
  final String? label;

  /// Whether the field is required.
  final bool required;

  /// HTML input type.
  final String type;

  /// Autocomplete attribute value.
  final String? autocomplete;
}

/// Options for WebAuthn registration ceremonies.
class WebAuthnRegistrationOptions {
  const WebAuthnRegistrationOptions({
    this.attestation = 'none',
    this.authenticatorSelection,
    this.excludeCredentials = true,
  });

  /// Attestation conveyance preference (none, indirect, direct).
  final String attestation;

  /// Authenticator selection criteria.
  final WebAuthnAuthenticatorSelection? authenticatorSelection;

  /// Whether to exclude existing credentials during registration.
  final bool excludeCredentials;
}

/// Options for WebAuthn authentication ceremonies.
class WebAuthnAuthenticationOptions {
  const WebAuthnAuthenticationOptions({this.userVerification = 'preferred'});

  /// User verification requirement (required, preferred, discouraged).
  final String userVerification;
}

/// Authenticator selection criteria for registration.
class WebAuthnAuthenticatorSelection {
  const WebAuthnAuthenticatorSelection({
    this.authenticatorAttachment,
    this.residentKey = 'preferred',
    this.userVerification = 'preferred',
  });

  /// Attachment type (platform, cross-platform).
  final String? authenticatorAttachment;

  /// Resident key requirement (required, preferred, discouraged).
  final String residentKey;

  /// User verification requirement.
  final String userVerification;
}

/// Result from a custom callback provider's handleCallback method.
class CallbackResult {
  const CallbackResult({required this.user, this.redirect, this.error});

  /// Successfully authenticated user.
  final AuthUser? user;

  /// Optional redirect URL after authentication.
  final String? redirect;

  /// Error message if authentication failed.
  final String? error;

  /// Creates a successful result.
  const CallbackResult.success(AuthUser this.user, {this.redirect})
    : error = null;

  /// Creates an error result.
  const CallbackResult.failure(String this.error)
    : user = null,
      redirect = null;

  /// Whether authentication succeeded.
  bool get isSuccess => user != null && error == null;
}

/// Mixin for auth providers that handle custom callback flows.
///
/// Implement this mixin on custom providers (like Telegram) that don't follow
/// standard OAuth or email flows. The [handleCallback] method will be called
/// by [AuthRoutes] when the callback URL is accessed.
///
/// ## Example
///
/// ```dart
/// class TelegramProvider extends AuthProvider with CallbackProvider {
///   @override
///   Future<CallbackResult> handleCallback(
///     AuthContext ctx,
///     Map<String, String> params,
///   ) async {
///     // Verify HMAC signature from Telegram
///     final profile = verifyAndParseCallback(params);
///     final user = mapProfile(profile);
///     return CallbackResult.success(user, redirect: '/profile');
///   }
/// }
/// ```
mixin CallbackProvider on AuthProvider {
  /// Handles the callback request from the external provider.
  ///
  /// [ctx] is the engine context for the request.
  /// [params] contains query parameters from the callback URL.
  ///
  /// Returns a [CallbackResult] with either the authenticated user
  /// or an error message.
  FutureOr<CallbackResult> handleCallback(
    AuthContext ctx,
    Map<String, String> params,
  );
}
