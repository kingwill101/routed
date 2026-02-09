import 'package:routed/routed.dart';

/// GitLab user profile.
///
/// See [GitLab User API](https://docs.gitlab.com/ee/api/users.html).
class GitLabProfile {
  /// Creates a new [GitLabProfile] with the given fields.
  const GitLabProfile({
    required this.id,
    required this.username,
    this.email,
    this.name,
    this.avatarUrl,
    this.webUrl,
    this.state,
    this.bio,
    this.location,
    this.publicEmail,
    this.websiteUrl,
    this.organization,
    this.jobTitle,
    this.twoFactorEnabled,
    this.isAdmin,
    this.createdAt,
  });

  /// User ID.
  final int id;

  /// User's username.
  final String username;

  /// User's primary email.
  final String? email;

  /// User's display name.
  final String? name;

  /// URL of the user's avatar.
  final String? avatarUrl;

  /// URL to user's GitLab profile.
  final String? webUrl;

  /// Account state (active, blocked, etc.).
  final String? state;

  /// User's bio.
  final String? bio;

  /// User's location.
  final String? location;

  /// User's public email.
  final String? publicEmail;

  /// User's website URL.
  final String? websiteUrl;

  /// User's organization.
  final String? organization;

  /// User's job title.
  final String? jobTitle;

  /// Whether 2FA is enabled.
  final bool? twoFactorEnabled;

  /// Whether user is admin.
  final bool? isAdmin;

  /// When the account was created.
  final String? createdAt;

  /// Creates a [GitLabProfile] from a JSON map returned by the GitLab API.
  factory GitLabProfile.fromJson(Map<String, dynamic> json) {
    return GitLabProfile(
      id: json['id'] as int? ?? 0,
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString(),
      name: json['name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      webUrl: json['web_url']?.toString(),
      state: json['state']?.toString(),
      bio: json['bio']?.toString(),
      location: json['location']?.toString(),
      publicEmail: json['public_email']?.toString(),
      websiteUrl: json['website_url']?.toString(),
      organization: json['organization']?.toString(),
      jobTitle: json['job_title']?.toString(),
      twoFactorEnabled: json['two_factor_enabled'] as bool?,
      isAdmin: json['is_admin'] as bool?,
      createdAt: json['created_at']?.toString(),
    );
  }

  /// Converts this profile to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'name': name,
    'avatar_url': avatarUrl,
    'web_url': webUrl,
    'state': state,
    'bio': bio,
    'location': location,
    'public_email': publicEmail,
    'website_url': websiteUrl,
    'organization': organization,
    'job_title': jobTitle,
    'two_factor_enabled': twoFactorEnabled,
    'is_admin': isAdmin,
    'created_at': createdAt,
  };
}

/// Configuration for the GitLab OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/gitlab
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
///       gitlabProvider(
///         GitLabProviderOptions(
///           clientId: env('GITLAB_CLIENT_ID'),
///           clientSecret: env('GITLAB_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/gitlab',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - For self-hosted GitLab, set [baseUrl].
class GitLabProviderOptions {
  /// Creates a new [GitLabProviderOptions] configuration.
  const GitLabProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.baseUrl,
    this.scopes = const ['read_user'],
  });

  /// OAuth 2.0 application ID from GitLab.
  final String clientId;

  /// OAuth 2.0 application secret from GitLab.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// Base URL for self-hosted GitLab instances.
  final String? baseUrl;

  /// OAuth scopes to request. Defaults to `['read_user']`.
  final List<String> scopes;
}

/// GitLab OAuth provider.
///
/// ### Resources
/// - https://docs.gitlab.com/ee/api/oauth2.html
/// - https://docs.gitlab.com/ee/api/users.html
OAuthProvider<GitLabProfile> gitlabProvider(GitLabProviderOptions options) {
  final baseUrl = options.baseUrl ?? 'https://gitlab.com';

  return OAuthProvider<GitLabProfile>(
    id: 'gitlab',
    name: 'GitLab',
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse('$baseUrl/oauth/authorize'),
    tokenEndpoint: Uri.parse('$baseUrl/oauth/token'),
    userInfoEndpoint: Uri.parse('$baseUrl/api/v4/user'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: GitLabProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.id.toString(),
        name: profile.name ?? profile.username,
        email: profile.email ?? profile.publicEmail,
        image: profile.avatarUrl,
        attributes: profile.toJson(),
      );
    },
  );
}

const List<String> _defaultGitLabScopes = ['read_user'];

AuthProviderRegistration _gitlabRegistration() {
  return AuthProviderRegistration(
    id: 'gitlab',
    schema: ConfigSchema.object(
      description: 'GitLab OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the GitLab provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'GitLab OAuth client ID.',
          defaultValue: "{{ env.GITLAB_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'GitLab OAuth client secret.',
          defaultValue: "{{ env.GITLAB_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for GitLab callbacks.',
          defaultValue: "{{ env.GITLAB_REDIRECT_URI | default: '' }}",
        ),
        'base_url': ConfigSchema.string(
          description: 'Base URL for self-hosted GitLab.',
          defaultValue: '',
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from GitLab.',
          items: ConfigSchema.string(),
          defaultValue: _defaultGitLabScopes,
        ),
      },
    ),
    builder: _buildGitLabProvider,
  );
}

AuthProvider? _buildGitLabProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.gitlab.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.gitlab.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.gitlab.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.gitlab.redirect_uri',
  );
  final baseUrl = _nullIfEmpty(
    parseStringLike(
      config['base_url'],
      context: 'auth.providers.gitlab.base_url',
      allowEmpty: true,
      throwOnInvalid: true,
    ),
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.gitlab.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultGitLabScopes;

  return gitlabProvider(
    GitLabProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      baseUrl: baseUrl,
      scopes: scopes.isEmpty ? _defaultGitLabScopes : scopes,
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

/// Register the GitLab OAuth provider with the registry.
void registerGitLabAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_gitlabRegistration(), overrideExisting: overrideExisting);
}
