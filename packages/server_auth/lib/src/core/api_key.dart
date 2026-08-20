import 'dart:async';

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'rate_limit.dart';
import 'tokens.dart'
    show constantTimeStringEquals, hashOpaqueToken, secureRandomToken;

const String authApiKeyPluginId = 'api_key';

typedef AuthApiKeyTokenGenerator = String Function({int length});

/// The persisted representation of an API key.
///
/// [secretHash] is the digest of the client-held key. The raw API key is never
/// persisted and is only returned by [AuthApiKeyIssued] at creation or
/// rotation time.
final class AuthApiKeyRecord {
  AuthApiKeyRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.keyPrefix,
    required this.secretHash,
    required this.scopes,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String keyPrefix;
  final String secretHash;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  bool isActive({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return revokedAt == null &&
        (expiresAt == null || current.isBefore(expiresAt!.toUtc()));
  }

  AuthApiKeyRecord copyWith({
    String? id,
    String? userId,
    String? name,
    String? keyPrefix,
    String? secretHash,
    List<String>? scopes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
    bool clearExpiresAt = false,
    bool clearLastUsedAt = false,
    bool clearRevokedAt = false,
  }) {
    return AuthApiKeyRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      keyPrefix: keyPrefix ?? this.keyPrefix,
      secretHash: secretHash ?? this.secretHash,
      scopes: scopes ?? this.scopes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: clearExpiresAt ? null : expiresAt ?? this.expiresAt,
      lastUsedAt: clearLastUsedAt ? null : lastUsedAt ?? this.lastUsedAt,
      revokedAt: clearRevokedAt ? null : revokedAt ?? this.revokedAt,
    );
  }

  /// Serializes persistence fields, including the non-reversible secret hash.
  ///
  /// This method is for storage adapters only. Use [toJson] for public
  /// responses.
  Map<String, dynamic> toStorageJson() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'key_prefix': keyPrefix,
    'secret_hash': secretHash,
    'scopes': scopes,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'last_used_at': lastUsedAt?.toUtc().toIso8601String(),
    'revoked_at': revokedAt?.toUtc().toIso8601String(),
  };

  /// Returns the safe public projection of this key.
  AuthApiKey toPublic({DateTime? now}) => AuthApiKey(
    id: id,
    userId: userId,
    name: name,
    keyPrefix: keyPrefix,
    scopes: scopes,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
    lastUsedAt: lastUsedAt,
    revokedAt: revokedAt,
    active: isActive(now: now),
  );
}

/// Public API-key metadata. It never contains the secret or its hash.
final class AuthApiKey {
  const AuthApiKey({
    required this.id,
    required this.userId,
    required this.name,
    required this.keyPrefix,
    required this.scopes,
    required this.createdAt,
    required this.updatedAt,
    required this.active,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String keyPrefix;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;
  final bool active;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'keyPrefix': keyPrefix,
    'scopes': scopes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt?.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
    'active': active,
  };
}

/// The only response that contains a raw API key.
final class AuthApiKeyIssued {
  const AuthApiKeyIssued({required this.apiKey, required this.key});

  final AuthApiKey apiKey;
  final String key;

  Map<String, dynamic> toJson() => {'apiKey': key, ...apiKey.toJson()};
}

/// Successful verification result returned to framework adapters.
final class AuthApiKeyAuthentication {
  const AuthApiKeyAuthentication(this.record);

  final AuthApiKeyRecord record;

  List<String> get scopes => record.scopes;

  /// Returns whether this key grants [scope]. A wildcard grants every scope.
  bool allowsScope(String scope) {
    final requested = scope.trim().toLowerCase();
    return record.scopes.any((value) => value == '*' || value == requested);
  }
}

/// Persistence contract for API keys.
abstract interface class AuthApiKeyStore {
  /// Creates a key. Implementations must enforce unique key IDs atomically.
  FutureOr<AuthApiKeyRecord> create(AuthApiKeyRecord record);

  FutureOr<AuthApiKeyRecord?> findById(String id);

  FutureOr<List<AuthApiKeyRecord>> listForUser(String userId);

