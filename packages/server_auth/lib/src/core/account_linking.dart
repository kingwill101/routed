import 'dart:async';

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'models.dart';
import 'oauth.dart';
import 'providers.dart';
import 'store.dart';
import 'tokens.dart' show secureRandomToken;
import 'users.dart' show resolveAuthAccountId;

/// Information about a linked provider account.
class AuthLinkedAccountInfo {
  const AuthLinkedAccountInfo({
    required this.providerId,
    required this.providerAccountId,
    required this.linkedAt,
    this.email,
    this.name,
    this.image,
    this.displayName,
  });

  /// Provider identifier (e.g., 'github', 'google').
  final String providerId;

  /// Provider-specific account ID.
  final String providerAccountId;

  /// When the account was linked.
  final DateTime linkedAt;

  /// Email from the provider (if available).
  final String? email;

  /// Name from the provider (if available).
  final String? name;

  /// Image from the provider (if available).
  final String? image;

  /// Human-readable display name combining provider and identity.
  String get displayLabel => displayName ?? '$providerId · $providerAccountId';

  /// Optional override for the display label.
  final String? displayName;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'providerAccountId': providerAccountId,
    'linkedAt': linkedAt.toUtc().toIso8601String(),
    'email': email,
    'name': name,
    'image': image,
    'displayName': displayName,
  };
}

/// Result of linking a provider account.
class AuthAccountLinked {
  const AuthAccountLinked({
    required this.providerId,
    required this.providerAccountId,
    required this.linkedAt,
    required this.isNewLink,
  });

  /// Provider identifier.
  final String providerId;

  /// Provider-specific account ID.
  final String providerAccountId;

  /// When the account was linked.
  final DateTime linkedAt;

  /// Whether this was a new link (not already linked).
  final bool isNewLink;

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'providerAccountId': providerAccountId,
    'linkedAt': linkedAt.toUtc().toIso8601String(),
    'isNewLink': isNewLink,
  };
}

/// Result of unlinking a provider account.
class AuthAccountUnlinked {
  const AuthAccountUnlinked({
    required this.providerId,
    required this.providerAccountId,
    required this.unlinkedAt,
  });

  /// Provider identifier.
  final String providerId;

  /// Provider-specific account ID.
  final String providerAccountId;

  /// When the account was unlinked.
  final DateTime unlinkedAt;

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'providerAccountId': providerAccountId,
    'unlinkedAt': unlinkedAt.toUtc().toIso8601String(),
  };
}

/// Verifies ownership of a provider account using a provider-issued access
/// token before it is linked to the current local user.
Future<AuthAccount> verifyOAuthProviderAccount({
  required AuthProvider provider,
  required String accessToken,
  required String expectedProviderAccountId,
  required String userId,
  required Object context,
  required http.Client httpClient,
}) async {
  if (provider is! OAuthProvider) {
    throw AuthFlowException('provider_link_not_supported');
  }
  return _verifyOAuthProviderAccount<Object>(
    provider: provider,
    accessToken: accessToken,
    expectedProviderAccountId: expectedProviderAccountId,
    userId: userId,
    context: context,
    httpClient: httpClient,
  );
}

Future<AuthAccount> _verifyOAuthProviderAccount<TProfile extends Object>({
  required OAuthProvider<TProfile> provider,
  required String accessToken,
  required String expectedProviderAccountId,
  required String userId,
  required Object context,
  required http.Client httpClient,
}) async {
  if (accessToken.trim().isEmpty) {
    throw AuthFlowException('provider_access_token_required');
  }
  final token = OAuthTokenResponse(
    accessToken: accessToken,
    tokenType: 'Bearer',
    expiresIn: null,
    raw: const <String, dynamic>{},
  );
  final rawProfile = await loadOAuthProfile(
    provider,
    token: token,
    httpClient: httpClient,
  );
  final parsed = provider.parseProfile(rawProfile);
  final enriched = await Future.sync(
    () => provider.enrichProfile(context, token, httpClient, parsed),
  );
  final mappedUser = provider.mapProfile(enriched);
  final profile = provider.serializeProfile(enriched);
  final emailVerified =
      profile['verified'] == true || profile['email_verified'] == true;
  final accountId = resolveAuthAccountId(
    profile,
    mappedUser,
    fallbackId: secureRandomToken,
    emailVerified: emailVerified,
  );
  if (accountId != expectedProviderAccountId.trim()) {
    throw AuthFlowException('provider_account_mismatch');
  }
  return AuthAccount(
    providerId: provider.id,
    providerAccountId: accountId,
    userId: userId,
    accessToken: accessToken,
    expiresAt: oauthTokenExpiryFromSeconds(token.expiresIn),
    metadata: profile,
  );
}

