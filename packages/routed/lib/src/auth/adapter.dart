import 'dart:async';

import 'package:routed/src/auth/models.dart';

/// Base adapter for persisting auth data.
///
/// Override methods to integrate with your datastore. The default
/// implementation is a no-op in-memory placeholder.
class AuthAdapter {
  const AuthAdapter();

  /// Looks up a user by identifier.
  FutureOr<AuthUser?> getUserById(String id) => null;

  /// Looks up a user by email address.
  FutureOr<AuthUser?> getUserByEmail(String email) => null;

  /// Persists a new user.
  FutureOr<AuthUser> createUser(AuthUser user) => user;

  /// Updates a user record.
  FutureOr<AuthUser?> updateUser(AuthUser user) => user;

  /// Verifies credential sign-in against your datastore.
  FutureOr<AuthUser?> verifyCredentials(AuthCredentials credentials) => null;

  /// Registers a new user from credential input.
  FutureOr<AuthUser?> registerCredentials(AuthCredentials credentials) => null;

  /// Loads a provider account link.
  FutureOr<AuthAccount?> getAccount(
    String providerId,
    String providerAccountId,
  ) => null;

  /// Links a provider account to a user.
  FutureOr<void> linkAccount(AuthAccount account) {}

  /// Loads a session for server-side sessions.
  FutureOr<AuthSession?> getSession(String sessionToken) => null;

  /// Persists a server-side session.
  FutureOr<AuthSession> createSession(AuthSession session) => session;

  /// Deletes a session by token.
  FutureOr<void> deleteSession(String sessionToken) {}

  /// Saves an email verification token.
  FutureOr<void> saveVerificationToken(AuthVerificationToken token) {}

  /// Consumes an email verification token.
  FutureOr<AuthVerificationToken?> useVerificationToken(
    String identifier,
    String token,
  ) => null;

  /// Deletes verification tokens for an identifier.
  FutureOr<void> deleteVerificationTokens(String identifier) {}
}

/// Adapter implementation backed by callbacks.
class CallbackAuthAdapter extends AuthAdapter {
  CallbackAuthAdapter({
    this.onGetUserById,
    this.onGetUserByEmail,
    this.onCreateUser,
    this.onUpdateUser,
    this.onVerifyCredentials,
    this.onRegisterCredentials,
    this.onGetAccount,
    this.onLinkAccount,
    this.onGetSession,
    this.onCreateSession,
    this.onDeleteSession,
    this.onSaveVerificationToken,
    this.onUseVerificationToken,
    this.onDeleteVerificationTokens,
  });

  final FutureOr<AuthUser?> Function(String id)? onGetUserById;
  final FutureOr<AuthUser?> Function(String email)? onGetUserByEmail;
  final FutureOr<AuthUser> Function(AuthUser user)? onCreateUser;
  final FutureOr<AuthUser?> Function(AuthUser user)? onUpdateUser;
  final FutureOr<AuthUser?> Function(AuthCredentials credentials)?
  onVerifyCredentials;
  final FutureOr<AuthUser?> Function(AuthCredentials credentials)?
  onRegisterCredentials;
  final FutureOr<AuthAccount?> Function(
    String providerId,
    String providerAccountId,
  )?
  onGetAccount;
  final FutureOr<void> Function(AuthAccount account)? onLinkAccount;
  final FutureOr<AuthSession?> Function(String sessionToken)? onGetSession;
  final FutureOr<AuthSession> Function(AuthSession session)? onCreateSession;
  final FutureOr<void> Function(String sessionToken)? onDeleteSession;
  final FutureOr<void> Function(AuthVerificationToken token)?
  onSaveVerificationToken;
  final FutureOr<AuthVerificationToken?> Function(
    String identifier,
    String token,
  )?
  onUseVerificationToken;
  final FutureOr<void> Function(String identifier)? onDeleteVerificationTokens;

  @override
  FutureOr<AuthUser?> getUserById(String id) {
    return onGetUserById?.call(id);
  }

  @override
  FutureOr<AuthUser?> getUserByEmail(String email) {
    return onGetUserByEmail?.call(email);
  }

  @override
  FutureOr<AuthUser> createUser(AuthUser user) {
    return onCreateUser?.call(user) ?? user;
  }

  @override
  FutureOr<AuthUser?> updateUser(AuthUser user) {
    return onUpdateUser?.call(user) ?? user;
  }

  @override
  FutureOr<AuthUser?> verifyCredentials(AuthCredentials credentials) {
    return onVerifyCredentials?.call(credentials);
  }

  @override
  FutureOr<AuthUser?> registerCredentials(AuthCredentials credentials) {
    return onRegisterCredentials?.call(credentials);
  }