  /// Touches an active key and returns the updated record atomically.
  ///
  /// Revoked or expired keys must return `null` and must not be touched.
  FutureOr<AuthApiKeyRecord?> touchIfActive(String id, DateTime lastUsedAt);

  /// Revokes a key only when it belongs to [userId].
  FutureOr<AuthApiKeyRecord?> revokeForUser(
    String userId,
    String id, {
    DateTime? revokedAt,
  });

  /// Atomically revokes the old key and creates [replacement].
  FutureOr<AuthApiKeyRecord?> rotateForUser({
    required String userId,
    required String id,
    required AuthApiKeyRecord replacement,
    DateTime? revokedAt,
  });

  /// Removes every API key owned by [userId] as part of account deletion.
  ///
  /// Durable implementations must execute this operation in the same
  /// deletion transaction as the rest of the user's auth data.
  FutureOr<void> deleteForUser(String userId);
}

/// Optional atomic capability for revoking all API keys owned by one user.
abstract interface class AuthApiKeyUserAccessRevocationStore {
  FutureOr<int> revokeAllForUser(String userId, {DateTime? revokedAt});
}

/// Bounded in-memory API-key store for tests and local development.
final class InMemoryAuthApiKeyStore
    implements
        AuthApiKeyStore,
        AuthApiKeyUserAccessRevocationStore,
        AuthInMemoryTransactionParticipant {
  InMemoryAuthApiKeyStore({this.maxRecords = 10000}) {
    if (maxRecords <= 0) {
      throw ArgumentError.value(
        maxRecords,
        'maxRecords',
        'must be greater than zero',
      );
    }
  }

  final int maxRecords;
  final Map<String, AuthApiKeyRecord> _records = <String, AuthApiKeyRecord>{};

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, AuthApiKeyRecord>.of(_records);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
    final records = checkpoint as Map<String, AuthApiKeyRecord>;
    _records
      ..clear()
      ..addAll(records);
  }

  @override
  Future<AuthApiKeyRecord> create(AuthApiKeyRecord record) async {
    _validateRecord(record);
    _prune(DateTime.now().toUtc());
    if (_records.length >= maxRecords || _records.containsKey(record.id)) {
      throw StateError('API key storage capacity or key ID is exhausted.');
    }
    _records[record.id] = record;
    return record;
  }

  @override
  Future<AuthApiKeyRecord?> findById(String id) async => _records[id.trim()];

  @override
  Future<List<AuthApiKeyRecord>> listForUser(String userId) async {
    return _records.values
        .where((record) => record.userId == userId)
        .toList(growable: false);
  }

  @override
  Future<AuthApiKeyRecord?> touchIfActive(
    String id,
    DateTime lastUsedAt,
  ) async {
    final current = _records[id.trim()];
    final now = lastUsedAt.toUtc();
    if (current == null || !current.isActive(now: now)) return null;
    final touched = current.copyWith(lastUsedAt: now, updatedAt: now);
    _records[current.id] = touched;
    return touched;
  }

  @override
  Future<AuthApiKeyRecord?> revokeForUser(
    String userId,
    String id, {
    DateTime? revokedAt,
  }) async {
    final current = _records[id.trim()];
    if (current == null || current.userId != userId) return null;
    final revokedAtUtc = (revokedAt ?? DateTime.now()).toUtc();
    final revoked = current.copyWith(
      revokedAt: revokedAtUtc,
      updatedAt: revokedAtUtc,
    );
    _records[current.id] = revoked;
    return revoked;
  }

