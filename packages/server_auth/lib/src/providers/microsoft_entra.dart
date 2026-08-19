import '../core/core.dart';

/// Microsoft Entra ID (Azure AD) user profile.
///
/// See [Microsoft Graph User resource](https://learn.microsoft.com/en-us/graph/api/resources/user).
class MicrosoftEntraProfile {
  /// Creates a new [MicrosoftEntraProfile] with the given fields.
  const MicrosoftEntraProfile({
    required this.sub,
    this.email,
    this.name,
    this.preferredUsername,
    this.picture,
    this.givenName,
    this.familyName,
    this.oid,
    this.tid,
  });

  /// Subject identifier (unique user ID).
  final String sub;

  /// User's email address.
  final String? email;

  /// User's display name.
  final String? name;

  /// User's preferred username (usually email or UPN).
  final String? preferredUsername;

  /// URL of the user's profile picture.
  final String? picture;

  /// User's given/first name.
  final String? givenName;

  /// User's family/last name.
  final String? familyName;

  /// Object ID (unique within tenant).
  final String? oid;

  /// Tenant ID.
  final String? tid;

  /// Creates a [MicrosoftEntraProfile] from a JSON map returned by Microsoft Graph.
  factory MicrosoftEntraProfile.fromJson(Map<String, dynamic> json) {
    return MicrosoftEntraProfile(
      sub: json['sub']?.toString() ?? json['oid']?.toString() ?? '',
      email: json['email']?.toString(),
      name: json['name']?.toString(),
      preferredUsername: json['preferred_username']?.toString(),
      picture: json['picture']?.toString(),
      givenName: json['given_name']?.toString(),
      familyName: json['family_name']?.toString(),
      oid: json['oid']?.toString(),
      tid: json['tid']?.toString(),
    );
  }

  /// Converts this profile to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'sub': sub,
    'email': email,
    'name': name,
    'preferred_username': preferredUsername,
    'picture': picture,
    'given_name': givenName,
    'family_name': familyName,
    'oid': oid,
    'tid': tid,
  };
}

/// Tenant type for Microsoft Entra ID.
enum MicrosoftEntraTenantType {
  /// Only allow users from your organization.
  singleTenant,

  /// Allow users from any organization.
  multiTenant,

  /// Allow any Microsoft account (work, school, personal).
  multiTenantAndPersonal,

  /// Only allow personal Microsoft accounts.
  personalOnly,
}

/// Configuration for the Microsoft Entra ID OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/microsoft-entra-id
/// ```
///
/// ### Usage
/// ```dart
/// import 'package:server_auth/server_auth.dart';
/// import 'package:server_auth/server_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     providers: [
///       microsoftEntraProvider(
///         MicrosoftEntraProviderOptions(
///           clientId: env('AZURE_AD_CLIENT_ID'),
///           clientSecret: env('AZURE_AD_CLIENT_SECRET'),
///           tenantId: env('AZURE_AD_TENANT_ID'), // or use tenantType
///           redirectUri: 'https://example.com/auth/callback/microsoft-entra-id',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OpenID Connect with OAuth 2.0.
/// - Set `tenantId` for single-tenant apps, or `tenantType` for multi-tenant.
/// - Microsoft returns profile picture as binary data - consider using Graph API.
class MicrosoftEntraProviderOptions {
  /// Creates a new [MicrosoftEntraProviderOptions] configuration.
  const MicrosoftEntraProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.tenantId,
    this.tenantType,
    this.scopes = const ['openid', 'profile', 'email'],
  });

  /// Application (client) ID from the Azure portal.
  final String clientId;

  /// Client secret from the Azure portal.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// Specific tenant ID (for single-tenant apps).
  final String? tenantId;

  /// Tenant type (for multi-tenant apps). Ignored if tenantId is set.
  final MicrosoftEntraTenantType? tenantType;

  /// OAuth scopes to request. Defaults to `['openid', 'profile', 'email']`.
  final List<String> scopes;

  String get _issuerPath {
    if (tenantId != null && tenantId!.isNotEmpty) {
      return tenantId!;
    }
    switch (tenantType) {
      case MicrosoftEntraTenantType.singleTenant:
        throw ArgumentError('tenantId is required for single-tenant apps');
      case MicrosoftEntraTenantType.multiTenant:
        return 'organizations';
      case MicrosoftEntraTenantType.personalOnly:
        return 'consumers';
      case MicrosoftEntraTenantType.multiTenantAndPersonal:
      case null:
        return 'common';
    }
  }
}

/// Microsoft Entra ID (Azure AD) OAuth provider.
///
/// Based on Microsoft's OAuth 2.0 and OpenID Connect documentation.
///
/// ### Resources
/// - https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow
/// - https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app
///
/// ### Example
/// ```dart
/// final provider = microsoftEntraProvider(
///   MicrosoftEntraProviderOptions(
///     clientId: 'client-id',
///     clientSecret: 'client-secret',
///     tenantId: 'your-tenant-id',
///     redirectUri: 'https://example.com/auth/callback/microsoft-entra-id',
///   ),
/// );
/// ```
OAuthProvider<MicrosoftEntraProfile> microsoftEntraProvider(
  MicrosoftEntraProviderOptions options,
) {
  final issuerPath = options._issuerPath;
  final baseUrl = 'https://login.microsoftonline.com/$issuerPath/v2.0';

  return OAuthProvider<MicrosoftEntraProfile>(
    id: 'microsoft-entra-id',
    name: 'Microsoft Entra ID',
    type: AuthProviderType.oidc,
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse('$baseUrl/authorize'),
    tokenEndpoint: Uri.parse('$baseUrl/token'),
    userInfoEndpoint: Uri.parse('https://graph.microsoft.com/oidc/userinfo'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: MicrosoftEntraProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.sub,
        name: profile.name,
        email: profile.email ?? profile.preferredUsername,
        image: profile.picture,
        attributes: profile.toJson(),
      );
    },
  );
}
