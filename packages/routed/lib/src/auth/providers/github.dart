import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:routed/src/auth/models.dart';
import 'package:routed/src/auth/providers.dart';
import 'package:routed/src/context/context.dart';

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
    profileRequest: (ctx, provider, token, client, profile) async {
      if (profile.email != null && profile.email!.isNotEmpty) {
        return profile;
      }

      final emailProfile = await _fetchPrimaryEmail(
        ctx,
        client,
        apiBaseUrl,
        token.accessToken,
      );
      if (emailProfile == null) {
        return profile;
      }

      return GitHubProfile(
        login: profile.login,
        id: profile.id,
        nodeId: profile.nodeId,
        avatarUrl: profile.avatarUrl,
        gravatarId: profile.gravatarId,
        url: profile.url,
        htmlUrl: profile.htmlUrl,
        followersUrl: profile.followersUrl,
        followingUrl: profile.followingUrl,
        gistsUrl: profile.gistsUrl,
        starredUrl: profile.starredUrl,
        subscriptionsUrl: profile.subscriptionsUrl,
        organizationsUrl: profile.organizationsUrl,
        reposUrl: profile.reposUrl,
        eventsUrl: profile.eventsUrl,
        receivedEventsUrl: profile.receivedEventsUrl,
        type: profile.type,
        siteAdmin: profile.siteAdmin,
        name: profile.name,
        company: profile.company,
        blog: profile.blog,
        location: profile.location,
        email: emailProfile,
        hireable: profile.hireable,
        bio: profile.bio,
        twitterUsername: profile.twitterUsername,
        publicRepos: profile.publicRepos,
        publicGists: profile.publicGists,
        followers: profile.followers,
        following: profile.following,
        createdAt: profile.createdAt,
        updatedAt: profile.updatedAt,
        privateGists: profile.privateGists,
        totalPrivateRepos: profile.totalPrivateRepos,
        ownedPrivateRepos: profile.ownedPrivateRepos,
        diskUsage: profile.diskUsage,
        suspendedAt: profile.suspendedAt,
        collaborators: profile.collaborators,
        twoFactorAuthentication: profile.twoFactorAuthentication,
        plan: profile.plan,
      );
    },
  );
}

Future<String?> _fetchPrimaryEmail(
  EngineContext ctx,
  http.Client client,
  String apiBaseUrl,
  String accessToken,
) async {
  try {
    final response = await client.get(
      Uri.parse('$apiBaseUrl/user/emails'),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $accessToken',
        HttpHeaders.userAgentHeader: 'routed',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return null;
    }
    final emails = decoded
        .whereType<Map<String, dynamic>>()
        .map(GitHubEmail.fromJson)
        .toList();
    if (emails.isEmpty) {
      return null;
    }
    final primary = emails.firstWhere(
      (email) => email.primary,
      orElse: () => emails.first,
    );
    return primary.email;
  } catch (_) {
    return null;
  }
}