  @override
  Future<int> revokeAllForUser(String userId, {DateTime? revokedAt}) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return 0;
    final revokedAtUtc = (revokedAt ?? DateTime.now()).toUtc();
    var count = 0;
    for (final entry in _records.entries.toList(growable: false)) {
      final record = entry.value;
      if (record.userId != normalizedUserId || record.revokedAt != null) {
        continue;
      }
      _records[entry.key] = record.copyWith(
        revokedAt: revokedAtUtc,
        updatedAt: revokedAtUtc,
      );
      count += 1;
    }
    return count;
  }

  @override
  Future<AuthApiKeyRecord?> rotateForUser({
    required String userId,
    required String id,
    required AuthApiKeyRecord replacement,
    DateTime? revokedAt,
  }) async {
    final current = _records[id.trim()];
    final now = (revokedAt ?? DateTime.now()).toUtc();
    if (current == null ||
        current.userId != userId ||
        !current.isActive(now: now) ||
        _records.containsKey(replacement.id)) {
      return null;
    }
    _validateRecord(replacement);
    _prune(now);
    if (_records.length < maxRecords) {
      _records[current.id] = current.copyWith(revokedAt: now, updatedAt: now);
    } else {
      _records.remove(current.id);
    }
    _records[replacement.id] = replacement;
    return replacement;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    _records.removeWhere((_, record) => record.userId == normalizedUserId);
  }

  void _prune(DateTime now) {
    _records.removeWhere(
      (_, record) =>
          record.revokedAt != null ||
          (record.expiresAt != null && !now.isBefore(record.expiresAt!)),
    );
  }
}