/// Lists all linked provider accounts for a user.
///
/// Uses [store.accounts.listForUser] to find linked accounts, and
/// cross-references them with the configured [providers] to attach
/// metadata like display names. No provider IDs are hardcoded.
Future<List<AuthLinkedAccountInfo>> listLinkedAccounts({
  required AuthStore store,
  required List<AuthProvider> providers,
  required String userId,
}) async {
  final normalizedUserId = userId.trim();

  if (normalizedUserId.isEmpty) {
    throw AuthFlowException('invalid_request');
  }

  // Verify user exists
  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) {
    throw AuthFlowException('user_not_found');
  }

  // Ask the account store for all linked accounts
  final accounts = await Future.sync(
    () => store.accounts.listForUser(normalizedUserId),
  );

  // Build a lookup from configured providers
  final providerMap = <String, AuthProvider>{};
  for (final provider in providers) {
    providerMap[provider.id] = provider;
  }

  return accounts.map((account) {
    final provider = providerMap[account.providerId];
    final metadata = account.metadata;
    return AuthLinkedAccountInfo(
      providerId: account.providerId,
      providerAccountId: account.providerAccountId,
      linkedAt: _parseLinkedAt(metadata),
      email: metadata['email']?.toString(),
      name: metadata['name']?.toString(),
      image: metadata['picture']?.toString() ?? metadata['image']?.toString(),
      displayName: provider?.id,
    );
  }).toList();
}

/// Links a provider account to a user.
///
/// This is typically called after an OAuth flow completes and the user
/// wants to link the provider to their existing account.
Future<AuthAccountLinked> linkProviderAccount({
  required AuthStore store,
  required String userId,
  required String providerId,
  required String providerAccountId,
  String? accessToken,
  String? refreshToken,
  DateTime? expiresAt,
  Map<String, dynamic>? metadata,
  DateTime? now,
}) async {
  final normalizedUserId = userId.trim();
  final normalizedProviderId = providerId.trim();
  final normalizedProviderAccountId = providerAccountId.trim();

  if (normalizedUserId.isEmpty) {
    throw AuthFlowException('invalid_request');
  }
  if (normalizedProviderId.isEmpty) {
    throw AuthFlowException('invalid_provider');
  }
  if (normalizedProviderAccountId.isEmpty) {
    throw AuthFlowException('invalid_provider_account');
  }

  // Verify user exists
  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) {
    throw AuthFlowException('user_not_found');
  }

  // Check if this provider account is already linked to another user
  final existingAccount = await Future.sync(
    () =>
        store.accounts.find(normalizedProviderId, normalizedProviderAccountId),
  );

  if (existingAccount != null) {
    if (existingAccount.userId == normalizedUserId) {
      // Already linked to this user
      return AuthAccountLinked(
        providerId: normalizedProviderId,
        providerAccountId: normalizedProviderAccountId,
        linkedAt: _parseLinkedAt(existingAccount.metadata),
        isNewLink: false,
      );
    } else {
      // Linked to a different user
      throw AuthFlowException('provider_account_already_linked');
    }
  }

  // Create the account link
  final linkedAt = (now ?? DateTime.now()).toUtc();
  final account = AuthAccount(
    providerId: normalizedProviderId,
    providerAccountId: normalizedProviderAccountId,
    userId: normalizedUserId,
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    metadata: {...?metadata, 'linkedAt': linkedAt.toIso8601String()},
  );

  final canonical = await Future.sync(() => store.accounts.link(account));
  if (canonical.providerId != normalizedProviderId ||
      canonical.providerAccountId != normalizedProviderAccountId ||
      canonical.userId != normalizedUserId) {
    throw AuthFlowException('provider_account_already_linked');
  }

  return AuthAccountLinked(
    providerId: normalizedProviderId,
    providerAccountId: normalizedProviderAccountId,
    linkedAt: linkedAt,
    isNewLink: true,
  );
}