  @override
  FutureOr<AuthAccount?> getAccount(
    String providerId,
    String providerAccountId,
  ) {
    return onGetAccount?.call(providerId, providerAccountId);
  }

  @override
  FutureOr<void> linkAccount(AuthAccount account) {
    return onLinkAccount?.call(account);
  }

  @override
  FutureOr<AuthSession?> getSession(String sessionToken) {
    return onGetSession?.call(sessionToken);
  }

  @override
  FutureOr<AuthSession> createSession(AuthSession session) {
    return onCreateSession?.call(session) ?? session;
  }

  @override
  FutureOr<void> deleteSession(String sessionToken) {
    return onDeleteSession?.call(sessionToken);
  }

  @override
  FutureOr<void> saveVerificationToken(AuthVerificationToken token) {
    return onSaveVerificationToken?.call(token);
  }

  @override
  FutureOr<AuthVerificationToken?> useVerificationToken(
    String identifier,
    String token,
  ) {
    return onUseVerificationToken?.call(identifier, token);
  }

  @override
  FutureOr<void> deleteVerificationTokens(String identifier) {
    return onDeleteVerificationTokens?.call(identifier);
  }
}

/// In-memory adapter for testing and prototypes.
class InMemoryAuthAdapter extends AuthAdapter {
  final Map<String, AuthUser> _usersById = <String, AuthUser>{};
  final Map<String, AuthUser> _usersByEmail = <String, AuthUser>{};
  final Map<String, AuthAccount> _accounts = <String, AuthAccount>{};
  final Map<String, AuthSession> _sessions = <String, AuthSession>{};
  final Map<String, AuthVerificationToken> _tokens =
      <String, AuthVerificationToken>{};

  @override
  Future<AuthUser?> getUserById(String id) async => _usersById[id];

  @override
  Future<AuthUser?> getUserByEmail(String email) async => _usersByEmail[email];

  @override
  Future<AuthUser?> verifyCredentials(AuthCredentials credentials) async {
    final identifier = credentials.email ?? credentials.username;
    if (identifier == null || identifier.isEmpty) {
      return null;
    }
    final user = _usersByEmail[identifier] ?? _usersById[identifier];
    if (user == null) {
      return null;
    }
    final storedPassword = user.attributes['password']?.toString();
    if (storedPassword == null) {
      return null;
    }
    if (credentials.password == storedPassword) {
      return user;
    }
    return null;
  }

  @override
  Future<AuthUser?> registerCredentials(AuthCredentials credentials) async {
    final identifier = credentials.email ?? credentials.username;
    final password = credentials.password;
    if (identifier == null || identifier.isEmpty || password == null) {
      return null;
    }
    if (_usersByEmail.containsKey(identifier) ||
        _usersById.containsKey(identifier)) {
      return null;
    }

    final user = AuthUser(
      id: identifier,
      email: credentials.email,
      name: credentials.username ?? credentials.email,
      attributes: {'password': password},
    );
    return createUser(user);
  }

  @override
  Future<AuthUser> createUser(AuthUser user) async {
    _usersById[user.id] = user;
    if (user.email != null) {
      _usersByEmail[user.email!] = user;
    }
    return user;
  }

  @override
  Future<AuthUser?> updateUser(AuthUser user) async {
    _usersById[user.id] = user;
    if (user.email != null) {
      _usersByEmail[user.email!] = user;
    }
    return user;
  }

  @override
  Future<AuthAccount?> getAccount(
    String providerId,
    String providerAccountId,
  ) async {
    return _accounts['$providerId::$providerAccountId'];
  }

  @override
  Future<void> linkAccount(AuthAccount account) async {
    _accounts['${account.providerId}::${account.providerAccountId}'] = account;
  }

  @override
  Future<AuthSession?> getSession(String sessionToken) async {
    return _sessions[sessionToken];
  }

  @override
  Future<AuthSession> createSession(AuthSession session) async {
    final token = session.token ?? session.user.id;
    _sessions[token] = session;
    return session;
  }

  @override
  Future<void> deleteSession(String sessionToken) async {
    _sessions.remove(sessionToken);
  }

  @override
  Future<void> saveVerificationToken(AuthVerificationToken token) async {
    _tokens['${token.identifier}::${token.token}'] = token;
  }

  @override
  Future<AuthVerificationToken?> useVerificationToken(
    String identifier,
    String token,
  ) async {
    final key = '$identifier::$token';
    final record = _tokens.remove(key);
    if (record == null) return null;
    if (DateTime.now().isAfter(record.expiresAt)) {
      return null;
    }
    return record;
  }

  @override
  Future<void> deleteVerificationTokens(String identifier) async {
    _tokens.removeWhere((key, _) => key.startsWith('$identifier::'));
  }
}