/// Complete API-key capability with lifecycle endpoints and client metadata.
final class AuthApiKeyPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthHostEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthReversibleUserDataDeletionContributor,
        AuthUserAccessRevocationContributor {
  AuthApiKeyPlugin({
    required this.store,
    this.keyPrefix = 'rka',
    this.defaultLifetime = const Duration(days: 90),
    this.maxLifetime = const Duration(days: 365),
    this.sessionExchangeEnabled = false,
    this.keyIdGenerator = secureRandomToken,
    this.secretGenerator = secureRandomToken,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (keyPrefix.trim().isEmpty ||
        keyPrefix.contains('.') ||
        keyPrefix.contains(' ')) {
      throw ArgumentError.value(
        keyPrefix,
        'keyPrefix',
        'must be a non-empty token prefix without dots or spaces',
      );
    }
    if (defaultLifetime <= Duration.zero) {
      throw ArgumentError.value(
        defaultLifetime,
        'defaultLifetime',
        'must be greater than zero',
      );
    }
    if (maxLifetime < defaultLifetime) {
      throw ArgumentError.value(
        maxLifetime,
        'maxLifetime',
        'must be at least defaultLifetime',
      );
    }
  }

  final AuthApiKeyStore store;
  final String keyPrefix;
  final Duration defaultLifetime;
  final Duration maxLifetime;

  /// Whether Routed adapters should expose API-key-to-session exchange.
  ///
  /// This is disabled by default because an API key is usually intended for
  /// service authentication, not browser-session creation.
  final bool sessionExchangeEnabled;
  final AuthApiKeyTokenGenerator keyIdGenerator;
  final AuthApiKeyTokenGenerator secretGenerator;
  final DateTime Function() _clock;
  AuthSessionStrategy _sessionStrategy = AuthSessionStrategy.session;

  @override
  String get id => authApiKeyPluginId;

  @override
  String get userDataNamespace => 'api_keys';

  @override
  String get userAccessNamespace => 'api_keys';

  @override
  Future<void> validateUserDeletion(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must be non-empty');
    }
  }

  @override
  Future<void> deleteUserData(String userId) async {
    await store.deleteForUser(userId);
  }

  @override
  AuthUserDataDeletionCheckpoint checkpointUserData(String userId) =>
      AuthUserDataDeletionCheckpoint.capture([store]);

  @override
  Future<void> revokeUserAccess(String userId) async {
    final target = store;
    if (target is AuthApiKeyUserAccessRevocationStore) {
      final revocationStore = target as AuthApiKeyUserAccessRevocationStore;
      await revocationStore.revokeAllForUser(userId);
      return;
    }
    final revokedAt = _clock().toUtc();
    final records = await target.listForUser(userId);
    for (final record in records) {
      if (record.revokedAt == null) {
        await target.revokeForUser(userId, record.id, revokedAt: revokedAt);
      }
    }
  }

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _sessionStrategy = context.sessionStrategy;
  }

  /// Issues a key and returns the raw secret exactly once.
  Future<AuthApiKeyIssued> issue({
    required String userId,
    required String name,
    Iterable<String> scopes = const <String>[],
    DateTime? expiresAt,
    DateTime? now,
  }) async {
    final current = (now ?? _clock()).toUtc();
    final normalizedUserId = _required(userId, 'userId');
    final normalizedName = _normalizeName(name);
    final normalizedScopes = _normalizeScopes(scopes);
    final expiry = _resolveExpiry(expiresAt, current);
    final id = _requiredToken(keyIdGenerator(length: 12), 'key ID');
    final secret = _requiredToken(secretGenerator(length: 32), 'key secret');
    final rawKey = '$keyPrefix.$id.$secret';
    final record = AuthApiKeyRecord(
      id: id,
      userId: normalizedUserId,
      name: normalizedName,
      keyPrefix: '$keyPrefix.${id.substring(0, id.length < 8 ? id.length : 8)}',
      secretHash: hashOpaqueToken(rawKey),
      scopes: normalizedScopes,
      createdAt: current,
      updatedAt: current,
      expiresAt: expiry,
    );
    await store.create(record);
    return AuthApiKeyIssued(
      apiKey: record.toPublic(now: current),
      key: rawKey,
    );
  }

  Future<List<AuthApiKey>> list(String userId) async {
    final current = _clock().toUtc();
    return (await store.listForUser(
      _required(userId, 'userId'),
    )).map((record) => record.toPublic(now: current)).toList(growable: false);
  }

  Future<AuthApiKey?> revoke(String userId, String id, {DateTime? now}) async {
    final current = (now ?? _clock()).toUtc();
    final revoked = await store.revokeForUser(
      _required(userId, 'userId'),
      _required(id, 'id'),
      revokedAt: current,
    );
    return revoked?.toPublic(now: current);
  }

  /// Replaces a key atomically and returns the new raw key once.
  Future<AuthApiKeyIssued?> rotate(
    String userId,
    String id, {
    String? name,
    Iterable<String>? scopes,
    DateTime? expiresAt,
    DateTime? now,
  }) async {
    final current = (now ?? _clock()).toUtc();
    final existing = await store.findById(_required(id, 'id'));
    if (existing == null ||
        existing.userId != _required(userId, 'userId') ||
        !existing.isActive(now: current)) {
      return null;
    }
    final issued = await _buildIssued(
      userId: existing.userId,
      name: name ?? existing.name,
      scopes: scopes ?? existing.scopes,
      expiresAt: expiresAt ?? existing.expiresAt,
      now: current,
    );
    final replacement = await store.rotateForUser(
      userId: existing.userId,
      id: existing.id,
      replacement: _recordFromIssued(issued),
      revokedAt: current,
    );
    return replacement == null ? null : issued;
  }

  /// Verifies a raw API key and atomically records its last use.
  Future<AuthApiKeyAuthentication?> authenticate(
    String rawKey, {
    DateTime? now,
  }) async {
    final parsed = _parse(rawKey);
    if (parsed == null) return null;
    final record = await store.findById(parsed.id);
    if (record == null ||
        !constantTimeStringEquals(record.secretHash, hashOpaqueToken(rawKey))) {
      return null;
    }
    final touched = await store.touchIfActive(
      record.id,
      (now ?? _clock()).toUtc(),
    );
    return touched == null ? null : AuthApiKeyAuthentication(touched);
  }

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'apiKey.create',
      method: AuthOperationMethod.post,
      path: '/api-keys/create',
      requestCodec: _apiKeyCreateRequestCodec,
      responseCodec: _apiKeyIssuedResponseCodec,
      originPolicy: AuthOperationOriginPolicy.browser,
      csrfPolicy: AuthOperationCsrfPolicy.required,
      rateLimitOperation: apiKeyCreateRateLimitOperation,
      handler: (invocation, input) async {
        final user = _requireUser(invocation.user);
        return (await issue(
          userId: user.id,
          name: _string(input, 'name'),
          scopes: _strings(input['scopes']),
          expiresAt: _optionalDate(input, 'expiresAt'),
        )).toJson();
      },
    ),
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'apiKey.list',
      method: AuthOperationMethod.get,
      path: '/api-keys/list',
      requestCodec: _emptyRequestCodec,
      responseCodec: _apiKeyListResponseCodec,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      rateLimitOperation: apiKeyListRateLimitOperation,
      handler: (invocation, _) async {
        final user = _requireUser(invocation.user);
        return {
          'apiKeys': (await list(
            user.id,
          )).map((key) => key.toJson()).toList(growable: false),
        };
      },
    ),
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'apiKey.revoke',
      method: AuthOperationMethod.post,
      path: '/api-keys/revoke',
      requestCodec: _apiKeyIdRequestCodec,
      responseCodec: _apiKeyMetadataResponseCodec,
      originPolicy: AuthOperationOriginPolicy.browser,
      csrfPolicy: AuthOperationCsrfPolicy.required,
      rateLimitOperation: apiKeyRevokeRateLimitOperation,
      handler: (invocation, input) async {
        final user = _requireUser(invocation.user);
        final revoked = await revoke(user.id, _string(input, 'id'));
        if (revoked == null) throw AuthFlowException('api_key_not_found');
        return {'apiKey': revoked.toJson()};
      },
    ),
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'apiKey.rotate',
      method: AuthOperationMethod.post,
      path: '/api-keys/rotate',
      requestCodec: _apiKeyRotateRequestCodec,
      responseCodec: _apiKeyIssuedResponseCodec,
      originPolicy: AuthOperationOriginPolicy.browser,
      csrfPolicy: AuthOperationCsrfPolicy.required,
      rateLimitOperation: apiKeyRotateRateLimitOperation,
      handler: (invocation, input) async {
        final user = _requireUser(invocation.user);
        final rotated = await rotate(
          user.id,
          _string(input, 'id'),
          name: input['name']?.toString(),
          scopes: input.containsKey('scopes')
              ? _strings(input['scopes'])
              : null,
          expiresAt: _optionalDate(input, 'expiresAt'),
        );
        if (rotated == null) throw AuthFlowException('api_key_not_found');
        return rotated.toJson();
      },
    ),
  ];

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get hostEndpoints =>
      sessionExchangeEnabled && _sessionStrategy == AuthSessionStrategy.session
      ? <AuthEndpointDescriptor<TContext>>[
          TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
            id: 'apiKey.exchange',
            method: AuthOperationMethod.post,
            path: '/api-keys/exchange',
            requestCodec: _emptyRequestCodec,
            responseCodec: _sessionResponseCodec,
            authentication: AuthOperationAuthentication.apiKey,
            originPolicy: AuthOperationOriginPolicy.none,
            csrfPolicy: AuthOperationCsrfPolicy.none,
            rateLimitOperation: apiKeyExchangeRateLimitOperation,
            handler: (invocation, request) => throw UnsupportedError(
              'This endpoint is implemented by the auth host.',
            ),
          ),
        ]
      : <AuthEndpointDescriptor<TContext>>[];

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => [
    AuthPersistenceSchema(
      id: authApiKeyPluginId,
      entities: [
        AuthEntityDescriptor(
          id: 'api_key',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'string'),
            AuthFieldDescriptor(name: 'user_id', kind: 'string'),
            AuthFieldDescriptor(name: 'name', kind: 'string'),
            AuthFieldDescriptor(name: 'key_prefix', kind: 'string'),
            AuthFieldDescriptor(name: 'secret_hash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'scopes', kind: 'string[]'),
            AuthFieldDescriptor(name: 'created_at', kind: 'timestamp'),
            AuthFieldDescriptor(name: 'updated_at', kind: 'timestamp'),
            AuthFieldDescriptor(name: 'expires_at', kind: 'timestamp?'),
            AuthFieldDescriptor(name: 'last_used_at', kind: 'timestamp?'),
            AuthFieldDescriptor(name: 'revoked_at', kind: 'timestamp?'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'user_id',
              targetEntity: 'user',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: const [
            ['id'],
          ],
          indexes: const [
            ['user_id'],
            ['secret_hash'],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'api_key.touch_if_active',
          description:
              'Verify key state and advance last-used time atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'api_key.rotate_for_user',
          description:
              'Revoke the old key and create its replacement atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'api_key.revoke_for_user',
          description: 'Revoke a key belonging to a user atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'api_key.revoke_all_for_user',
          description: 'Revoke every key belonging to a user atomically.',
        ),
      ],
    ),
  ];

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => [
    const AuthClientOperationDescriptor(
      id: 'apiKey.create',
      method: AuthOperationMethod.post,
      path: '/api-keys/create',
    ),
    const AuthClientOperationDescriptor(
      id: 'apiKey.list',
      method: AuthOperationMethod.get,
      path: '/api-keys/list',
    ),
    const AuthClientOperationDescriptor(
      id: 'apiKey.revoke',
      method: AuthOperationMethod.post,
      path: '/api-keys/revoke',
    ),
    const AuthClientOperationDescriptor(
      id: 'apiKey.rotate',
      method: AuthOperationMethod.post,
      path: '/api-keys/rotate',
    ),
    if (sessionExchangeEnabled &&
        _sessionStrategy == AuthSessionStrategy.session)
      const AuthClientOperationDescriptor(
        id: 'apiKey.exchange',
        method: AuthOperationMethod.post,
        path: '/api-keys/exchange',
      ),
  ];

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => [
    apiKeyCreateRateLimitOperation,
    apiKeyListRateLimitOperation,
    apiKeyRevokeRateLimitOperation,
    apiKeyRotateRateLimitOperation,
    if (sessionExchangeEnabled &&
        _sessionStrategy == AuthSessionStrategy.session)
      apiKeyExchangeRateLimitOperation,
  ];

  Future<AuthApiKeyIssued> _buildIssued({
    required String userId,
    required String name,
    required Iterable<String> scopes,
    required DateTime? expiresAt,
    required DateTime now,
  }) async {
    final id = _requiredToken(keyIdGenerator(length: 12), 'key ID');
    final secret = _requiredToken(secretGenerator(length: 32), 'key secret');
    final rawKey = '$keyPrefix.$id.$secret';
    final record = AuthApiKeyRecord(
      id: id,
      userId: _required(userId, 'userId'),
      name: _normalizeName(name),
      keyPrefix: '$keyPrefix.${id.substring(0, id.length < 8 ? id.length : 8)}',
      secretHash: hashOpaqueToken(rawKey),
      scopes: _normalizeScopes(scopes),
      createdAt: now,
      updatedAt: now,
      expiresAt: _resolveExpiry(expiresAt, now),
    );
    return AuthApiKeyIssued(
      apiKey: record.toPublic(now: now),
      key: rawKey,
    );
  }

  AuthApiKeyRecord _recordFromIssued(AuthApiKeyIssued issued) {
    final public = issued.apiKey;
    return AuthApiKeyRecord(
      id: public.id,
      userId: public.userId,
      name: public.name,
      keyPrefix: public.keyPrefix,
      secretHash: hashOpaqueToken(issued.key),
      scopes: public.scopes,
      createdAt: public.createdAt,
      updatedAt: public.updatedAt,
      expiresAt: public.expiresAt,
    );
  }

  DateTime _resolveExpiry(DateTime? value, DateTime now) {
    final expiry = (value ?? now.add(defaultLifetime)).toUtc();
    if (!expiry.isAfter(now)) {
      throw ArgumentError.value(value, 'expiresAt', 'must be in the future');
    }
    if (expiry.isAfter(now.add(maxLifetime))) {
      throw ArgumentError.value(
        value,
        'expiresAt',
        'must not exceed maxLifetime',
      );
    }
    return expiry;
  }

  _ParsedApiKey? _parse(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 3 || parts[0] != keyPrefix) return null;
    if (parts[1].trim().isEmpty || parts[2].trim().isEmpty) return null;
    return _ParsedApiKey(parts[1], value.trim());
  }
}

