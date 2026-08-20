import 'dart:async';

import 'deletion_transaction.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

import 'tokens.dart' show hashOpaqueToken;

/// A short-lived OAuth authorization code with its protocol bindings.
///
/// [codeHash] is the only code representation accepted by this persistence
/// model. The raw authorization code exists only in the response that starts
/// an authorization transaction and is hashed before [create] is called.
final class AuthOAuthAuthorizationCode {
  const AuthOAuthAuthorizationCode({
    required this.id,
    required this.codeHash,
    required this.clientId,
    required this.userId,
    required this.redirectUri,
    required this.scopes,
    required this.codeChallenge,
    required this.codeChallengeMethod,
    required this.createdAt,
    required this.expiresAt,
    this.nonce,
    this.resource,
  });

  final String id;
  final String codeHash;
  final String clientId;
  final String userId;
  final Uri redirectUri;
  final List<String> scopes;
  final String codeChallenge;
  final String codeChallengeMethod;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? nonce;
  final Uri? resource;

  bool isActive({DateTime? now}) =>
      (now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());

  /// Serializes persistence-safe data without a raw authorization code.
  Map<String, dynamic> toStorageJson() => <String, dynamic>{
    'id': id,
    'code_hash': codeHash,
    'client_id': clientId,
    'user_id': userId,
    'redirect_uri': redirectUri.toString(),
    'scopes': scopes,
    'code_challenge': codeChallenge,
    'code_challenge_method': codeChallengeMethod,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    if (nonce != null) 'nonce': nonce,
    if (resource != null) 'resource': resource.toString(),
  };
}

/// Persistence boundary for OAuth authorization codes.
abstract interface class AuthOAuthAuthorizationCodeStore {
  /// Creates a code and rejects duplicate code hashes.
  FutureOr<AuthOAuthAuthorizationCode> create(
    AuthOAuthAuthorizationCode authorizationCode,
  );

  /// Atomically consumes a code after validating all protocol bindings.
  ///
  /// A matching code is invalidated even when the verifier is wrong. This
  /// prevents an attacker from retrying a captured authorization code and
  /// means persistent implementations must perform the binding checks and
  /// delete in one transaction or compare-and-delete operation.
  FutureOr<AuthOAuthAuthorizationCode?> consume({
    required String codeHash,
    required String clientId,
    required Uri redirectUri,
    required String codeVerifier,
    DateTime? now,
  });

  /// Deletes codes owned by a user during account deletion.
  FutureOr<void> deleteForUser(String userId);
}

/// Framework-agnostic helper for issuing and exchanging authorization codes.
final class AuthOAuthAuthorizationCodeService {
  const AuthOAuthAuthorizationCodeService({
    required this.store,
    this.codeLifetime = const Duration(minutes: 1),
  }) : assert(codeLifetime > Duration.zero);

  final AuthOAuthAuthorizationCodeStore store;
  final Duration codeLifetime;

  Future<AuthOAuthAuthorizationCode> issue({
    required String rawCode,
    required String clientId,
    required String userId,
    required Uri redirectUri,
    required Iterable<String> scopes,
    required String codeChallenge,
    required String codeChallengeMethod,
    DateTime? now,
    String? nonce,
    Uri? resource,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final normalizedCode = _required(rawCode, 'rawCode');
    final normalizedClient = _required(clientId, 'clientId');
    final normalizedUser = _required(userId, 'userId');
    final normalizedChallenge = _required(codeChallenge, 'codeChallenge');
    if (codeChallengeMethod != 'S256') {
      throw ArgumentError.value(
        codeChallengeMethod,
        'codeChallengeMethod',
        'only S256 is supported',
      );
    }
    if (!redirectUri.isAbsolute || redirectUri.fragment.isNotEmpty) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'must be absolute and fragment-free',
      );
    }
    final record = AuthOAuthAuthorizationCode(
      id: hashOpaqueToken('$normalizedClient:$normalizedCode'),
      codeHash: hashOpaqueToken(normalizedCode),
      clientId: normalizedClient,
      userId: normalizedUser,
      redirectUri: redirectUri,
      scopes: _scopes(scopes),
      codeChallenge: normalizedChallenge,
      codeChallengeMethod: codeChallengeMethod,
      createdAt: current,
      expiresAt: current.add(codeLifetime),
      nonce: _optional(nonce),
      resource: resource,
    );
    return store.create(record);
  }

  Future<AuthOAuthAuthorizationCode?> exchange({
    required String rawCode,
    required String clientId,
    required Uri redirectUri,
    required String codeVerifier,
    DateTime? now,
  }) {
    return Future.sync(
      () => store.consume(
        codeHash: hashOpaqueToken(rawCode),
        clientId: clientId,
        redirectUri: redirectUri,
        codeVerifier: codeVerifier,
        now: now,
      ),
    );
  }
}

