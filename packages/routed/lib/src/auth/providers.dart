import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:routed/src/auth/models.dart';
import 'package:routed/src/auth/oauth.dart';
import 'package:routed/src/context/context.dart';

/// {@template routed_auth_provider_overview}
/// Base metadata for a routed auth provider.
///
/// Providers describe the authentication mechanism and the identifiers exposed
/// by `AuthRoutes` at `/auth/providers`.
/// {@endtemplate}
///
/// {@template routed_auth_oauth_provider}
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
/// {@template routed_auth_email_provider}
/// Email (magic link) provider configuration.
///
/// Provide `sendVerificationRequest` to send the token to the user. The
/// provider uses `tokenExpiry` and `tokenGenerator` to manage verification.
/// {@endtemplate}
///
/// {@template routed_auth_credentials_provider}
/// Credentials provider configuration.
///
/// Provide `authorize` to validate username/email/password input. When omitted,
/// the `AuthAdapter.verifyCredentials` hook is used.
///
/// Provide `register` to create new users. When omitted, the
/// `AuthAdapter.registerCredentials` hook is used.
/// {@endtemplate}

/// Supported provider kinds.
enum AuthProviderType { oauth, email, credentials }

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
      EngineContext context,
      OAuthProvider<TProfile> provider,
      String state,
    );

/// Called after the OAuth profile is loaded.
typedef OAuthProfileCallback<TProfile extends Object> =
    FutureOr<AuthUser?> Function(
      EngineContext context,
      OAuthProvider<TProfile> provider,
      TProfile profile,
    );

/// Called to enrich or replace the OAuth profile data.
typedef OAuthProfileRequest<TProfile extends Object> =
    FutureOr<TProfile> Function(
      EngineContext context,
      OAuthProvider<TProfile> provider,
      OAuthTokenResponse token,
      http.Client httpClient,
      TProfile profile,
    );

/// Sends a verification token for email flows.
typedef EmailSendCallback =
    FutureOr<void> Function(
      EngineContext context,
      EmailProvider provider,
      AuthEmailRequest request,
    );

/// Authorizes credential-based sign-in.
typedef CredentialsAuthorize =
    FutureOr<AuthUser?> Function(
      EngineContext context,
      CredentialsProvider provider,
      AuthCredentials credentials,
    );

/// Registers a new user from credential input.
typedef CredentialsRegister =
    FutureOr<AuthUser?> Function(
      EngineContext context,
      CredentialsProvider provider,
      AuthCredentials credentials,
    );

/// {@macro routed_auth_provider_overview}
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
}

/// {@macro routed_auth_oauth_provider}
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
    this.userInfoEndpoint,
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
  }) : super(type: AuthProviderType.oauth);

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
  FutureOr<AuthUser?> overrideProfile(EngineContext context, TProfile profile) {
    if (onProfile == null) {
      return null;
    }
    return onProfile!(context, this, profile);
  }

  /// Runs the optional profile enrichment hook.
  FutureOr<TProfile> enrichProfile(
    EngineContext context,
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

/// {@macro routed_auth_email_provider}
class EmailProvider extends AuthProvider {
  EmailProvider({
    super.id = 'email',
    super.name = 'Email',
    required this.sendVerificationRequest,
    this.tokenExpiry = const Duration(minutes: 15),
    this.tokenGenerator,
  }) : super(type: AuthProviderType.email);

  /// Sends the verification email (or other delivery mechanism).
  final EmailSendCallback sendVerificationRequest;

  /// Expiration window for the verification token.
  final Duration tokenExpiry;

  /// Custom token generator. Defaults to a secure random token.
  final String Function()? tokenGenerator;
}

/// {@macro routed_auth_credentials_provider}
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
