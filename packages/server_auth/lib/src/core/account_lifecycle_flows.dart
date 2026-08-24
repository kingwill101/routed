import 'dart:async';

import 'package:server_auth/src/core/account_deletion.dart';
import 'package:server_auth/src/core/account_linking.dart';
import 'package:server_auth/src/core/authentication_methods.dart';
import 'package:server_auth/src/core/email_change.dart';
import 'package:server_auth/src/core/password_hasher.dart';
import 'package:server_auth/src/core/providers.dart';
import 'package:server_auth/src/core/store.dart';

// Re-export types for convenience
export 'account_deletion.dart'
    show
        AuthAccountDeletionConfirmed,
        AuthAccountDeletionInitiated,
        AuthAccountDeletionRequest;
export 'account_linking.dart'
    show AuthAccountLinked, AuthAccountUnlinked, AuthLinkedAccountInfo;
export 'email_change.dart'
    show AuthEmailChangeConfirmed, AuthEmailChangeInitiated;

/// Initiates an email change flow.
Future<AuthEmailChangeInitiated> initiateEmailChangeFlow({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required String userId,
  required String currentPassword,
  required String newEmail,
}) async {
  return initiateEmailChange(
    store: store,
    passwordHasher: passwordHasher,
    userId: userId,
    currentPassword: currentPassword,
    newEmail: newEmail,
  );
}

/// Confirms an email change flow.
Future<AuthEmailChangeConfirmed> confirmEmailChangeFlow({
  required AuthStore store,
  required String tokenIdentifier,
  required String token,
  required String newEmail,
}) async {
  return confirmEmailChange(
    store: store,
    tokenIdentifier: tokenIdentifier,
    token: token,
    newEmail: newEmail,
  );
}

/// Initiates an account deletion flow.
Future<AuthAccountDeletionInitiated> initiateAccountDeletionFlow({
  required AuthStore store,
  required PasswordHasher passwordHasher,
  required String userId,
  required String password,
}) async {
  return initiateAccountDeletion(
    store: store,
    passwordHasher: passwordHasher,
    userId: userId,
    password: password,
  );
}

/// Confirms an account deletion flow.
Future<AuthAccountDeletionConfirmed> confirmAccountDeletionFlow({
  required AuthStore store,
  required String userId,
  required String token,
}) async {
  return confirmAccountDeletion(store: store, userId: userId, token: token);
}

/// Lists linked accounts flow.
Future<List<AuthLinkedAccountInfo>> listLinkedAccountsFlow({
  required AuthStore store,
  required List<AuthProvider> providers,
  required String userId,
}) async {
  return listLinkedAccounts(store: store, providers: providers, userId: userId);
}

/// Links a provider account flow.
Future<AuthAccountLinked> linkProviderAccountFlow({
  required AuthStore store,
  required String userId,
  required String providerId,
  required String providerAccountId,
  String? accessToken,
  String? refreshToken,
  DateTime? expiresAt,
  Map<String, dynamic>? metadata,
}) async {
  return linkProviderAccount(
    store: store,
    userId: userId,
    providerId: providerId,
    providerAccountId: providerAccountId,
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    metadata: metadata,
  );
}

/// Unlinks a provider account flow.
Future<AuthAccountUnlinked> unlinkProviderAccountFlow({
  required AuthStore store,
  required AuthAuthenticationMethodService authenticationMethods,
  required String userId,
  required String providerId,
  required String providerAccountId,
}) async {
  return unlinkProviderAccount(
    store: store,
    authenticationMethods: authenticationMethods,
    userId: userId,
    providerId: providerId,
    providerAccountId: providerAccountId,
  );
}