/// In-memory authorization-code store for tests and local development.
final class InMemoryAuthOAuthAuthorizationCodeStore
    implements
        AuthOAuthAuthorizationCodeStore,
        AuthInMemoryTransactionParticipant {
  InMemoryAuthOAuthAuthorizationCodeStore({this.maxEntries = 1024})
    : assert(maxEntries > 0);

  final int maxEntries;
  final Map<String, AuthOAuthAuthorizationCode> _records =
      <String, AuthOAuthAuthorizationCode>{};

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, AuthOAuthAuthorizationCode>.of(_records);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
    final records = checkpoint as Map<String, AuthOAuthAuthorizationCode>;
    _records
      ..clear()
      ..addAll(records);
  }

  @override
  Future<AuthOAuthAuthorizationCode> create(
    AuthOAuthAuthorizationCode authorizationCode,
  ) async {
    _validate(authorizationCode);
    final now = DateTime.now().toUtc();
    _records.removeWhere((_, record) => !record.isActive(now: now));
    if (_records.containsKey(authorizationCode.codeHash)) {
      throw StateError('OAuth authorization code already exists');
    }
    while (_records.length >= maxEntries) {
      _records.remove(_records.keys.first);
    }
    _records[authorizationCode.codeHash] = authorizationCode;
    return authorizationCode;
  }

  @override
  Future<AuthOAuthAuthorizationCode?> consume({
    required String codeHash,
    required String clientId,
    required Uri redirectUri,
    required String codeVerifier,
    DateTime? now,
  }) async {
    final record = _records.remove(codeHash.trim());
    if (record == null || !record.isActive(now: now)) return null;
    if (record.clientId != clientId || record.redirectUri != redirectUri) {
      return null;
    }
    if (!_verifyPkce(record, codeVerifier)) return null;
    return record;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    _records.removeWhere((_, record) => record.userId == userId);
  }

  static void _validate(AuthOAuthAuthorizationCode code) {
    if (code.id.trim().isEmpty ||
        code.codeHash.trim().isEmpty ||
        code.clientId.trim().isEmpty ||
        code.userId.trim().isEmpty ||
        code.codeChallenge.trim().isEmpty ||
        code.codeChallengeMethod != 'S256') {
      throw ArgumentError('Invalid OAuth authorization code');
    }
    if (!code.redirectUri.isAbsolute || code.redirectUri.fragment.isNotEmpty) {
      throw ArgumentError(
        'OAuth redirect URI must be absolute and fragment-free',
      );
    }
    if (!code.expiresAt.toUtc().isAfter(code.createdAt.toUtc())) {
      throw ArgumentError('OAuth authorization code must not be expired');
    }
  }
}

bool _verifyPkce(AuthOAuthAuthorizationCode code, String verifier) {
  if (verifier.isEmpty) return false;
  final digest = sha256.convert(utf8.encode(verifier));
  final expected = base64Url.encode(digest.bytes).replaceAll('=', '');
  return _constantTimeEquals(expected, code.codeChallenge);
}

String _required(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}

String? _optional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

List<String> _scopes(Iterable<String> values) => List<String>.unmodifiable(
  values.map((value) => value.trim()).where((value) => value.isNotEmpty),
);

bool _constantTimeEquals(String left, String right) {
  var difference = left.length ^ right.length;
  final length = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
