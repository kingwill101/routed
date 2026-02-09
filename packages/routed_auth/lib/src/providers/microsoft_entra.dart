import 'package:routed/routed.dart';

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
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
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

const List<String> _defaultMicrosoftScopes = ['openid', 'profile', 'email'];

AuthProviderRegistration _microsoftEntraRegistration() {
  return AuthProviderRegistration(
    id: 'microsoft-entra-id',
    schema: ConfigSchema.object(
      description: 'Microsoft Entra ID (Azure AD) OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Microsoft Entra ID provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Microsoft Entra ID OAuth client ID.',
          defaultValue: "{{ env.AZURE_AD_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Microsoft Entra ID OAuth client secret.',
          defaultValue: "{{ env.AZURE_AD_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Microsoft callbacks.',
          defaultValue: "{{ env.AZURE_AD_REDIRECT_URI | default: '' }}",
        ),
        'tenant_id': ConfigSchema.string(
          description: 'Azure AD Tenant ID (for single-tenant apps).',
          defaultValue: "{{ env.AZURE_AD_TENANT_ID | default: '' }}",
        ),
        'tenant_type': ConfigSchema.string(
          description:
              'Tenant type: single_tenant, multi_tenant, multi_tenant_and_personal, personal_only.',
          defaultValue: 'multi_tenant_and_personal',
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Microsoft.',
          items: ConfigSchema.string(),
          defaultValue: _defaultMicrosoftScopes,
        ),
      },
    ),
    builder: _buildMicrosoftEntraProvider,
  );
}

AuthProvider? _buildMicrosoftEntraProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.microsoft-entra-id.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.microsoft-entra-id.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.microsoft-entra-id.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.microsoft-entra-id.redirect_uri',
  );
  final tenantId = _nullIfEmpty(
    parseStringLike(
      config['tenant_id'],
      context: 'auth.providers.microsoft-entra-id.tenant_id',
      allowEmpty: true,
      throwOnInvalid: true,
    ),
  );
  final tenantTypeStr = parseStringLike(
    config['tenant_type'],
    context: 'auth.providers.microsoft-entra-id.tenant_type',
    allowEmpty: true,
    throwOnInvalid: true,
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.microsoft-entra-id.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultMicrosoftScopes;

  MicrosoftEntraTenantType? tenantType;
  if (tenantTypeStr != null && tenantTypeStr.isNotEmpty) {
    switch (tenantTypeStr) {
      case 'single_tenant':
        tenantType = MicrosoftEntraTenantType.singleTenant;
        break;
      case 'multi_tenant':
        tenantType = MicrosoftEntraTenantType.multiTenant;
        break;
      case 'multi_tenant_and_personal':
        tenantType = MicrosoftEntraTenantType.multiTenantAndPersonal;
        break;
      case 'personal_only':
        tenantType = MicrosoftEntraTenantType.personalOnly;
        break;
    }
  }

  return microsoftEntraProvider(
    MicrosoftEntraProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      tenantId: tenantId,
      tenantType: tenantType,
      scopes: scopes.isEmpty ? _defaultMicrosoftScopes : scopes,
    ),
  );
}

String _requireString(Object? value, String context) {
  final resolved = parseStringLike(
    value,
    context: context,
    allowEmpty: true,
    throwOnInvalid: true,
  );
  if (resolved == null || resolved.trim().isEmpty) {
    throw ProviderConfigException('$context is required');
  }
  return resolved.trim();
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Register the Microsoft Entra ID OAuth provider with the registry.
void registerMicrosoftEntraAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(
    _microsoftEntraRegistration(),
    overrideExisting: overrideExisting,
  );
}
