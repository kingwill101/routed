import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:server_auth/src/core/core.dart';

/// GitHub email payload returned by `/user/emails`.
class GitHubEmail {
  /// Creates an email record returned by GitHub.
  GitHubEmail({
    required this.email,
    required this.primary,
    required this.verified,
    required this.visibility,
  });

  /// Creates an email record from a GitHub API response.
  factory GitHubEmail.fromJson(Map<String, dynamic> json) {
    return GitHubEmail(
      email: json['email']?.toString() ?? '',
      primary: json['primary'] == true,
      verified: json['verified'] == true,
      visibility: json['visibility']?.toString() ?? 'private',
    );
  }

  /// Email address reported by GitHub.
  final String email;

  /// Whether GitHub marks this address as the account's primary address.
  final bool primary;

  /// Whether GitHub has verified this address.
  final bool verified;

  /// Visibility setting reported by GitHub.
  final String visibility;
}

/// GitHub user plan information.
class GitHubPlan {
  /// Creates plan information returned by GitHub.
  const GitHubPlan({
    required this.collaborators,
    required this.name,
    required this.space,
    required this.privateRepos,
  });

  /// Creates plan information from a GitHub API response.
  factory GitHubPlan.fromJson(Map<String, dynamic> json) {
    return GitHubPlan(
      collaborators: json['collaborators'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      space: json['space'] as int? ?? 0,
      privateRepos: json['private_repos'] as int? ?? 0,
    );
  }

  /// Number of collaborators included in the plan.
  final int collaborators;

  /// GitHub plan name.
  final String name;

  /// Storage space included in the plan, as reported by GitHub.
  final int space;

  /// Number of private repositories included in the plan.
  final int privateRepos;

  /// Serializes this plan using GitHub's response field names.
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
  /// Creates a profile returned by GitHub's authenticated-user endpoint.
  const GitHubProfile({
    required this.login,
    required this.id,
    required this.nodeId,
    required this.avatarUrl,
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
    required this.publicRepos,
    required this.publicGists,
    required this.followers,
    required this.following,
    required this.createdAt,
    required this.updatedAt,
    required this.twoFactorAuthentication,
    this.gravatarId,
    this.name,
    this.company,
    this.blog,
    this.location,
    this.email,
    this.hireable,
    this.bio,
    this.twitterUsername,
    this.privateGists,
    this.totalPrivateRepos,
    this.ownedPrivateRepos,
    this.diskUsage,
    this.suspendedAt,
    this.collaborators,
    this.plan,
  });

  /// Creates a profile from a GitHub API response.
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

  /// GitHub login name.
  final String login;

  /// Numeric GitHub account identifier.
  final int id;

  /// GraphQL node identifier for the account.
  final String nodeId;

  /// URL of the account avatar.
  final String avatarUrl;

  /// Legacy Gravatar identifier, when supplied by GitHub.
  final String? gravatarId;

  /// API URL for the account.
  final String url;

  /// Web URL for the account profile.
  final String htmlUrl;

  /// API URL for the account's followers.
  final String followersUrl;

  /// API URL for accounts followed by this user.
  final String followingUrl;

  /// API URL for the account's gists.
  final String gistsUrl;

  /// API URL for repositories starred by the account.
  final String starredUrl;

  /// API URL for the account's subscriptions.
  final String subscriptionsUrl;

  /// API URL for organizations owned by the account.
  final String organizationsUrl;

  /// API URL for repositories owned by the account.
  final String reposUrl;

  /// API URL for events performed by the account.
  final String eventsUrl;

  /// API URL for events received by the account.
  final String receivedEventsUrl;

  /// GitHub account type, such as `User` or `Organization`.
  final String type;

  /// Whether the account is a GitHub site administrator.
  final bool siteAdmin;

  /// Display name supplied by GitHub.
  final String? name;

  /// Company supplied by the account owner.
  final String? company;

  /// Personal blog URL or text supplied by the account owner.
  final String? blog;

  /// Location supplied by the account owner.
  final String? location;

  /// Public email supplied by GitHub, when available.
  final String? email;

  /// Whether the account owner is available for hire.
  final bool? hireable;

  /// Profile biography supplied by the account owner.
  final String? bio;

  /// Twitter username supplied by the account owner.
  final String? twitterUsername;

  /// Number of public repositories owned by the account.
  final int publicRepos;

  /// Number of public gists owned by the account.
  final int publicGists;

  /// Number of followers of the account.
  final int followers;

  /// Number of accounts followed by the user.
  final int following;

  /// Account creation timestamp as returned by GitHub.
  final String createdAt;

  /// Timestamp of the most recent profile update as returned by GitHub.
  final String updatedAt;

  /// Number of private gists, when GitHub supplies it.
  final int? privateGists;

  /// Number of private repositories visible to the account.
  final int? totalPrivateRepos;

  /// Number of private repositories owned by the account.
  final int? ownedPrivateRepos;

  /// Disk usage reported for the account.
  final int? diskUsage;

  /// Suspension timestamp, when the account is suspended.
  final String? suspendedAt;

  /// Number of collaborators reported for the account.
  final int? collaborators;

  /// Whether two-factor authentication is enabled for the account.
  final bool twoFactorAuthentication;

  /// Billing plan information, when GitHub supplies it.
  final GitHubPlan? plan;

  /// Serializes this profile using GitHub's response field names.
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

  /// Returns a copy with an optionally replaced email address.
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
/// import 'package:server_auth/server_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     store: InMemoryAuthStore(),
///     storeMode: AuthStoreMode.ephemeral,
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
  /// Creates configuration for the GitHub OAuth provider.
  const GitHubProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.enterpriseBaseUrl,
    this.scopes = const ['read:user', 'user:email'],
  });

  /// OAuth application client identifier.
  final String clientId;

  /// OAuth application client secret.
  final String clientSecret;

  /// Callback URI registered with the GitHub OAuth application.
  final String redirectUri;

  /// GitHub Enterprise Server origin, when using an enterprise deployment.
  final String? enterpriseBaseUrl;

  /// OAuth scopes requested during authorization.
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
    userInfoRequest: _loadGitHubUserInfo,
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
    profileRequest: (_, provider, token, httpClient, profile) async {
      if (profile.email != null && profile.email!.isNotEmpty) {
        return profile;
      }
      final emails = await _loadGitHubEmails(
        token,
        httpClient,
        apiBaseUrl,
        requestTimeout: provider.requestTimeout,
      );
      if (emails.isEmpty) return profile;
      final primary = emails.firstWhere(
        (entry) => entry.primary && entry.verified,
        orElse: () => emails.first,
      );
      return profile.copyWith(email: primary.email);
    },
  );
}

Future<Map<String, dynamic>> _loadGitHubUserInfo(
  OAuthTokenResponse token,
  http.Client httpClient,
  Uri endpoint,
) async {
  final response = await httpClient.get(
    endpoint,
    headers: {
      'Authorization': 'Bearer ${token.accessToken}',
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'server_auth',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw OAuth2Exception(
      'GitHub user-info endpoint responded with ${response.statusCode}',
      response.statusCode,
    );
  }
  if (response.body.length > maxOAuthResponseCharacters) {
    throw OAuth2Exception('invalid_userinfo_response');
  }
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('expected JSON object');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } catch (_) {
    throw OAuth2Exception('invalid_userinfo_response');
  }
}

Future<List<GitHubEmail>> _loadGitHubEmails(
  OAuthTokenResponse token,
  http.Client httpClient,
  String apiBaseUrl, {
  required Duration requestTimeout,
}) async {
  try {
    final response = await httpClient
        .get(
          Uri.parse('$apiBaseUrl/user/emails'),
          headers: {
            'Authorization': 'Bearer ${token.accessToken}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'server_auth',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const <GitHubEmail>[];
    }
    if (response.body.length > maxOAuthResponseCharacters) {
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