final class _ParsedApiKey {
  const _ParsedApiKey(this.id, this.rawKey);

  final String id;
  final String rawKey;
}

const _apiKeyCreateRequestCodec = AuthOperationCodec<Map<String, dynamic>>(
  decode: _decodeMap,
  encode: _encodeMap,
  required: true,
  schema: _apiKeyCreateRequestSchema,
);
const _apiKeyIdRequestCodec = AuthOperationCodec<Map<String, dynamic>>(
  decode: _decodeMap,
  encode: _encodeMap,
  required: true,
  schema: _apiKeyIdRequestSchema,
);
const _apiKeyRotateRequestCodec = AuthOperationCodec<Map<String, dynamic>>(
  decode: _decodeMap,
  encode: _encodeMap,
  required: true,
  schema: _apiKeyRotateRequestSchema,
);
const _emptyRequestCodec = AuthOperationCodec<Map<String, dynamic>>(
  decode: _decodeMap,
  encode: _encodeMap,
  schema: _emptyObjectSchema,
);
const _apiKeyIssuedResponseCodec = AuthOperationCodec<Object?>(
  decode: _decodeObject,
  encode: _encodeObject,
  schema: _apiKeyIssuedResponseSchema,
);
const _apiKeyMetadataResponseCodec = AuthOperationCodec<Object?>(
  decode: _decodeObject,
  encode: _encodeObject,
  schema: _apiKeyMetadataEnvelopeSchema,
);
const _apiKeyListResponseCodec = AuthOperationCodec<Object?>(
  decode: _decodeObject,
  encode: _encodeObject,
  schema: _apiKeyListResponseSchema,
);
const _sessionResponseCodec = AuthOperationCodec<Object?>(
  decode: _decodeObject,
  encode: _encodeObject,
  schema: _authSessionResponseSchema,
);

