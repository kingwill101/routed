import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart' as cbor;
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'exceptions.dart';
import 'feature.dart';
import 'models.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart';
import 'webauthn_store.dart';

/// Stable ID for the opt-in WebAuthn feature.
const String authWebAuthnFeatureId = 'webauthn';

/// Public registration options returned to a WebAuthn client.
final class AuthWebAuthnRegistrationOptions {
  const AuthWebAuthnRegistrationOptions({
    required this.challenge,
    required this.relyingParty,
    required this.userId,
    required this.userName,
    required this.displayName,
    required this.timeout,
    required this.attestation,
    required this.excludeCredentials,
    required this.userVerification,
  });

  final String challenge;
  final WebAuthnRelyingParty relyingParty;
  final String userId;
  final String userName;
  final String displayName;
  final Duration timeout;
  final String attestation;
  final List<String> excludeCredentials;
  final String userVerification;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'challenge': challenge,
    'rp': <String, dynamic>{'id': relyingParty.id, 'name': relyingParty.name},
    'user': <String, dynamic>{
      'id': userId,
      'name': userName,
      'displayName': displayName,
    },
    'pubKeyCredParams': const <Map<String, dynamic>>[
      <String, dynamic>{'type': 'public-key', 'alg': -7},
    ],
    'timeout': timeout.inMilliseconds,
    'attestation': attestation,
    'excludeCredentials': excludeCredentials
        .map(
          (credentialId) => <String, dynamic>{
            'type': 'public-key',
            'id': credentialId,
          },
        )
        .toList(growable: false),
    'authenticatorSelection': <String, dynamic>{
      'userVerification': userVerification,
    },
  };
}

/// Public authentication options returned to a WebAuthn client.
final class AuthWebAuthnAuthenticationOptions {
  const AuthWebAuthnAuthenticationOptions({
    required this.challenge,
    required this.relyingPartyId,
    required this.timeout,
    required this.userVerification,
    required this.allowCredentials,
    this.userId,
  });

  final String challenge;
  final String relyingPartyId;
  final Duration timeout;
  final String userVerification;
  final List<String> allowCredentials;
  final String? userId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'challenge': challenge,
    'rpId': relyingPartyId,
    'timeout': timeout.inMilliseconds,
    'userVerification': userVerification,
    if (allowCredentials.isNotEmpty)
      'allowCredentials': allowCredentials
          .map(
            (credentialId) => <String, dynamic>{
              'type': 'public-key',
              'id': credentialId,
            },
          )
          .toList(growable: false),
  };
}

/// Result of a verified passkey assertion.
final class AuthWebAuthnAuthenticationResult {
  const AuthWebAuthnAuthenticationResult({
    required this.user,
    required this.authenticator,
  });

  final AuthUser user;
  final WebAuthnAuthenticator authenticator;
}

