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
    super.type = AuthProviderType.oauth,
    this.userInfoEndpoint,
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
  });

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
    return WebAuthnAuthenticator(
      credentialId: json['credential_id']?.toString() ?? '',
      publicKey: json['public_key']?.toString() ?? '',
      counter: json['counter'] as int? ?? 0,
      userId: json['user_id']?.toString(),
      transports: (json['transports'] as List?)?.cast<String>(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : null,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'].toString())
          : null,
      name: json['name']?.toString(),
    );
  }
}

/// Callback to retrieve user info for WebAuthn registration/authentication.
typedef WebAuthnGetUserInfo =
    FutureOr<WebAuthnUserInfo?> Function(
      EngineContext context,
      WebAuthnProvider provider,
      Map<String, dynamic> request,
    );

/// Callback to get the relying party configuration.
typedef WebAuthnGetRelyingParty =
    WebAuthnRelyingParty Function(
      EngineContext context,
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

/// {@template routed_auth_webauthn_provider}
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
///     EngineContext ctx,
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
    EngineContext ctx,
    Map<String, String> params,
  );
}