Map<String, dynamic> _decodeMap(Map<String, dynamic> value) => value;
Object? _encodeMap(Map<String, dynamic> value) => value;
Object? _decodeObject(Map<String, dynamic> value) => value;
Object? _encodeObject(Object? value) => value;

const Map<String, Object?> _emptyObjectSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
};

const Map<String, Object?> _apiKeyCreateRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['name'],
  'properties': <String, Object?>{
    'name': <String, Object?>{'type': 'string', 'minLength': 1},
    'scopes': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string'},
      'uniqueItems': true,
    },
    'expiresAt': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
  },
};

const Map<String, Object?> _apiKeyIdRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['id'],
  'properties': <String, Object?>{
    'id': <String, Object?>{'type': 'string', 'minLength': 1},
  },
};

const Map<String, Object?> _apiKeyRotateRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['id'],
  'properties': <String, Object?>{
    'id': <String, Object?>{'type': 'string', 'minLength': 1},
    'name': <String, Object?>{'type': 'string', 'minLength': 1},
    'scopes': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string'},
      'uniqueItems': true,
    },
    'expiresAt': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
  },
};

const Map<String, Object?> _apiKeyMetadataSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': _apiKeyMetadataRequired,
  'properties': _apiKeyMetadataProperties,
};

const List<String> _apiKeyMetadataRequired = <String>[
  'id',
  'userId',
  'name',
  'keyPrefix',
  'scopes',
  'createdAt',
  'updatedAt',
  'active',
];