/// Typed WebAuthn/passkey feature for `server_auth` runtimes.
///
/// This feature supports `none` attestation and ES256 (`alg: -7`) passkeys.
/// It deliberately rejects unsupported attestation formats and COSE
/// algorithms instead of accepting an assertion that has not been verified.
/// Applications that need other WebAuthn algorithms can add them after the
/// same parsing and replay guarantees are implemented.
final class WebAuthnFeature<TContext>
    implements
        AuthFeature<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDataDeletionContributor {
  WebAuthnFeature({
    required this.provider,
    this.challengeTtl = const Duration(minutes: 5),
  }) : assert(challengeTtl > Duration.zero);

  final WebAuthnProvider provider;
  final Duration challengeTtl;

  late AuthWebAuthnChallengeStore _challengeStore;
  late AuthWebAuthnAuthenticatorStore _authenticatorStore;
  late AuthUserStore _userStore;
  bool _configured = false;

  @override
  String get id => authWebAuthnFeatureId;

  @override
  String get userDataNamespace => 'webauthn';

  @override
  Future<void> validateUserDeletion(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must be non-empty');
    }
  }

  @override
  Future<void> deleteUserData(String userId) async {
    final credentials = await _authenticatorStore.listForUser(userId);
    for (final credential in credentials) {
      await _authenticatorStore.deleteForUser(userId, credential.credentialId);
    }
  }

  @override
  void configure(AuthFeatureContext<TContext> context) {
    _challengeStore = context.store.webAuthnChallenges;
    _authenticatorStore = context.store.webAuthnAuthenticators;
    _userStore = context.store.users;
    _configured = true;
  }

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      <AuthEndpointDescriptor<TContext>>[
        _endpoint(
          id: 'webauthn.registrationOptions',
          method: AuthOperationMethod.post,
          path: '/webauthn/register/options',
          authentication: AuthOperationAuthentication.session,
          csrfPolicy: AuthOperationCsrfPolicy.required,
          operationName: 'registration-options',
        ),
        _endpoint(
          id: 'webauthn.registrationVerify',
          method: AuthOperationMethod.post,
          path: '/webauthn/register/verify',
          authentication: AuthOperationAuthentication.session,
          csrfPolicy: AuthOperationCsrfPolicy.required,
          operationName: 'registration-verify',
        ),
        _endpoint(
          id: 'webauthn.authenticationOptions',
          method: AuthOperationMethod.post,
          path: '/webauthn/authenticate/options',
          authentication: AuthOperationAuthentication.none,
          csrfPolicy: AuthOperationCsrfPolicy.none,
          operationName: 'authentication-options',
        ),
        _endpoint(
          id: 'webauthn.authenticationVerify',
          method: AuthOperationMethod.post,
          path: '/webauthn/authenticate/verify',
          authentication: AuthOperationAuthentication.none,
          csrfPolicy: AuthOperationCsrfPolicy.none,
          operationName: 'authentication-verify',
        ),
        _endpoint(
          id: 'webauthn.credentialList',
          method: AuthOperationMethod.get,
          path: '/webauthn/credentials',
          authentication: AuthOperationAuthentication.session,
          originPolicy: AuthOperationOriginPolicy.none,
          csrfPolicy: AuthOperationCsrfPolicy.none,
          operationName: 'credential-list',
        ),
        _endpoint(
          id: 'webauthn.credentialDelete',
          method: AuthOperationMethod.post,
          path: '/webauthn/credentials/delete',
          authentication: AuthOperationAuthentication.session,
          csrfPolicy: AuthOperationCsrfPolicy.required,
          operationName: 'credential-delete',
        ),
        _endpoint(
          id: 'webauthn.credentialRename',
          method: AuthOperationMethod.post,
          path: '/webauthn/credentials/rename',
          authentication: AuthOperationAuthentication.session,
          csrfPolicy: AuthOperationCsrfPolicy.required,
          operationName: 'credential-rename',
        ),
      ];

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      serverOnly: endpoint.serverOnly,
    ),
  );

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required AuthOperationMethod method,
    required String path,
    required AuthOperationAuthentication authentication,
    required AuthOperationCsrfPolicy csrfPolicy,
    required String operationName,
    AuthOperationOriginPolicy originPolicy = AuthOperationOriginPolicy.browser,
  }) {
    return TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: id,
      method: method,
      path: path,
      requestCodec: _mapCodec,
      responseCodec: _objectCodec,
      authentication: authentication,
      originPolicy: originPolicy,
      csrfPolicy: csrfPolicy,
      rateLimitOperation: AuthRateLimitOperation('webauthn', operationName),
      handler: (invocation, request) =>
          _invokeEndpoint(id, invocation, request),
    );
  }

  Future<Object?> _invokeEndpoint(
    String id,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> request,
  ) async {
    switch (id) {
      case 'webauthn.registrationOptions':
        final user = _requireInvocationUser(invocation);
        return (await beginRegistration(
          context: invocation.context,
          user: user,
        )).toJson();
      case 'webauthn.registrationVerify':
        final user = _requireInvocationUser(invocation);
        final credential = _requiredMap(request, 'credential');
        final saved = await finishRegistration(
          context: invocation.context,
          user: user,
          credential: credential,
        );
        return <String, dynamic>{'credential': saved.toJson()};
      case 'webauthn.authenticationOptions':
        final userId = _optionalString(request, 'userId');
        return (await beginAuthentication(
          context: invocation.context,
          userId: userId,
        )).toJson();
      case 'webauthn.authenticationVerify':
        final credential = _requiredMap(request, 'credential');
        final result = await finishAuthentication(
          context: invocation.context,
          credential: credential,
          userId: _optionalString(request, 'userId'),
        );
        final issuedSession = invocation.sessionControl == null ||
                invocation.sessionControl!.strategy !=
                    AuthSessionStrategy.session
            ? null
            : await invocation.sessionControl!.replaceIdentity(
                result.user,
                authenticationMethod: 'webauthn',
              );
        return <String, dynamic>{
          'status': 'authenticated',
          'user': result.user.toJson(),
          'credential': result.authenticator.toJson(),
          if (issuedSession != null) 'session': issuedSession.toJson(),
        };
      case 'webauthn.credentialList':
        final user = _requireInvocationUser(invocation);
        final credentials = await listCredentials(user.id);
        return <String, dynamic>{
          'credentials': credentials
              .map((credential) => credential.toJson())
              .toList(growable: false),
        };
      case 'webauthn.credentialDelete':
        final user = _requireInvocationUser(invocation);
        await deleteCredential(
          userId: user.id,
          credentialId: _requiredString(request, 'credentialId'),
        );
        return const <String, dynamic>{'status': 'credential_deleted'};
      case 'webauthn.credentialRename':
        final user = _requireInvocationUser(invocation);
        final renamed = await renameCredential(
          userId: user.id,
          credentialId: _requiredString(request, 'credentialId'),
          name: _requiredString(request, 'name'),
        );
        return <String, dynamic>{'credential': renamed.toJson()};
      default:
        throw StateError('Unknown WebAuthn endpoint $id');
    }
  }

  static final AuthOperationCodec<Map<String, dynamic>> _mapCodec =
      AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => Map<String, dynamic>.from(value),
        encode: (value) => value,
      );

  static final AuthOperationCodec<Object?> _objectCodec =
      AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      );

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authWebAuthnFeatureId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'auth_webauthn_challenge',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'challengeHash', kind: 'digest'),
            AuthFieldDescriptor(name: 'ceremony', kind: 'enum'),
            AuthFieldDescriptor(name: 'relyingPartyId', kind: 'string'),
            AuthFieldDescriptor(name: 'origin', kind: 'origin'),
            AuthFieldDescriptor(name: 'userId', kind: 'nullable_id'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(field: 'userId', targetEntity: 'user'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['challengeHash'],
          ],
          indexes: <List<String>>[
            <String>['expiresAt'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'auth_webauthn_authenticator',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'credentialId', kind: 'opaque_id'),
            AuthFieldDescriptor(name: 'publicKey', kind: 'cose_key'),
            AuthFieldDescriptor(name: 'counter', kind: 'integer'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'transports', kind: 'string_list'),
            AuthFieldDescriptor(name: 'name', kind: 'nullable_string'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'lastUsedAt', kind: 'nullable_datetime'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(field: 'userId', targetEntity: 'user'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['credentialId'],
          ],
          indexes: <List<String>>[
            <String>['userId'],
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'challenge.consume',
          description:
              'Consume one active challenge bound to the ceremony, RP, origin, and user.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'authenticator.updateUsage',
          description:
              'Compare-and-set the signature counter and advance last-used time.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'authenticator.rename',
          description:
              'Update a passkey name only when the credential belongs to the user.',
        ),
      ],
    ),
  ];

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => const [
    AuthRateLimitOperation('webauthn', 'registration-options'),
    AuthRateLimitOperation('webauthn', 'registration-verify'),
    AuthRateLimitOperation('webauthn', 'authentication-options'),
    AuthRateLimitOperation('webauthn', 'authentication-verify'),
    AuthRateLimitOperation('webauthn', 'credential-list'),
    AuthRateLimitOperation('webauthn', 'credential-delete'),
    AuthRateLimitOperation('webauthn', 'credential-rename'),
  ];

  /// Begins a registration ceremony for the authenticated [user].
  Future<AuthWebAuthnRegistrationOptions> beginRegistration({
    required TContext context,
    required AuthUser user,
    DateTime? now,
  }) async {
    _ensureConfigured();
    _requireUserId(user);
    final relyingParty = _validatedRelyingParty(context);
    final current = (now ?? DateTime.now()).toUtc();
    final challenge = secureRandomToken();
    await _challengeStore.save(
      AuthWebAuthnChallenge(
        id: secureRandomToken(length: 16),
        challengeHash: hashOpaqueToken(challenge),
        ceremony: AuthWebAuthnCeremony.registration,
        relyingPartyId: relyingParty.id,
        origin: _canonicalOrigin(relyingParty.origin),
        userId: user.id,
        createdAt: current,
        expiresAt: current.add(challengeTtl),
      ),
    );
    final existing = await _authenticatorStore.listForUser(user.id);
    final selection = provider.registrationOptions.authenticatorSelection;
    final userVerification = selection?.userVerification ?? 'preferred';
    _validateUserVerification(userVerification);
    return AuthWebAuthnRegistrationOptions(
      challenge: challenge,
      relyingParty: relyingParty,
      userId: _userHandle(user.id),
      userName: user.email ?? user.id,
      displayName: user.name ?? user.email ?? user.id,
      timeout: provider.timeout,
      attestation: _validateAttestationPreference(
        provider.registrationOptions.attestation,
      ),
      excludeCredentials: provider.registrationOptions.excludeCredentials
          ? existing.map((value) => value.credentialId).toList(growable: false)
          : const <String>[],
      userVerification: userVerification,
    );
  }

  /// Verifies and persists a registration response.
  Future<WebAuthnAuthenticator> finishRegistration({
    required TContext context,
    required AuthUser user,
    required Map<String, dynamic> credential,
    DateTime? now,
  }) async {
    _ensureConfigured();
    _requireUserId(user);
    final relyingParty = _validatedRelyingParty(context);
    final parsed = _parseCredential(credential);
    final clientData = _parseClientData(
      parsed.clientDataJson,
      expectedType: 'webauthn.create',
      expectedOrigin: _canonicalOrigin(relyingParty.origin),
    );
    final attestation = _parseAttestationObject(
      parsed.attestationObject!,
      relyingPartyId: relyingParty.id,
      requireUserVerification:
          provider
              .registrationOptions
              .authenticatorSelection
              ?.userVerification ==
          'required',
    );
    await _consumeChallenge(
      clientData.challenge,
      ceremony: AuthWebAuthnCeremony.registration,
      relyingPartyId: relyingParty.id,
      origin: _canonicalOrigin(relyingParty.origin),
      userId: user.id,
      now: now,
    );
    final createdAt = (now ?? DateTime.now()).toUtc();
    final authenticator = WebAuthnAuthenticator(
      credentialId: base64UrlNoPadding(attestation.credentialId),
      publicKey: base64UrlNoPadding(attestation.publicKeyCose),
      counter: attestation.counter,
      userId: user.id,
      transports: parsed.transports,
      createdAt: createdAt,
      name: parsed.name,
    );
    try {
      return await _authenticatorStore.create(authenticator);
    } on StateError {
      throw AuthFlowException('webauthn_credential_exists');
    } on ArgumentError {
      throw AuthFlowException('webauthn_registration_invalid');
    }
  }

  /// Begins a discoverable or user-bound authentication ceremony.
  Future<AuthWebAuthnAuthenticationOptions> beginAuthentication({
    required TContext context,
    String? userId,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final relyingParty = _validatedRelyingParty(context);
    final normalizedUserId = userId?.trim();
    if (normalizedUserId?.isEmpty == true) {
      throw AuthFlowException('webauthn_user_invalid');
    }
    final current = (now ?? DateTime.now()).toUtc();
    final challenge = secureRandomToken();
    await _challengeStore.save(
      AuthWebAuthnChallenge(
        id: secureRandomToken(length: 16),
        challengeHash: hashOpaqueToken(challenge),
        ceremony: AuthWebAuthnCeremony.authentication,
        relyingPartyId: relyingParty.id,
        origin: _canonicalOrigin(relyingParty.origin),
        userId: normalizedUserId,
        createdAt: current,
        expiresAt: current.add(challengeTtl),
      ),
    );
    final credentials = normalizedUserId == null
        ? const <WebAuthnAuthenticator>[]
        : await _authenticatorStore.listForUser(normalizedUserId);
    final userVerification = provider.authenticationOptions.userVerification;
    _validateUserVerification(userVerification);
    return AuthWebAuthnAuthenticationOptions(
      challenge: challenge,
      relyingPartyId: relyingParty.id,
      timeout: provider.timeout,
      userVerification: userVerification,
      allowCredentials: credentials
          .map((value) => value.credentialId)
          .toList(growable: false),
      userId: normalizedUserId,
    );
  }

  /// Verifies a passkey assertion and advances its replay counter atomically.
  Future<AuthWebAuthnAuthenticationResult> finishAuthentication({
    required TContext context,
    required Map<String, dynamic> credential,
    DateTime? now,
    String? userId,
  }) async {
    _ensureConfigured();
    final relyingParty = _validatedRelyingParty(context);
    final parsed = _parseCredential(credential, assertion: true);
    final credentialId = base64UrlNoPadding(parsed.credentialId);
    final authenticator = await _authenticatorStore.findByCredentialId(
      credentialId,
    );
    if (authenticator == null || authenticator.userId == null) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    final requestedUserId = userId?.trim();
    if (requestedUserId?.isEmpty == true ||
        (requestedUserId != null && requestedUserId != authenticator.userId)) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    final clientData = _parseClientData(
      parsed.clientDataJson,
      expectedType: 'webauthn.get',
      expectedOrigin: _canonicalOrigin(relyingParty.origin),
    );
    final authenticatorData = parsed.authenticatorData!;
    final signature = parsed.signature!;
    final assertion = _parseAssertionAuthenticatorData(
      authenticatorData,
      relyingPartyId: relyingParty.id,
      requireUserVerification:
          provider.authenticationOptions.userVerification == 'required',
    );
    final clientDataHash = crypto.sha256.convert(parsed.clientDataJson).bytes;
    final signedData = Uint8List.fromList(<int>[
      ...authenticatorData,
      ...clientDataHash,
    ]);
    if (!_verifyEs256(
      coseKey: _decodeBase64Url(authenticator.publicKey),
      message: signedData,
      signature: signature,
    )) {
      throw AuthFlowException('webauthn_signature_invalid');
    }
    await _consumeChallenge(
      clientData.challenge,
      ceremony: AuthWebAuthnCeremony.authentication,
      relyingPartyId: relyingParty.id,
      origin: _canonicalOrigin(relyingParty.origin),
      userId: requestedUserId,
      now: now,
    );
    final oldCounter = authenticator.counter;
    if (oldCounter > 0 && assertion.counter <= oldCounter) {
      throw AuthFlowException('webauthn_counter_replay');
    }
    final updated = await _authenticatorStore.updateUsage(
      credentialId: authenticator.credentialId,
      expectedCounter: oldCounter,
      newCounter: assertion.counter,
      lastUsedAt: (now ?? DateTime.now()).toUtc(),
    );
    if (updated == null) {
      throw AuthFlowException('webauthn_counter_replay');
    }
    final user = await _userStore.findById(authenticator.userId!);
    if (user == null) {
      throw AuthFlowException('webauthn_user_invalid');
    }
    return AuthWebAuthnAuthenticationResult(user: user, authenticator: updated);
  }

  Future<List<WebAuthnAuthenticator>> listCredentials(String userId) async {
    _ensureConfigured();
    if (userId.trim().isEmpty) throw AuthFlowException('unauthorized');
    return _authenticatorStore.listForUser(userId);
  }

  Future<void> deleteCredential({
    required String userId,
    required String credentialId,
  }) async {
    _ensureConfigured();
    if (userId.trim().isEmpty || credentialId.trim().isEmpty) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    final deleted = await _authenticatorStore.deleteForUser(
      userId,
      credentialId,
    );
    if (!deleted) throw AuthFlowException('webauthn_credential_not_found');
  }

  /// Renames one passkey belonging to [userId].
  Future<WebAuthnAuthenticator> renameCredential({
    required String userId,
    required String credentialId,
    required String name,
  }) async {
    _ensureConfigured();
    if (userId.trim().isEmpty || credentialId.trim().isEmpty) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw AuthFlowException('webauthn_name_invalid');
    }
    final renamed = await _authenticatorStore.renameForUser(
      userId,
      credentialId,
      normalizedName,
    );
    if (renamed == null) {
      throw AuthFlowException('webauthn_credential_not_found');
    }
    return renamed;
  }

  void _ensureConfigured() {
    if (!_configured) {
      throw StateError('WebAuthnFeature must be registered with AuthRuntime');
    }
  }

  WebAuthnRelyingParty _validatedRelyingParty(TContext context) {
    final configured = provider.getRelyingParty(context, provider);
    final id = configured.id.trim().toLowerCase();
    final origin = _canonicalOrigin(configured.origin);
    final originUri = Uri.parse(origin);
    if (id.isEmpty ||
        id.contains('/') ||
        id.contains(':') ||
        id.contains('@') ||
        id.contains('?') ||
        id.contains('#') ||
        id.endsWith('.') ||
        !RegExp(r'^[a-z0-9.-]+$').hasMatch(id)) {
      throw AuthFlowException('webauthn_configuration_invalid');
    }
    final host = originUri.host.toLowerCase();
    if (host != id && !host.endsWith('.$id')) {
      throw AuthFlowException('webauthn_configuration_invalid');
    }
    final name = configured.name.trim();
    if (name.isEmpty) throw AuthFlowException('webauthn_configuration_invalid');
    return WebAuthnRelyingParty(id: id, name: name, origin: origin);
  }

  Future<void> _consumeChallenge(
    String challenge, {
    required AuthWebAuthnCeremony ceremony,
    required String relyingPartyId,
    required String origin,
    required String? userId,
    DateTime? now,
  }) async {
    final challengeHash = hashOpaqueToken(challenge);
    final consumed = await _challengeStore.consume(
      challengeHash: challengeHash,
      ceremony: ceremony,
      relyingPartyId: relyingPartyId,
      origin: origin,
      userId: userId,
      now: now,
    );
    if (consumed == null) throw AuthFlowException('webauthn_challenge_invalid');
  }

  _ParsedCredential _parseCredential(
    Map<String, dynamic> input, {
    bool assertion = false,
  }) {
    final rawIdValue = input['rawId'] ?? input['id'];
    final responseValue = input['response'];
    final type = input['type'];
    if (rawIdValue is! String ||
        responseValue is! Map ||
        (type != null && type != 'public-key')) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    final rawId = _decodeBase64Url(rawIdValue);
    if (rawId.isEmpty || rawId.length > 1024) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    final idValue = input['id'];
    if (idValue is String &&
        !_constantTimeBytesEqual(rawId, _decodeBase64Url(idValue))) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    if (idValue != null && idValue is! String) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    late final Map<String, dynamic> response;
    try {
      response = Map<String, dynamic>.from(responseValue);
    } catch (_) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    final clientDataJson = _decodeField(response, 'clientDataJSON');
    final transports = response['transports'] is List
        ? (response['transports'] as List)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : null;
    final name = input['name']?.toString().trim();
    if (name?.isEmpty == true) throw AuthFlowException('webauthn_name_invalid');
    if (assertion) {
      final authenticatorData = _decodeField(response, 'authenticatorData');
      final signature = _decodeField(response, 'signature');
      return _ParsedCredential(
        credentialId: rawId,
        clientDataJson: clientDataJson,
        authenticatorData: authenticatorData,
        signature: signature,
        transports: transports,
        name: name,
      );
    }
    final attestationObject = _decodeField(response, 'attestationObject');
    return _ParsedCredential(
      credentialId: rawId,
      clientDataJson: clientDataJson,
      attestationObject: attestationObject,
      transports: transports,
      name: name,
    );
  }

  _ClientData _parseClientData(
    Uint8List bytes, {
    required String expectedType,
    required String expectedOrigin,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw AuthFlowException('webauthn_client_data_invalid');
    }
    if (decoded is! Map) {
      throw AuthFlowException('webauthn_client_data_invalid');
    }
    final type = decoded['type'];
    final challenge = decoded['challenge'];
    final origin = decoded['origin'];
    if (type != expectedType || challenge is! String || origin is! String) {
      throw AuthFlowException('webauthn_client_data_invalid');
    }
    if (_canonicalOrigin(origin) != expectedOrigin ||
        decoded['crossOrigin'] == true ||
        (decoded['topOrigin'] is String &&
            _canonicalOrigin(decoded['topOrigin'] as String) !=
                expectedOrigin)) {
      throw AuthFlowException('webauthn_origin_invalid');
    }
    try {
      _decodeBase64Url(challenge);
    } on AuthFlowException {
      throw AuthFlowException('webauthn_challenge_invalid');
    }
    return _ClientData(challenge: challenge);
  }

  _ParsedAttestation _parseAttestationObject(
    Uint8List bytes, {
    required String relyingPartyId,
    required bool requireUserVerification,
  }) {
    dynamic decoded;
    try {
      decoded = cbor.cbor.decode(bytes, decodeBase64: false);
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    if (decoded is! Map ||
        decoded['fmt'] != 'none' ||
        decoded['attStmt'] is! Map ||
        (decoded['attStmt'] as Map).isNotEmpty) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    final authData = decoded['authData'];
    if (authData is! List ||
        authData.any((value) => value is! int || value < 0 || value > 255)) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final parsed = _parseAuthenticatorData(
      Uint8List.fromList(authData.cast<int>()),
      relyingPartyId: relyingPartyId,
      requireAttestedCredential: true,
      requireUserVerification: requireUserVerification,
    );
    return _ParsedAttestation(
      credentialId: parsed.credentialId!,
      publicKeyCose: parsed.publicKeyCose!,
      counter: parsed.counter,
    );
  }

  _ParsedAuthenticatorData _parseAssertionAuthenticatorData(
    Uint8List bytes, {
    required String relyingPartyId,
    required bool requireUserVerification,
  }) {
    return _parseAuthenticatorData(
      bytes,
      relyingPartyId: relyingPartyId,
      requireAttestedCredential: false,
      requireUserVerification: requireUserVerification,
    );
  }

  _ParsedAuthenticatorData _parseAuthenticatorData(
    Uint8List bytes, {
    required String relyingPartyId,
    required bool requireAttestedCredential,
    required bool requireUserVerification,
  }) {
    if (bytes.length < 37) {
      throw AuthFlowException('webauthn_authenticator_data_invalid');
    }
    final expectedRpIdHash = crypto.sha256
        .convert(utf8.encode(relyingPartyId))
        .bytes;
    if (!_constantTimeBytesEqual(bytes.sublist(0, 32), expectedRpIdHash)) {
      throw AuthFlowException('webauthn_rp_id_invalid');
    }
    final flags = bytes[32];
    final userPresent = flags & 0x01 != 0;
    final userVerified = flags & 0x04 != 0;
    final attestedCredentialData = flags & 0x40 != 0;
    if (!userPresent || (requireUserVerification && !userVerified)) {
      throw AuthFlowException('webauthn_user_presence_invalid');
    }
    if (requireAttestedCredential && !attestedCredentialData) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final counter =
        (bytes[33] << 24) | (bytes[34] << 16) | (bytes[35] << 8) | bytes[36];
    if (!attestedCredentialData) {
      return _ParsedAuthenticatorData(counter: counter);
    }
    if (bytes.length < 55) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final credentialLength = (bytes[53] << 8) | bytes[54];
    final credentialStart = 55;
    final credentialEnd = credentialStart + credentialLength;
    if (credentialLength == 0 ||
        credentialLength > 1024 ||
        credentialEnd >= bytes.length) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final credentialId = bytes.sublist(credentialStart, credentialEnd);
    final publicKeyCose = bytes.sublist(credentialEnd);
    _decodeCosePublicKey(publicKeyCose);
    return _ParsedAuthenticatorData(
      counter: counter,
      credentialId: Uint8List.fromList(credentialId),
      publicKeyCose: Uint8List.fromList(publicKeyCose),
    );
  }

  bool _verifyEs256({
    required Uint8List coseKey,
    required Uint8List message,
    required Uint8List signature,
  }) {
    if (signature.length != 64) return false;
    try {
      final key = _decodeCosePublicKey(coseKey);
      final parameters = ECDomainParameters('secp256r1');
      final point = parameters.curve.createPoint(
        _bytesToBigInt(key.x),
        _bytesToBigInt(key.y),
      );
      if (point.isInfinity) return false;
      final parsedSignature = ECSignature(
        _bytesToBigInt(signature.sublist(0, 32)),
        _bytesToBigInt(signature.sublist(32)),
      );
      final verifier = ECDSASigner(SHA256Digest())
        ..init(
          false,
          PublicKeyParameter<ECPublicKey>(ECPublicKey(point, parameters)),
        );
      return verifier.verifySignature(message, parsedSignature);
    } catch (_) {
      return false;
    }
  }

  _CoseEs256Key _decodeCosePublicKey(Uint8List bytes) {
    dynamic decoded;
    try {
      decoded = cbor.cbor.decode(bytes, decodeBase64: false);
    } catch (_) {
      throw AuthFlowException('webauthn_public_key_invalid');
    }
    if (decoded is! Map ||
        decoded[1] != 2 ||
        decoded[3] != -7 ||
        decoded[-1] != 1) {
      throw AuthFlowException('webauthn_public_key_unsupported');
    }
    final x = decoded[-2];
    final y = decoded[-3];
    if (x is! List ||
        y is! List ||
        x.length != 32 ||
        y.length != 32 ||
        x.any((value) => value is! int || value < 0 || value > 255) ||
        y.any((value) => value is! int || value < 0 || value > 255)) {
      throw AuthFlowException('webauthn_public_key_invalid');
    }
    return _CoseEs256Key(
      x: Uint8List.fromList(x.cast<int>()),
      y: Uint8List.fromList(y.cast<int>()),
    );
  }

  static Uint8List _decodeField(Map<String, dynamic> response, String key) {
    final value = response[key];
    if (value is! String) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    return _decodeBase64Url(value);
  }

  static Uint8List _decodeBase64Url(String value) {
    if (value.trim().isEmpty || value != value.trim()) {
      throw AuthFlowException('webauthn_encoding_invalid');
    }
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
    } catch (_) {
      throw AuthFlowException('webauthn_encoding_invalid');
    }
  }

  static String _canonicalOrigin(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        (parsed.scheme != 'https' && parsed.scheme != 'http') ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        (parsed.path.isNotEmpty && parsed.path != '/') ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty) {
      throw AuthFlowException('webauthn_origin_invalid');
    }
    final host = parsed.host.toLowerCase();
    final hostText = host.contains(':') ? '[$host]' : host;
    final defaultPort = parsed.scheme == 'https' ? 443 : 80;
    final port = parsed.hasPort && parsed.port != defaultPort
        ? ':${parsed.port}'
        : '';
    return '${parsed.scheme.toLowerCase()}://$hostText$port';
  }

  static String _userHandle(String userId) {
    final bytes = utf8.encode(userId);
    if (bytes.isEmpty || bytes.length > 64) {
      throw AuthFlowException('webauthn_user_invalid');
    }
    return base64UrlNoPadding(bytes);
  }

  static String _validateAttestationPreference(String value) {
    const supported = <String>{'none'};
    if (!supported.contains(value)) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    return value;
  }

  static void _validateUserVerification(String value) {
    if (!const <String>{
      'required',
      'preferred',
      'discouraged',
    }.contains(value)) {
      throw AuthFlowException('webauthn_configuration_invalid');
    }
  }

  static void _requireUserId(AuthUser user) {
    if (user.id.trim().isEmpty) {
      throw AuthFlowException('unauthorized');
    }
  }

  AuthUser _requireInvocationUser(
    AuthOperationInvocation<TContext> invocation,
  ) {
    final user = invocation.user;
    if (user == null) throw AuthFlowException('unauthorized');
    return user;
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> request,
    String key,
  ) {
    final value = request[key];
    if (value is! Map) throw AuthFlowException('invalid_request');
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      throw AuthFlowException('invalid_request');
    }
  }

  static String _requiredString(Map<String, dynamic> request, String key) {
    final value = request[key];
    if (value is! String || value.trim().isEmpty) {
      throw AuthFlowException('invalid_request');
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, dynamic> request, String key) {
    final value = request[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw AuthFlowException('invalid_request');
    }
    return value.trim();
  }
}

final class _ParsedCredential {
  const _ParsedCredential({
    required this.credentialId,
    required this.clientDataJson,
    this.attestationObject,
    this.authenticatorData,
    this.signature,
    this.transports,
    this.name,
  });

  final Uint8List credentialId;
  final Uint8List clientDataJson;
  final Uint8List? attestationObject;
  final Uint8List? authenticatorData;
  final Uint8List? signature;
  final List<String>? transports;
  final String? name;
}

final class _ClientData {
  const _ClientData({required this.challenge});

  final String challenge;
}

final class _ParsedAttestation {
  const _ParsedAttestation({
    required this.credentialId,
    required this.publicKeyCose,
    required this.counter,
  });

  final Uint8List credentialId;
  final Uint8List publicKeyCose;
  final int counter;
}

final class _ParsedAuthenticatorData {
  const _ParsedAuthenticatorData({
    required this.counter,
    this.credentialId,
    this.publicKeyCose,
  });

  final int counter;
  final Uint8List? credentialId;
  final Uint8List? publicKeyCose;
}

final class _CoseEs256Key {
  const _CoseEs256Key({required this.x, required this.y});

  final Uint8List x;
  final Uint8List y;
}

BigInt _bytesToBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

bool _constantTimeBytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
