import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:routed/src/auth/models.dart';
import 'package:routed/src/auth/oauth.dart';
import 'package:routed/src/auth/provider_registry.dart';
import 'package:routed/src/auth/providers.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

/// GitHub email payload returned by `/user/emails`.
class GitHubEmail {
  GitHubEmail({
    required this.email,
    required this.primary,
    required this.verified,
    required this.visibility,
  });

  final String email;
  final bool primary;
  final bool verified;
  final String visibility;

  factory GitHubEmail.fromJson(Map<String, dynamic> json) {
    return GitHubEmail(
      email: json['email']?.toString() ?? '',
      primary: json['primary'] == true,
      verified: json['verified'] == true,
      visibility: json['visibility']?.toString() ?? 'private',
    );
  }
}

/// GitHub user plan information.
class GitHubPlan {
  const GitHubPlan({
    required this.collaborators,
    required this.name,
    required this.space,
    required this.privateRepos,
  });

  final int collaborators;
  final String name;
  final int space;
  final int privateRepos;

  factory GitHubPlan.fromJson(Map<String, dynamic> json) {
    return GitHubPlan(
      collaborators: json['collaborators'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      space: json['space'] as int? ?? 0,
      privateRepos: json['private_repos'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'collaborators': collaborators,
    'name': name,
    'space': space,
    'private_repos': privateRepos,
  };
}

/// GitHub user profile returned by `GET /user`.
///
/// See [Get the authenticated user](https://docs.github.com/en/rest/users/users#get-the-authenticated-user).
class GitHubProfile {
  const GitHubProfile({
    required this.login,
    required this.id,
    required this.nodeId,
    required this.avatarUrl,
    this.gravatarId,
    required this.url,
    required this.htmlUrl,
    required this.followersUrl,
    required this.followingUrl,
    required this.gistsUrl,
    required this.starredUrl,
    required this.subscriptionsUrl,
    required this.organizationsUrl,
    required this.reposUrl,
    required this.eventsUrl,
    required this.receivedEventsUrl,
    required this.type,
    required this.siteAdmin,
    this.name,
    this.company,
    this.blog,
    this.location,
    this.email,
    this.hireable,
    this.bio,
    this.twitterUsername,
    required this.publicRepos,
    required this.publicGists,
    required this.followers,
    required this.following,
    required this.createdAt,
    required this.updatedAt,
    this.privateGists,
    this.totalPrivateRepos,
    this.ownedPrivateRepos,
    this.diskUsage,
    this.suspendedAt,
    this.collaborators,
    required this.twoFactorAuthentication,
    this.plan,
  });

  final String login;
  final int id;
  final String nodeId;
  final String avatarUrl;
  final String? gravatarId;
  final String url;
  final String htmlUrl;
  final String followersUrl;
  final String followingUrl;
  final String gistsUrl;
  final String starredUrl;
  final String subscriptionsUrl;
  final String organizationsUrl;
  final String reposUrl;
  final String eventsUrl;
  final String receivedEventsUrl;
  final String type;
  final bool siteAdmin;
  final String? name;
  final String? company;
  final String? blog;
  final String? location;
  final String? email;
  final bool? hireable;
  final String? bio;
  final String? twitterUsername;
  final int publicRepos;
  final int publicGists;
  final int followers;
  final int following;
  final String createdAt;
  final String updatedAt;
  final int? privateGists;
  final int? totalPrivateRepos;
  final int? ownedPrivateRepos;
  final int? diskUsage;
  final String? suspendedAt;
  final int? collaborators;
  final bool twoFactorAuthentication;
  final GitHubPlan? plan;

  factory GitHubProfile.fromJson(Map<String, dynamic> json) {
    return GitHubProfile(
      login: json['login']?.toString() ?? '',
      id: json['id'] as int? ?? 0,
      nodeId: json['node_id']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString() ?? '',
      gravatarId: json['gravatar_id']?.toString(),
      url: json['url']?.toString() ?? '',
      htmlUrl: json['html_url']?.toString() ?? '',
      followersUrl: json['followers_url']?.toString() ?? '',
      followingUrl: json['following_url']?.toString() ?? '',
      gistsUrl: json['gists_url']?.toString() ?? '',
      starredUrl: json['starred_url']?.toString() ?? '',
      subscriptionsUrl: json['subscriptions_url']?.toString() ?? '',
      organizationsUrl: json['organizations_url']?.toString() ?? '',
      reposUrl: json['repos_url']?.toString() ?? '',
      eventsUrl: json['events_url']?.toString() ?? '',
      receivedEventsUrl: json['received_events_url']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      siteAdmin: json['site_admin'] == true,
      name: json['name']?.toString(),
      company: json['company']?.toString(),
      blog: json['blog']?.toString(),
      location: json['location']?.toString(),
      email: json['email']?.toString(),
      hireable: json['hireable'] as bool?,
      bio: json['bio']?.toString(),
      twitterUsername: json['twitter_username']?.toString(),
      publicRepos: json['public_repos'] as int? ?? 0,
      publicGists: json['public_gists'] as int? ?? 0,
      followers: json['followers'] as int? ?? 0,
      following: json['following'] as int? ?? 0,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      privateGists: json['private_gists'] as int?,
      totalPrivateRepos: json['total_private_repos'] as int?,
      ownedPrivateRepos: json['owned_private_repos'] as int?,
      diskUsage: json['disk_usage'] as int?,
      suspendedAt: json['suspended_at']?.toString(),
      collaborators: json['collaborators'] as int?,
      twoFactorAuthentication: json['two_factor_authentication'] == true,
      plan: json['plan'] != null
          ? GitHubPlan.fromJson(json['plan'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'login': login,
    'id': id,
    'node_id': nodeId,
    'avatar_url': avatarUrl,
    'gravatar_id': gravatarId,
    'url': url,
    'html_url': htmlUrl,
    'followers_url': followersUrl,
    'following_url': followingUrl,
    'gists_url': gistsUrl,
    'starred_url': starredUrl,
    'subscriptions_url': subscriptionsUrl,
    'organizations_url': organizationsUrl,
    'repos_url': reposUrl,
    'events_url': eventsUrl,
    'received_events_url': receivedEventsUrl,
    'type': type,
    'site_admin': siteAdmin,
    'name': name,
    'company': company,
    'blog': blog,
    'location': location,
    'email': email,
    'hireable': hireable,
    'bio': bio,
    'twitter_username': twitterUsername,
    'public_repos': publicRepos,
    'public_gists': publicGists,
    'followers': followers,
    'following': following,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'private_gists': privateGists,
    'total_private_repos': totalPrivateRepos,
    'owned_private_repos': ownedPrivateRepos,
    'disk_usage': diskUsage,
    'suspended_at': suspendedAt,
    'collaborators': collaborators,
    'two_factor_authentication': twoFactorAuthentication,
    'plan': plan?.toJson(),
  };

  GitHubProfile copyWith({String? email}) {
    return GitHubProfile(
      login: login,
      id: id,
      nodeId: nodeId,
      avatarUrl: avatarUrl,
      gravatarId: gravatarId,
      url: url,
      htmlUrl: htmlUrl,
      followersUrl: followersUrl,
      followingUrl: followingUrl,
      gistsUrl: gistsUrl,
      starredUrl: starredUrl,
      subscriptionsUrl: subscriptionsUrl,
      organizationsUrl: organizationsUrl,
      reposUrl: reposUrl,
      eventsUrl: eventsUrl,
      receivedEventsUrl: receivedEventsUrl,
      type: type,
      siteAdmin: siteAdmin,
      name: name,
      company: company,
      blog: blog,
      location: location,
      email: email ?? this.email,
      hireable: hireable,
      bio: bio,
      twitterUsername: twitterUsername,
      publicRepos: publicRepos,
      publicGists: publicGists,
      followers: followers,
      following: following,
      createdAt: createdAt,
      updatedAt: updatedAt,
      privateGists: privateGists,
      totalPrivateRepos: totalPrivateRepos,
      ownedPrivateRepos: ownedPrivateRepos,
      diskUsage: diskUsage,
      suspendedAt: suspendedAt,
      collaborators: collaborators,
      twoFactorAuthentication: twoFactorAuthentication,
      plan: plan,
    );
  }
}

/// Configuration for the GitHub OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/github
/// ```
///
/// ### Usage
/// ```dart
/// import 'package:routed/auth.dart';
/// import 'package:routed/auth/providers/github.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     providers: [
///       githubProvider(
///         GitHubProviderOptions(
///           clientId: env('GITHUB_CLIENT_ID'),
///           clientSecret: env('GITHUB_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/github',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OAuth 2.0 Authorization Code flow.
/// - When GitHub does not return a public email, the provider calls
///   `GET /user/emails` and selects the primary email.
/// - For GitHub Enterprise Server, set [enterpriseBaseUrl].
class GitHubProviderOptions {
  const GitHubProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.enterpriseBaseUrl,
    this.scopes = const ['read:user', 'user:email'],
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final String? enterpriseBaseUrl;
  final List<String> scopes;
}

/// GitHub OAuth provider.
///
/// Based on GitHub's OAuth documentation and NextAuth's default provider
/// configuration. Retrieves the authenticated user from `GET /user` and
/// falls back to `GET /user/emails` if the email is missing.
///
/// ### Resources
/// - https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app
/// - https://docs.github.com/en/developers/apps/building-oauth-apps/authorizing-oauth-apps
/// - https://docs.github.com/en/rest/users/users#get-the-authenticated-user
/// - https://docs.github.com/en/rest/users/emails#list-public-email-addresses-for-the-authenticated-user
///
/// ### Example
/// ```dart
/// final provider = githubProvider(
///   GitHubProviderOptions(
///     clientId: 'client-id',
///     clientSecret: 'client-secret',
///     redirectUri: 'https://example.com/auth/callback/github',
///   ),
/// );
/// ```
OAuthProvider<GitHubProfile> githubProvider(GitHubProviderOptions options) {
  final baseUrl = options.enterpriseBaseUrl ?? 'https://github.com';
  final apiBaseUrl = options.enterpriseBaseUrl != null
      ? '${options.enterpriseBaseUrl}/api/v3'
      : 'https://api.github.com';

  return OAuthProvider<GitHubProfile>(
    id: 'github',
    name: 'GitHub',
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse('$baseUrl/login/oauth/authorize'),
    tokenEndpoint: Uri.parse('$baseUrl/login/oauth/access_token'),
    userInfoEndpoint: Uri.parse('$apiBaseUrl/user'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: GitHubProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.id.toString(),
        name: profile.name ?? profile.login,
        email: profile.email,
        image: profile.avatarUrl,
        attributes: profile.toJson(),
      );
    },
    profileRequest: (_, _, token, httpClient, profile) async {
      if (profile.email != null && profile.email!.isNotEmpty) {
        return profile;
      }
      final emails = await _loadGitHubEmails(token, httpClient, apiBaseUrl);
      if (emails.isEmpty) return profile;
      final primary = emails.firstWhere(
        (entry) => entry.primary && entry.verified,
        orElse: () => emails.first,
      );
      return profile.copyWith(email: primary.email);
    },
  );
}

const List<String> _defaultGitHubScopes = ['read:user', 'user:email'];

AuthProviderRegistration _githubRegistration() {
  return AuthProviderRegistration(
    id: 'github',
    schema: ConfigSchema.object(
      description: 'GitHub OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the GitHub provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'GitHub OAuth client ID.',
          defaultValue: "{{ env.GITHUB_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'GitHub OAuth client secret.',
          defaultValue: "{{ env.GITHUB_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for GitHub callbacks.',
          defaultValue: "{{ env.GITHUB_REDIRECT_URI | default: '' }}",
        ),
        'enterprise_base_url': ConfigSchema.string(
          description: 'Optional GitHub Enterprise base URL.',
          defaultValue: "{{ env.GITHUB_ENTERPRISE_URL | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from GitHub.',
          items: ConfigSchema.string(),
          defaultValue: _defaultGitHubScopes,
        ),
      },
    ),
    builder: _buildGithubProvider,
  );
}

AuthProvider? _buildGithubProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.github.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) {
    return null;
  }
  final clientId = _requireString(
    config['client_id'],
    'auth.providers.github.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.github.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.github.redirect_uri',
  );
  final enterpriseBaseUrl = parseStringLike(
    config['enterprise_base_url'],
    context: 'auth.providers.github.enterprise_base_url',
    allowEmpty: true,
    throwOnInvalid: true,
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.github.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultGitHubScopes;
  return githubProvider(
    GitHubProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      enterpriseBaseUrl:
          enterpriseBaseUrl == null || enterpriseBaseUrl.trim().isEmpty
          ? null
          : enterpriseBaseUrl,
      scopes: scopes.isEmpty ? _defaultGitHubScopes : scopes,
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

void registerGitHubAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_githubRegistration(), overrideExisting: overrideExisting);
}

Future<List<GitHubEmail>> _loadGitHubEmails(
  OAuthTokenResponse token,
  http.Client httpClient,
  String apiBaseUrl,
) async {
  try {
    final response = await httpClient.get(
      Uri.parse('$apiBaseUrl/user/emails'),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${token.accessToken}',
        HttpHeaders.userAgentHeader: 'routed',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const <GitHubEmail>[];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const <GitHubEmail>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GitHubEmail.fromJson)
        .toList();
  } catch (_) {
    return const <GitHubEmail>[];
  }
}