const Map<String, Object?> _apiKeyMetadataProperties = <String, Object?>{
  'id': <String, Object?>{'type': 'string'},
  'userId': <String, Object?>{'type': 'string'},
  'name': <String, Object?>{'type': 'string'},
  'keyPrefix': <String, Object?>{'type': 'string'},
  'scopes': <String, Object?>{
    'type': 'array',
    'items': <String, Object?>{'type': 'string'},
  },
  'createdAt': <String, Object?>{'type': 'string', 'format': 'date-time'},
  'updatedAt': <String, Object?>{'type': 'string', 'format': 'date-time'},
  'expiresAt': <String, Object?>{
    'type': <String>['string', 'null'],
    'format': 'date-time',
  },
  'lastUsedAt': <String, Object?>{
    'type': <String>['string', 'null'],
    'format': 'date-time',
  },
  'revokedAt': <String, Object?>{
    'type': <String>['string', 'null'],
    'format': 'date-time',
  },
  'active': <String, Object?>{'type': 'boolean'},
};

const Map<String, Object?> _apiKeyIssuedResponseSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>[..._apiKeyMetadataRequired, 'apiKey'],
  'properties': <String, Object?>{
    ..._apiKeyMetadataProperties,
    'apiKey': <String, Object?>{
      'type': 'string',
      'readOnly': true,
      'description': 'Raw API key returned exactly once.',
    },
  },
};