/// Unlinks a provider account from a user.
///
/// This removes the link between the provider and the user. The user
/// will no longer be able to sign in with that provider.
Future<AuthAccountUnlinked> unlinkProviderAccount({
  required AuthStore store,
  required String userId,
  required String providerId,
  required String providerAccountId,
  DateTime? now,
}) async {
  final normalizedUserId = userId.trim();
  final normalizedProviderId = providerId.trim();
  final normalizedProviderAccountId = providerAccountId.trim();

  if (normalizedUserId.isEmpty) {
    throw AuthFlowException('invalid_request');
  }
  if (normalizedProviderId.isEmpty) {
    throw AuthFlowException('invalid_provider');
  }
  if (normalizedProviderAccountId.isEmpty) {
    throw AuthFlowException('invalid_provider_account');
  }

  // Verify user exists
  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) {
    throw AuthFlowException('user_not_found');
  }

  // Find the existing account
  final existingAccount = await Future.sync(
    () =>
        store.accounts.find(normalizedProviderId, normalizedProviderAccountId),
  );

  if (existingAccount == null) {
    throw AuthFlowException('linked_account_not_found');
  }

  if (existingAccount.userId != normalizedUserId) {
    throw AuthFlowException('linked_account_not_found');
  }

  final credential = await findAuthCredentialForUser(store, normalizedUserId);
  final result = await Future.sync(
    () => store.accounts.unlinkForUserIfSafe(
      normalizedUserId,
      normalizedProviderId,
      normalizedProviderAccountId,
      hasEnabledPasswordCredential: credential?.enabled == true,
    ),
  );
  switch (result) {
    case AuthAccountUnlinkResult.unlinked:
      break;
    case AuthAccountUnlinkResult.notFound:
      throw AuthFlowException('linked_account_not_found');
    case AuthAccountUnlinkResult.lastAuthenticationMethod:
      throw AuthFlowException('last_authentication_method');
  }

  return AuthAccountUnlinked(
    providerId: normalizedProviderId,
    providerAccountId: normalizedProviderAccountId,
    unlinkedAt: (now ?? DateTime.now()).toUtc(),
  );
}

/// Safety check: determines if a provider account can be unlinked.
///
/// Returns `true` if unlinking would leave the user with no authentication
/// methods. This should be checked before allowing unlinking.
Future<bool> canUnlinkProvider({
  required AuthStore store,
  required String userId,
  required String providerId,
  String? providerAccountId,
}) async {
  final normalizedUserId = userId.trim();

  // Check if user has a password credential
  final user = await Future.sync(() => store.users.findById(normalizedUserId));
  if (user == null) return false;

  final hasPassword = await findAuthCredentialForUser(store, normalizedUserId);

  if (hasPassword != null && hasPassword.enabled) {
    // User has a password, can unlink any provider
    return true;
  }

  // User only has OAuth, check if they have other linked providers
  final linkedAccounts = await Future.sync(
    () => store.accounts.listForUser(normalizedUserId),
  );

  // Count active links, excluding only the exact account being unlinked.
  final otherLinks = linkedAccounts
      .where(
        (account) =>
            account.userId == normalizedUserId &&
            (account.providerId != providerId ||
                account.providerAccountId != providerAccountId),
      )
      .length;

  return otherLinks > 0;
}

DateTime _parseLinkedAt(Map<String, dynamic> metadata) {
  final raw = metadata['linkedAt']?.toString();
  if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
  return DateTime.tryParse(raw)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