const Map<String, Object?> _apiKeyMetadataEnvelopeSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['apiKey'],
  'properties': <String, Object?>{'apiKey': _apiKeyMetadataSchema},
};

const Map<String, Object?> _apiKeyListResponseSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['apiKeys'],
  'properties': <String, Object?>{
    'apiKeys': <String, Object?>{
      'type': 'array',
      'items': _apiKeyMetadataSchema,
    },
  },
};

const Map<String, Object?> _authSessionResponseSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
  'required': <String>['user', 'strategy'],
  'properties': <String, Object?>{
    'user': <String, Object?>{'type': 'object'},
    'expires': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
    'strategy': <String, Object?>{'type': 'string'},
    'token': <String, Object?>{
      'type': 'string',
      'readOnly': true,
      'description': 'Present only when JWT response-body exposure is enabled.',
    },
  },
};

const apiKeyCreateRateLimitOperation = AuthRateLimitOperation(
  'api_key',
  'create',
);
const apiKeyListRateLimitOperation = AuthRateLimitOperation('api_key', 'list');
const apiKeyRevokeRateLimitOperation = AuthRateLimitOperation(
  'api_key',
  'revoke',
);
const apiKeyRotateRateLimitOperation = AuthRateLimitOperation(
  'api_key',
  'rotate',
);
const apiKeyExchangeRateLimitOperation = AuthRateLimitOperation(
  'api_key',
  'exchange',
);

AuthUser _requireUser(AuthUser? user) {
  if (user == null) throw AuthFlowException('unauthorized');
  return user;
}

String _required(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return trimmed;
}

String _requiredToken(String value, String name) {
  final token = _required(value, name);
  if (token.contains('.') || token.contains(RegExp(r'\s'))) {
    throw ArgumentError.value(
      value,
      name,
      'must not contain dots or whitespace',
    );
  }
  return token;
}

String _normalizeName(String value) {
  final normalized = _required(value, 'name');
  if (normalized.length > 100) {
    throw ArgumentError.value(value, 'name', 'must be at most 100 characters');
  }
  return normalized;
}

List<String> _normalizeScopes(Iterable<String> values) {
  final normalized = <String>{};
  for (final value in values) {
    final scope = value.trim().toLowerCase();
    if (scope.isEmpty) continue;
    if (scope.length > 100 || !RegExp(r'^[a-z0-9:_./*-]+$').hasMatch(scope)) {
      throw ArgumentError.value(value, 'scopes', 'contains an invalid scope');
    }
    normalized.add(scope);
  }
  return List<String>.unmodifiable(normalized);
}

List<String> _strings(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List) {
    throw AuthFlowException('invalid_api_key_scopes');
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

String _string(Map<String, dynamic> input, String key) {
  final value = input[key]?.toString() ?? '';
  if (value.trim().isEmpty) throw AuthFlowException('invalid_api_key_request');
  return value;
}

DateTime? _optionalDate(Map<String, dynamic> input, String key) {
  final value = input[key];
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) throw AuthFlowException('invalid_api_key_expiry');
  return parsed.toUtc();
}

void _validateRecord(AuthApiKeyRecord record) {
  _required(record.id, 'record.id');
  _required(record.userId, 'record.userId');
  _normalizeName(record.name);
  _required(record.keyPrefix, 'record.keyPrefix');
  _required(record.secretHash, 'record.secretHash');
  if (!record.updatedAt.toUtc().isAtLeast(record.createdAt.toUtc())) {
    throw ArgumentError.value(
      record.updatedAt,
      'record.updatedAt',
      'must not be before createdAt',
    );
  }
}

extension on DateTime {
  bool isAtLeast(DateTime other) => !isBefore(other);
}
