import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart' as cbor;
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart';
import 'webauthn_store.dart';

/// Stable ID for the opt-in WebAuthn plugin.
const String authWebAuthnPluginId = 'webauthn';

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
      <String, dynamic>{'type': 'public-key', 'alg': -8},
      <String, dynamic>{'type': 'public-key', 'alg': -7},
      <String, dynamic>{'type': 'public-key', 'alg': -257},
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

/// The provenance model established by attestation statement verification.
enum WebAuthnAttestationKind {
  /// No attestation statement or provenance information was supplied.
  none,

  /// The credential key signed its own attestation statement.
  self,

  /// Format verification returned an X.509 attestation trust path.
  certificate,
}

/// A relying-party decision about a cryptographically valid attestation.
enum WebAuthnAttestationTrustDecision {
  /// Accept the attestation under the relying party's configured policy.
  accept,

  /// Fail registration without consuming its challenge.
  reject,

  /// Register an ordinary passkey without claiming hardware provenance.
  downgrade,
}

/// A relying-party decision for `none` or self attestation.
///
/// These forms carry no hardware provenance, so downgrading is not a distinct
/// operation: a relying party can only accept the ordinary passkey or reject
/// the registration.
enum WebAuthnUnprovenAttestationDecision { accept, reject }

/// One certificate in a format-validated WebAuthn attestation trust path.
///
/// [derBytes] is an immutable copy of the certificate supplied by the client.
/// The parser's internal certificate representation is deliberately not
/// exposed. Relying parties can compare [sha256Fingerprint] with a configured
/// trust anchor or pass [derBytes] to their own offline trust implementation.
final class WebAuthnAttestationCertificate {
  WebAuthnAttestationCertificate._(List<int> derBytes)
    : derBytes = List<int>.unmodifiable(List<int>.from(derBytes)),
      sha256Fingerprint = crypto.sha256.convert(derBytes).toString();

  final List<int> derBytes;
  final String sha256Fingerprint;
}

/// Safe output from WebAuthn attestation statement verification.
///
/// This value contains no user, request, parser, or exception details. A trust
/// evaluator receives only the attestation format, provenance model, AAGUID,
/// and the already format-validated certificate path needed for a local trust
/// decision.
final class WebAuthnAttestationMetadata {
  WebAuthnAttestationMetadata._({
    required this.format,
    required this.kind,
    required this.aaguid,
    required List<WebAuthnAttestationCertificate> certificateTrustPath,
  }) : certificateTrustPath = List<WebAuthnAttestationCertificate>.unmodifiable(
         certificateTrustPath,
       );

  final String format;
  final WebAuthnAttestationKind kind;

  /// Lowercase UUID representation of the authenticator AAGUID.
  final String aaguid;

  /// Leaf-first certificate path returned by format verification.
  ///
  /// This is empty for `none` and self attestation. Presence of a path proves
  /// only that the attestation format and supplied chain are cryptographically
  /// valid; it does not mean the root is trusted by the relying party.
  final List<WebAuthnAttestationCertificate> certificateTrustPath;
}

/// Evaluates a certificate-backed attestation after format verification.
typedef WebAuthnCertificateAttestationTrustEvaluator =
    FutureOr<WebAuthnAttestationTrustDecision> Function(
      WebAuthnAttestationMetadata metadata,
    );

/// Explicit relying-party policy for WebAuthn attestation trust.
///
/// The passkey default accepts `none` and self attestation and downgrades
/// certificate-backed attestation to an ordinary passkey. It never silently
/// treats a supplied certificate as a trusted hardware provenance claim.
final class WebAuthnAttestationTrustPolicy {
  const WebAuthnAttestationTrustPolicy({
    this.none = WebAuthnUnprovenAttestationDecision.accept,
    this.self = WebAuthnUnprovenAttestationDecision.accept,
    this.certificate = WebAuthnAttestationTrustDecision.downgrade,
    this.evaluateCertificate,
  }) : _trustedRoots = const <Uint8List>[];

  /// Ordinary-passkey policy with no hardware provenance claim.
  const WebAuthnAttestationTrustPolicy.passkeys()
    : none = WebAuthnUnprovenAttestationDecision.accept,
      self = WebAuthnUnprovenAttestationDecision.accept,
      certificate = WebAuthnAttestationTrustDecision.downgrade,
      evaluateCertificate = null,
      _trustedRoots = const <Uint8List>[];

  /// Trusts paths that terminate at, or are signed by, a configured DER trust
  /// anchor.
  ///
  /// Signature, issuer, and CA path constraints are verified locally. The
  /// authenticator may include the anchor in `x5c`, but normal chains that end
  /// at a leaf or intermediate signed by an omitted anchor are also accepted.
  /// Core does not fetch FIDO metadata or certificate roots from the network.
  factory WebAuthnAttestationTrustPolicy.trustedRoots({
    required Iterable<List<int>> roots,
    WebAuthnUnprovenAttestationDecision none =
        WebAuthnUnprovenAttestationDecision.accept,
    WebAuthnUnprovenAttestationDecision self =
        WebAuthnUnprovenAttestationDecision.accept,
    WebAuthnAttestationTrustDecision untrusted =
        WebAuthnAttestationTrustDecision.reject,
  }) {
    final trustedRoots = roots
        .map((root) {
          if (root.isEmpty || root.length > 16384) {
            throw ArgumentError.value(
              root,
              'roots',
              'must contain bounded DER',
            );
          }
          return Uint8List.fromList(root);
        })
        .toList(growable: false);
    if (trustedRoots.isEmpty) {
      throw ArgumentError.value(roots, 'roots', 'must not be empty');
    }
    return WebAuthnAttestationTrustPolicy._(
      none: none,
      self: self,
      certificate: untrusted,
      trustedRoots: trustedRoots,
    );
  }

  const WebAuthnAttestationTrustPolicy._({
    required this.none,
    required this.self,
    required this.certificate,
    required List<Uint8List> trustedRoots,
  }) : evaluateCertificate = null,
       _trustedRoots = trustedRoots;

  final WebAuthnUnprovenAttestationDecision none;
  final WebAuthnUnprovenAttestationDecision self;

  /// Decision used when [evaluateCertificate] is absent.
  final WebAuthnAttestationTrustDecision certificate;

  /// Optional local trust evaluator for certificate-backed attestation.
  final WebAuthnCertificateAttestationTrustEvaluator? evaluateCertificate;

  final List<Uint8List> _trustedRoots;
}

/// Typed WebAuthn/passkey plugin for `server_auth` runtimes.
///
/// This plugin supports `none` attestation plus cryptographically verified
/// packed self-attestation with EdDSA/Ed25519 (`alg: -8`), ES256 (`alg: -7`),
/// and RS256 (`alg: -257`) passkeys, X.509 certificate-backed ES256 and RS256
/// attestation, Android Key attestation, and FIDO U2F attestation.
/// It deliberately rejects unsupported attestation formats and COSE
/// algorithms instead of accepting an assertion that has not been verified.
/// Certificate verification alone does not establish trusted hardware
/// provenance. Configure [attestationTrustPolicy] when relying-party policy
/// needs to trust or reject particular roots; the default safely downgrades
/// certificate-backed registrations to ordinary passkeys.
/// Applications that need other WebAuthn algorithms can add them after the
/// same parsing and replay guarantees are implemented.
final class WebAuthnPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDeletionPlanContributor {
  WebAuthnPlugin({
    required this.provider,
    this.challengeTtl = const Duration(minutes: 5),
    this.attestationTrustPolicy =
        const WebAuthnAttestationTrustPolicy.passkeys(),
  }) : assert(challengeTtl > Duration.zero);

  final WebAuthnProvider provider;
  final Duration challengeTtl;
  final WebAuthnAttestationTrustPolicy attestationTrustPolicy;

  late AuthWebAuthnChallengeStore _challengeStore;
  late AuthWebAuthnAuthenticatorStore _authenticatorStore;
  late AuthUserStore _userStore;
  late AuthUserDeletionDomain _deletionDomain;
  bool _configured = false;

  @override
  String get id => authWebAuthnPluginId;

  @override
  String get userDataNamespace => 'webauthn';

  @override
  Future<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user) {
    _ensureConfigured();
    if (_deletionDomain is! AuthInMemoryUserDeletionDomain ||
        _challengeStore is! AuthInMemoryUserDeletionStore ||
        _authenticatorStore is! AuthInMemoryUserDeletionStore) {
      throw StateError('The WebAuthn adapter has no plan for this domain.');
    }
    return Future.value(
      AuthInMemoryUserDeletionPlan(
        domain: _deletionDomain as AuthInMemoryUserDeletionDomain,
        userId: user.id,
        namespace: userDataNamespace,
        operation: AuthInMemoryCompositeDeletionOperation([
          AuthInMemoryStoreDeletionOperation(
            store: _challengeStore as AuthInMemoryUserDeletionStore,
            userId: user.id,
          ),
          AuthInMemoryStoreDeletionOperation(
            store: _authenticatorStore as AuthInMemoryUserDeletionStore,
            userId: user.id,
          ),
        ]),
      ),
    );
  }

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final store = context.store;
    if (store is! AuthWebAuthnStoreCapabilities) {
      throw StateError(
        'WebAuthnPlugin requires AuthWebAuthnStoreCapabilities.',
      );
    }
    final capabilities = store as AuthWebAuthnStoreCapabilities;
    _challengeStore = capabilities.webAuthnChallenges;
    _authenticatorStore = capabilities.webAuthnAuthenticators;
    _userStore = context.store.users;
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError(
        'WebAuthnPlugin requires a deletion-coordinator host store.',
      );
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
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
      semantics: _operationSemantics(id),
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

  static AuthOperationSemantics _operationSemantics(String id) {
    switch (id) {
      case 'webauthn.credentialList':
        return const AuthOperationSemantics.readOnly();
      case 'webauthn.registrationOptions':
      case 'webauthn.authenticationOptions':
        return const AuthOperationSemantics.mutation(
          persistence: AuthMutationPersistence.boundedEphemeral(),
          replaySafety: AuthMutationReplaySafety.repeatable,
        );
      case 'webauthn.credentialRename':
        return const AuthOperationSemantics.mutation(
          persistence: AuthMutationPersistence.durable(
            atomicity: AuthMutationAtomicity.atomic,
            reference: AuthPersistenceOperationReference(
              schemaId: authWebAuthnPluginId,
              atomicOperationId: 'authenticator.rename',
            ),
          ),
          replaySafety: AuthMutationReplaySafety.idempotent,
        );
      case 'webauthn.registrationVerify':
      case 'webauthn.authenticationVerify':
      case 'webauthn.credentialDelete':
        return const AuthOperationSemantics.mutation(
          persistence: AuthMutationPersistence.durable(
            atomicity: AuthMutationAtomicity.nonAtomic,
            reference: AuthPersistenceOperationReference(
              schemaId: authWebAuthnPluginId,
            ),
          ),
          replaySafety: AuthMutationReplaySafety.singleUse,
        );
    }
    throw StateError('Unknown WebAuthn operation $id');
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
        final authenticatedUser = invocation.user;
        final options =
            authenticatedUser != null &&
                (userId == null || userId == authenticatedUser.id)
            ? await beginUserBoundAuthentication(
                context: invocation.context,
                user: authenticatedUser,
              )
            : await beginAuthentication(
                context: invocation.context,
                userId: userId,
              );
        return options.toJson();
      case 'webauthn.authenticationVerify':
        final credential = _requiredMap(request, 'credential');
        final result = await finishAuthentication(
          context: invocation.context,
          credential: credential,
          userId: _optionalString(request, 'userId'),
        );
        return AuthEndpointAuthenticationIntent(
          user: result.user,
          authenticationMethod: 'webauthn',
          metadata: <String, dynamic>{
            'status': 'authenticated',
            'credential': result.authenticator.toJson(),
          },
        );
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
      id: authWebAuthnPluginId,
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
    final attestation = await _parseAttestationObject(
      parsed.attestationObject!,
      relyingPartyId: relyingParty.id,
      clientDataHash: Uint8List.fromList(
        crypto.sha256.convert(parsed.clientDataJson).bytes,
      ),
      requireUserVerification:
          provider
              .registrationOptions
              .authenticatorSelection
              ?.userVerification ==
          'required',
    );
    if (!_constantTimeBytesEqual(
      parsed.credentialId,
      attestation.credentialId,
    )) {
      throw AuthFlowException('webauthn_credential_invalid');
    }
    await _applyAttestationTrustPolicy(attestation.metadata);
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

  Future<void> _applyAttestationTrustPolicy(
    WebAuthnAttestationMetadata metadata,
  ) async {
    WebAuthnAttestationTrustDecision decision;
    try {
      decision = switch (metadata.kind) {
        WebAuthnAttestationKind.none =>
          attestationTrustPolicy.none ==
                  WebAuthnUnprovenAttestationDecision.accept
              ? WebAuthnAttestationTrustDecision.accept
              : WebAuthnAttestationTrustDecision.reject,
        WebAuthnAttestationKind.self =>
          attestationTrustPolicy.self ==
                  WebAuthnUnprovenAttestationDecision.accept
              ? WebAuthnAttestationTrustDecision.accept
              : WebAuthnAttestationTrustDecision.reject,
        WebAuthnAttestationKind.certificate =>
          attestationTrustPolicy._trustedRoots.isNotEmpty
              ? await _evaluateTrustedRoots(metadata)
              : attestationTrustPolicy.evaluateCertificate == null
              ? attestationTrustPolicy.certificate
              : await attestationTrustPolicy.evaluateCertificate!(metadata),
      };
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_untrusted');
    }
    if (decision == WebAuthnAttestationTrustDecision.reject) {
      throw AuthFlowException('webauthn_attestation_untrusted');
    }
  }

  Future<WebAuthnAttestationTrustDecision> _evaluateTrustedRoots(
    WebAuthnAttestationMetadata metadata,
  ) async {
    final encodedPath = metadata.certificateTrustPath;
    if (encodedPath.isEmpty) return attestationTrustPolicy.certificate;

    final path = encodedPath
        .map(
          (certificate) =>
              _parsePackedCertificate(Uint8List.fromList(certificate.derBytes)),
        )
        .toList(growable: false);
    for (final intermediate in path.skip(1)) {
      if (!intermediate.isVersion3 ||
          !intermediate.hasBasicConstraints ||
          !intermediate.isCertificateAuthority) {
        return attestationTrustPolicy.certificate;
      }
    }

    final finalCertificate = path.last;
    for (final encodedAnchor in attestationTrustPolicy._trustedRoots) {
      if (_constantTimeBytesEqual(finalCertificate.derBytes, encodedAnchor)) {
        return WebAuthnAttestationTrustDecision.accept;
      }

      _PackedAttestationCertificate anchor;
      try {
        anchor = _parsePackedCertificate(encodedAnchor);
      } on AuthFlowException {
        continue;
      }
      if (!anchor.isVersion3 ||
          !anchor.hasBasicConstraints ||
          !anchor.isCertificateAuthority ||
          !_constantTimeBytesEqual(finalCertificate.issuer, anchor.subject)) {
        continue;
      }
      if (await _verifyCertificateSignature(
        finalCertificate,
        anchor.publicKey,
      )) {
        return WebAuthnAttestationTrustDecision.accept;
      }
    }
    return attestationTrustPolicy.certificate;
  }

  /// Begins a discoverable authentication ceremony.
  ///
  /// [userId] only binds the challenge to an asserted account identifier. It
  /// never looks up that account or exposes its credential IDs, so known and
  /// unknown identifiers produce indistinguishable public options.
  Future<AuthWebAuthnAuthenticationOptions> beginAuthentication({
    required TContext context,
    String? userId,
    DateTime? now,
  }) => _beginAuthentication(context: context, userId: userId, now: now);

  /// Begins a credential-filtered ceremony for an already authenticated user.
  ///
  /// Routes must source [user] from their authenticated principal rather than
  /// from request input. This is the only API that returns `allowCredentials`.
  Future<AuthWebAuthnAuthenticationOptions> beginUserBoundAuthentication({
    required TContext context,
    required AuthUser user,
    DateTime? now,
  }) => _beginAuthentication(
    context: context,
    userId: user.id,
    credentialLookupUserId: user.id,
    now: now,
  );

  Future<AuthWebAuthnAuthenticationOptions> _beginAuthentication({
    required TContext context,
    String? userId,
    String? credentialLookupUserId,
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
    final credentials = credentialLookupUserId == null
        ? const <WebAuthnAuthenticator>[]
        : await _authenticatorStore.listForUser(credentialLookupUserId);
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
    if (!await _verifySignature(
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
      throw StateError('WebAuthnPlugin must be registered with AuthRuntime');
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

  Future<_ParsedAttestation> _parseAttestationObject(
    Uint8List bytes, {
    required String relyingPartyId,
    required Uint8List clientDataHash,
    required bool requireUserVerification,
  }) async {
    dynamic decoded;
    try {
      _StrictCborReader(bytes).validateSingle();
      decoded = cbor.cbor.decode(bytes, decodeBase64: false);
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    if (decoded is! Map || decoded['fmt'] is! String) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final format = decoded['fmt'] as String;
    final statement = decoded['attStmt'];
    if (statement is! Map) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final authData = decoded['authData'];
    if (authData is! List ||
        authData.any((value) => value is! int || value < 0 || value > 255)) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final authDataBytes = Uint8List.fromList(authData.cast<int>());
    final parsed = _parseAuthenticatorData(
      authDataBytes,
      relyingPartyId: relyingPartyId,
      requireAttestedCredential: true,
      requireUserVerification: requireUserVerification,
    );
    final _VerifiedAttestationStatement verifiedStatement;
    if (format == 'none') {
      if (statement.isNotEmpty) {
        throw AuthFlowException('webauthn_attestation_invalid');
      }
      verifiedStatement = const _VerifiedAttestationStatement(
        kind: WebAuthnAttestationKind.none,
      );
    } else if (format == 'packed') {
      verifiedStatement = await _verifyPackedAttestation(
        statement: statement,
        authenticatorData: authDataBytes,
        clientDataHash: clientDataHash,
        credentialPublicKey: parsed.publicKeyCose!,
        aaguid: parsed.aaguid!,
      );
    } else if (format == 'fido-u2f') {
      verifiedStatement = await _verifyFidoU2fAttestation(
        statement: statement,
        authenticatorData: authDataBytes,
        clientDataHash: clientDataHash,
        credentialId: parsed.credentialId!,
        credentialPublicKey: parsed.publicKeyCose!,
      );
    } else if (format == 'android-key') {
      verifiedStatement = await _verifyAndroidKeyAttestation(
        statement: statement,
        authenticatorData: authDataBytes,
        clientDataHash: clientDataHash,
        credentialPublicKey: parsed.publicKeyCose!,
      );
    } else if (format == 'apple') {
      verifiedStatement = await _verifyAppleAttestation(
        statement: statement,
        authenticatorData: authDataBytes,
        clientDataHash: clientDataHash,
        credentialPublicKey: parsed.publicKeyCose!,
      );
    } else if (format == 'tpm') {
      verifiedStatement = await _verifyTpmAttestation(
        statement: statement,
        authenticatorData: authDataBytes,
        clientDataHash: clientDataHash,
        credentialPublicKey: parsed.publicKeyCose!,
        aaguid: parsed.aaguid!,
      );
    } else {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    return _ParsedAttestation(
      credentialId: parsed.credentialId!,
      publicKeyCose: parsed.publicKeyCose!,
      counter: parsed.counter,
      metadata: WebAuthnAttestationMetadata._(
        format: format,
        kind: verifiedStatement.kind,
        aaguid: _formatAaguid(parsed.aaguid!),
        certificateTrustPath: verifiedStatement.certificateTrustPath
            .map(WebAuthnAttestationCertificate._)
            .toList(growable: false),
      ),
    );
  }

  Future<_VerifiedAttestationStatement> _verifyPackedAttestation({
    required Map statement,
    required Uint8List authenticatorData,
    required Uint8List clientDataHash,
    required Uint8List credentialPublicKey,
    required Uint8List aaguid,
  }) async {
    if (statement.containsKey('ecdaaKeyId')) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    final algorithm = statement['alg'];
    final signatureValue = statement['sig'];
    if (algorithm is! int || signatureValue is! List) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    if (signatureValue.any(
      (value) => value is! int || value < 0 || value > 255,
    )) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    if (algorithm != -8 && algorithm != -7 && algorithm != -257) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    final certificateChain = statement['x5c'];
    if (statement.length != (certificateChain == null ? 2 : 3)) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final signedData = Uint8List.fromList(<int>[
      ...authenticatorData,
      ...clientDataHash,
    ]);
    final _CosePublicKey key;
    List<_PackedAttestationCertificate>? certificates;
    if (certificateChain == null) {
      key = _decodeCosePublicKey(credentialPublicKey);
      if (key.algorithm != algorithm) {
        throw AuthFlowException('webauthn_attestation_invalid');
      }
    } else {
      certificates = _parsePackedCertificateChain(
        certificateChain,
        aaguid: aaguid,
      );
      key = certificates.first.publicKey;
      if (key.algorithm != algorithm) {
        throw AuthFlowException('webauthn_attestation_invalid');
      }
      for (var index = 0; index + 1 < certificates.length; index++) {
        final certificate = certificates[index];
        final issuer = certificates[index + 1];
        if (!_constantTimeBytesEqual(certificate.issuer, issuer.subject) ||
            !issuer.isCertificateAuthority ||
            !await _verifyCertificateSignature(certificate, issuer.publicKey)) {
          throw AuthFlowException('webauthn_attestation_invalid');
        }
      }
    }
    if (!await _verifySignatureWithKey(
      key: key,
      algorithm: algorithm,
      message: signedData,
      signature: Uint8List.fromList(signatureValue.cast<int>()),
    )) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    return _VerifiedAttestationStatement(
      kind: certificates == null
          ? WebAuthnAttestationKind.self
          : WebAuthnAttestationKind.certificate,
      certificateTrustPath:
          certificates
              ?.map((certificate) => certificate.derBytes)
              .toList(growable: false) ??
          const <Uint8List>[],
    );
  }

  Future<_VerifiedAttestationStatement> _verifyFidoU2fAttestation({
    required Map statement,
    required Uint8List authenticatorData,
    required Uint8List clientDataHash,
    required Uint8List credentialId,
    required Uint8List credentialPublicKey,
  }) async {
    if (statement.length != 2 ||
        !statement.containsKey('x5c') ||
        !statement.containsKey('sig')) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final certificateChain = statement['x5c'];
    final signatureValue = statement['sig'];
    if (certificateChain is! List ||
        certificateChain.length != 1 ||
        signatureValue is! List ||
        signatureValue.any(
          (value) => value is! int || value < 0 || value > 255,
        )) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final certificateBytes = certificateChain.single;
    if (certificateBytes is! List ||
        certificateBytes.isEmpty ||
        certificateBytes.length > 16384 ||
        certificateBytes.any(
          (value) => value is! int || value < 0 || value > 255,
        )) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }

    final credentialKey = _decodeCosePublicKey(credentialPublicKey);
    if (credentialKey.algorithm != -7 ||
        credentialKey.x == null ||
        credentialKey.y == null) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    final publicKeyU2F = Uint8List.fromList(<int>[
      0x04,
      ...credentialKey.x!,
      ...credentialKey.y!,
    ]);
    final certificateKey = _parseFidoU2fAttestationCertificate(
      Uint8List.fromList(certificateBytes.cast<int>()),
    );
    if (certificateKey.algorithm != -7 ||
        certificateKey.x == null ||
        certificateKey.y == null) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final verificationData = Uint8List.fromList(<int>[
      0x00,
      ...authenticatorData.sublist(0, 32),
      ...clientDataHash,
      ...credentialId,
      ...publicKeyU2F,
    ]);
    if (!await _verifySignatureWithKey(
      key: certificateKey,
      algorithm: -7,
      message: verificationData,
      signature: Uint8List.fromList(signatureValue.cast<int>()),
      derOnly: true,
    )) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    return _VerifiedAttestationStatement(
      kind: WebAuthnAttestationKind.certificate,
      certificateTrustPath: <Uint8List>[
        Uint8List.fromList(certificateBytes.cast<int>()),
      ],
    );
  }

  Future<_VerifiedAttestationStatement> _verifyAndroidKeyAttestation({
    required Map statement,
    required Uint8List authenticatorData,
    required Uint8List clientDataHash,
    required Uint8List credentialPublicKey,
  }) async {
    if (statement.length != 3 ||
        !statement.containsKey('alg') ||
        !statement.containsKey('sig') ||
        !statement.containsKey('x5c')) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final algorithm = statement['alg'];
    final signatureValue = statement['sig'];
    if (algorithm is! int ||
        (algorithm != -8 && algorithm != -7 && algorithm != -257)) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    if (signatureValue is! List ||
        signatureValue.isEmpty ||
        signatureValue.length > 1024 ||
        signatureValue.any(
          (value) => value is! int || value < 0 || value > 255,
        )) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }

    final certificates = _parseAndroidKeyCertificateChain(statement['x5c']);
    final leaf = certificates.first;
    final credentialKey = _decodeCosePublicKey(credentialPublicKey);
    if (leaf.publicKey.algorithm != algorithm ||
        credentialKey.algorithm != algorithm ||
        !_cosePublicKeysEqual(leaf.publicKey, credentialKey)) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    for (var index = 0; index + 1 < certificates.length; index++) {
      final certificate = certificates[index];
      final issuer = certificates[index + 1];
      if (!_constantTimeBytesEqual(certificate.issuer, issuer.subject) ||
          !issuer.hasBasicConstraints ||
          !issuer.isCertificateAuthority ||
          !await _verifyCertificateSignature(certificate, issuer.publicKey)) {
        throw AuthFlowException('webauthn_attestation_invalid');
      }
    }

    final signedData = Uint8List.fromList(<int>[
      ...authenticatorData,
      ...clientDataHash,
    ]);
    if (!await _verifySignatureWithKey(
      key: leaf.publicKey,
      algorithm: algorithm,
      message: signedData,
      signature: Uint8List.fromList(signatureValue.cast<int>()),
      derOnly: algorithm == -7,
    )) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    _validateAndroidKeyAttestationExtension(
      leaf.androidKeyAttestationExtension,
      clientDataHash: clientDataHash,
    );

    return _VerifiedAttestationStatement(
      kind: WebAuthnAttestationKind.certificate,
      certificateTrustPath: certificates
          .map((certificate) => certificate.derBytes)
          .toList(growable: false),
    );
  }

  Future<_VerifiedAttestationStatement> _verifyAppleAttestation({
    required Map statement,
    required Uint8List authenticatorData,
    required Uint8List clientDataHash,
    required Uint8List credentialPublicKey,
  }) async {
    if (statement.length != 1 || !statement.containsKey('x5c')) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final certificates = _parseAppleCertificateChain(statement['x5c']);
    final leaf = certificates.first;
    final credentialKey = _decodeCosePublicKey(credentialPublicKey);
    if (!leaf.isVersion3 ||
        leaf.isCertificateAuthority ||
        !_cosePublicKeysEqual(leaf.publicKey, credentialKey)) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    for (var index = 0; index + 1 < certificates.length; index++) {
      final certificate = certificates[index];
      final issuer = certificates[index + 1];
      if (!_constantTimeBytesEqual(certificate.issuer, issuer.subject) ||
          !issuer.hasBasicConstraints ||
          !issuer.isCertificateAuthority ||
          !await _verifyCertificateSignature(certificate, issuer.publicKey)) {
        throw AuthFlowException('webauthn_attestation_invalid');
      }
    }

    final nonce = Uint8List.fromList(
      crypto.sha256.convert(<int>[
        ...authenticatorData,
        ...clientDataHash,
      ]).bytes,
    );
    _validateAppleNonceExtension(leaf.appleNonceExtension, nonce: nonce);
    return _VerifiedAttestationStatement(
      kind: WebAuthnAttestationKind.certificate,
      certificateTrustPath: certificates
          .map((certificate) => certificate.derBytes)
          .toList(growable: false),
    );
  }

  Future<_VerifiedAttestationStatement> _verifyTpmAttestation({
    required Map statement,
    required Uint8List authenticatorData,
    required Uint8List clientDataHash,
    required Uint8List credentialPublicKey,
    required Uint8List aaguid,
  }) async {
    if (statement.containsKey('ecdaaKeyId')) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    if (statement.length != 6 ||
        statement['ver'] != '2.0' ||
        !statement.containsKey('alg') ||
        !statement.containsKey('sig') ||
        !statement.containsKey('certInfo') ||
        !statement.containsKey('pubArea') ||
        !statement.containsKey('x5c')) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final algorithm = statement['alg'];
    if (algorithm is! int || (algorithm != -7 && algorithm != -257)) {
      throw AuthFlowException('webauthn_attestation_unsupported');
    }
    final signature = _boundedByteString(statement['sig'], maximum: 1024);
    final certInfo = _boundedByteString(statement['certInfo'], maximum: 16384);
    final pubArea = _boundedByteString(statement['pubArea'], maximum: 16384);

    try {
      final credentialKey = _decodeCosePublicKey(credentialPublicKey);
      final parsedPublicArea = _parseTpmPublicArea(pubArea);
      if (!_cosePublicKeysEqual(parsedPublicArea.publicKey, credentialKey)) {
        throw const FormatException();
      }

      final certificates = _parseTpmCertificateChain(
        statement['x5c'],
        aaguid: aaguid,
      );
      final leaf = certificates.first;
      if (leaf.publicKey.algorithm != algorithm) {
        throw const FormatException();
      }
      for (var index = 0; index + 1 < certificates.length; index++) {
        final certificate = certificates[index];
        final issuer = certificates[index + 1];
        if (!_constantTimeBytesEqual(certificate.issuer, issuer.subject) ||
            !issuer.hasBasicConstraints ||
            !issuer.isCertificateAuthority ||
            !await _verifyCertificateSignature(certificate, issuer.publicKey)) {
          throw const FormatException();
        }
      }
      if (!await _verifySignatureWithKey(
        key: leaf.publicKey,
        algorithm: algorithm,
        message: certInfo,
        signature: signature,
        derOnly: algorithm == -7,
      )) {
        throw const FormatException();
      }

      final parsedCertInfo = _parseTpmCertInfo(certInfo);
      final expectedExtraData = Uint8List.fromList(
        crypto.sha256.convert(<int>[
          ...authenticatorData,
          ...clientDataHash,
        ]).bytes,
      );
      if (!_constantTimeBytesEqual(
        parsedCertInfo.extraData,
        expectedExtraData,
      )) {
        throw const FormatException();
      }
      final expectedName = Uint8List.fromList(<int>[
        (parsedPublicArea.nameAlgorithm >> 8) & 0xff,
        parsedPublicArea.nameAlgorithm & 0xff,
        ..._tpmDigest(parsedPublicArea.nameAlgorithm, pubArea),
      ]);
      if (!_constantTimeBytesEqual(parsedCertInfo.name, expectedName)) {
        throw const FormatException();
      }

      return _VerifiedAttestationStatement(
        kind: WebAuthnAttestationKind.certificate,
        certificateTrustPath: certificates
            .map((certificate) => certificate.derBytes)
            .toList(growable: false),
      );
    } on AuthFlowException catch (error) {
      if (error.code == 'webauthn_attestation_unsupported') rethrow;
      throw AuthFlowException('webauthn_attestation_invalid');
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
  }

  Uint8List _boundedByteString(Object? value, {required int maximum}) {
    if (value is! List ||
        value.isEmpty ||
        value.length > maximum ||
        value.any((byte) => byte is! int || byte < 0 || byte > 255)) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    return Uint8List.fromList(value.cast<int>());
  }

  _TpmPublicArea _parseTpmPublicArea(Uint8List bytes) {
    final reader = _TpmReader(bytes);
    final type = reader.uint16();
    final nameAlgorithm = reader.uint16();
    _tpmDigest(nameAlgorithm, const <int>[]);
    reader.uint32(); // objectAttributes
    reader.sized(maximum: 1024); // authPolicy

    late final _CosePublicKey publicKey;
    switch (type) {
      case 0x0001: // TPM_ALG_RSA
        _readTpmNullSymmetricDefinition(reader);
        _readTpmScheme(reader, expected: 0x0014); // TPM_ALG_RSASSA
        final keyBits = reader.uint16();
        final encodedExponent = reader.uint32();
        final modulus = reader.sized(maximum: 1024);
        final exponent = encodedExponent == 0 ? 65537 : encodedExponent;
        if (keyBits < 2048 ||
            keyBits > 8192 ||
            modulus.length != (keyBits + 7) ~/ 8 ||
            exponent < 3 ||
            exponent.isEven) {
          throw const FormatException();
        }
        publicKey = _CosePublicKey(
          algorithm: -257,
          modulus: modulus,
          exponent: _unsignedIntBytes(exponent),
        );
      case 0x0023: // TPM_ALG_ECC
        _readTpmNullSymmetricDefinition(reader);
        _readTpmScheme(reader, expected: 0x0018); // TPM_ALG_ECDSA
        if (reader.uint16() != 0x0003) throw const FormatException();
        if (reader.uint16() != 0x0010) throw const FormatException();
        final x = reader.sized(maximum: 66);
        final y = reader.sized(maximum: 66);
        if (x.length != 32 || y.length != 32) {
          throw const FormatException();
        }
        publicKey = _CosePublicKey(algorithm: -7, x: x, y: y);
      default:
        throw AuthFlowException('webauthn_attestation_unsupported');
    }
    reader.requireEnd();
    return _TpmPublicArea(nameAlgorithm: nameAlgorithm, publicKey: publicKey);
  }

  void _readTpmNullSymmetricDefinition(_TpmReader reader) {
    if (reader.uint16() != 0x0010) throw const FormatException();
  }

  void _readTpmScheme(_TpmReader reader, {required int expected}) {
    final scheme = reader.uint16();
    if (scheme == 0x0010) return;
    if (scheme != expected || reader.uint16() != 0x000b) {
      throw const FormatException();
    }
  }

  _TpmCertInfo _parseTpmCertInfo(Uint8List bytes) {
    final reader = _TpmReader(bytes);
    if (reader.uint32() != 0xff544347 || reader.uint16() != 0x8017) {
      throw const FormatException();
    }
    reader.sized(maximum: 1024); // qualifiedSigner
    final extraData = reader.sized(maximum: 64);
    reader.uint64(); // clock
    reader.uint32(); // resetCount
    reader.uint32(); // restartCount
    final safe = reader.uint8();
    if (safe != 0 && safe != 1) throw const FormatException();
    reader.uint64(); // firmwareVersion
    final name = reader.sized(maximum: 128);
    reader.sized(maximum: 128); // qualifiedName
    reader.requireEnd();
    if (extraData.length != 32 || name.length < 22 || name.length > 66) {
      throw const FormatException();
    }
    return _TpmCertInfo(extraData: extraData, name: name);
  }

  List<_PackedAttestationCertificate> _parseTpmCertificateChain(
    Object? value, {
    required Uint8List aaguid,
  }) {
    if (value is! List || value.isEmpty || value.length > 8) {
      throw const FormatException();
    }
    final certificates = <_PackedAttestationCertificate>[];
    for (final item in value) {
      certificates.add(
        _parsePackedCertificate(_boundedByteString(item, maximum: 16384)),
      );
    }
    final leaf = certificates.first;
    if (!leaf.isVersion3 ||
        !_isEmptyX509Name(leaf.subject) ||
        !leaf.hasTpmSubjectAlternativeName ||
        !leaf.hasTpmAikExtendedKeyUsage ||
        !leaf.hasBasicConstraints ||
        leaf.isCertificateAuthority ||
        (leaf.aaguid != null &&
            !_constantTimeBytesEqual(leaf.aaguid!, aaguid))) {
      throw const FormatException();
    }
    return certificates;
  }

  bool _isEmptyX509Name(Uint8List encodedName) {
    try {
      final parser = ASN1Parser(encodedName);
      final name = parser.nextObject();
      return !parser.hasNext() &&
          name is ASN1Sequence &&
          (name.elements?.isEmpty ?? true);
    } catch (_) {
      return false;
    }
  }

  Uint8List _unsignedIntBytes(int value) {
    if (value <= 0) throw const FormatException();
    final bytes = <int>[];
    var remaining = value;
    while (remaining != 0) {
      bytes.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List _tpmDigest(int algorithm, List<int> bytes) =>
      Uint8List.fromList(switch (algorithm) {
        0x0004 => crypto.sha1.convert(bytes).bytes,
        0x000b => crypto.sha256.convert(bytes).bytes,
        0x000c => crypto.sha384.convert(bytes).bytes,
        0x000d => crypto.sha512.convert(bytes).bytes,
        _ => throw const FormatException(),
      });

  List<_PackedAttestationCertificate> _parseAppleCertificateChain(
    Object? value,
  ) {
    if (value is! List || value.isEmpty || value.length > 8) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    try {
      final certificates = <_PackedAttestationCertificate>[];
      for (final item in value) {
        if (item is! List ||
            item.isEmpty ||
            item.length > 16384 ||
            item.any((byte) => byte is! int || byte < 0 || byte > 255)) {
          throw const FormatException();
        }
        certificates.add(
          _parsePackedCertificate(Uint8List.fromList(item.cast<int>())),
        );
      }
      if (certificates.first.appleNonceExtension == null) {
        throw const FormatException();
      }
      return certificates;
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
  }

  void _validateAppleNonceExtension(
    Uint8List? extension, {
    required Uint8List nonce,
  }) {
    try {
      if (extension == null || extension.isEmpty || extension.length > 1024) {
        throw const FormatException();
      }
      final sequence = _DerReader(extension).readSingle();
      final fields = _derChildren(sequence, universalTag: 16, maxElements: 2);
      if (fields.length != 1) throw const FormatException();
      final certificateNonce = _derOctets(fields.single);
      if (certificateNonce.length != 32 ||
          !_constantTimeBytesEqual(certificateNonce, nonce)) {
        throw const FormatException();
      }
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
  }

  List<_PackedAttestationCertificate> _parseAndroidKeyCertificateChain(
    Object? value,
  ) {
    if (value is! List || value.isEmpty || value.length > 8) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    try {
      final certificates = <_PackedAttestationCertificate>[];
      for (final item in value) {
        if (item is! List ||
            item.isEmpty ||
            item.length > 16384 ||
            item.any((byte) => byte is! int || byte < 0 || byte > 255)) {
          throw const FormatException();
        }
        certificates.add(
          _parsePackedCertificate(Uint8List.fromList(item.cast<int>())),
        );
      }
      if (certificates.first.androidKeyAttestationExtension == null) {
        throw const FormatException();
      }
      return certificates;
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
  }

  void _validateAndroidKeyAttestationExtension(
    Uint8List? extension, {
    required Uint8List clientDataHash,
  }) {
    try {
      if (extension == null || extension.isEmpty || extension.length > 16384) {
        throw const FormatException();
      }
      final description = _DerReader(extension).readSingle();
      final fields = _derChildren(
        description,
        universalTag: 16,
        maxElements: 8,
      );
      if (fields.length != 8) throw const FormatException();
      _derUnsignedInteger(fields[0], universalTag: 2);
      _derUnsignedInteger(fields[1], universalTag: 10);
      _derUnsignedInteger(fields[2], universalTag: 2);
      _derUnsignedInteger(fields[3], universalTag: 10);
      final challenge = _derOctets(fields[4]);
      _derOctets(fields[5]);
      if (!_constantTimeBytesEqual(challenge, clientDataHash)) {
        throw const FormatException();
      }
      final software = _parseAndroidAuthorizationList(fields[6]);
      final tee = _parseAndroidAuthorizationList(fields[7]);
      if (software.hasAllApplications || tee.hasAllApplications) {
        throw const FormatException();
      }
      final origins = <int>{
        if (software.origin != null) software.origin!,
        if (tee.origin != null) tee.origin!,
      };
      if (origins.length != 1 || origins.single != 0) {
        throw const FormatException();
      }
      final purposes = <int>{...software.purposes, ...tee.purposes};
      if (purposes.length != 1 || purposes.single != 2) {
        throw const FormatException();
      }
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
  }

  _AndroidAuthorizationList _parseAndroidAuthorizationList(_DerValue value) {
    final fields = _derChildren(value, universalTag: 16, maxElements: 64);
    final seenTags = <int>{};
    var hasAllApplications = false;
    int? origin;
    var purposes = const <int>{};
    for (final field in fields) {
      if (field.tagClass != 2 || !field.constructed || field.tagNumber > 4096) {
        throw const FormatException();
      }
      if (!seenTags.add(field.tagNumber)) throw const FormatException();
      final explicitValue = _DerReader(field.value).readSingle();
      switch (field.tagNumber) {
        case 1:
          final values = _derChildren(
            explicitValue,
            universalTag: 17,
            maxElements: 16,
          );
          final parsed = <int>{};
          for (final purpose in values) {
            if (!parsed.add(_derUnsignedInteger(purpose, universalTag: 2))) {
              throw const FormatException();
            }
          }
          purposes = Set<int>.unmodifiable(parsed);
        case 600:
          if (explicitValue.tagClass != 0 ||
              explicitValue.tagNumber != 5 ||
              explicitValue.constructed ||
              explicitValue.value.isNotEmpty) {
            throw const FormatException();
          }
          hasAllApplications = true;
        case 702:
          origin = _derUnsignedInteger(explicitValue, universalTag: 2);
      }
    }
    return _AndroidAuthorizationList(
      purposes: purposes,
      origin: origin,
      hasAllApplications: hasAllApplications,
    );
  }

  _CosePublicKey _parseFidoU2fAttestationCertificate(Uint8List bytes) {
    try {
      final parser = ASN1Parser(bytes);
      final certificate = parser.nextObject();
      if (parser.hasNext() || certificate is! ASN1Sequence) {
        throw const FormatException();
      }
      final certificateElements = certificate.elements;
      if (certificateElements == null || certificateElements.length != 3) {
        throw const FormatException();
      }
      final tbsCertificate = certificateElements[0];
      final signatureAlgorithm = certificateElements[1];
      final signatureValue = certificateElements[2];
      if (tbsCertificate is! ASN1Sequence ||
          signatureAlgorithm is! ASN1Sequence ||
          signatureValue is! ASN1BitString ||
          signatureValue.unusedbits != 0 ||
          signatureValue.stringValues == null ||
          signatureValue.stringValues!.isEmpty) {
        throw const FormatException();
      }
      final elements = tbsCertificate.elements;
      if (elements == null) throw const FormatException();
      var offset = 0;
      if (elements.isNotEmpty && elements.first.tag == 0xa0) {
        final versionParser = ASN1Parser(elements.first.valueBytes);
        final version = versionParser.nextObject();
        if (versionParser.hasNext() || version is! ASN1Integer) {
          throw const FormatException();
        }
        offset = 1;
      }
      if (elements.length < offset + 6 ||
          elements[offset] is! ASN1Integer ||
          elements[offset + 1] is! ASN1Sequence ||
          elements[offset + 2] is! ASN1Sequence ||
          elements[offset + 3] is! ASN1Sequence ||
          elements[offset + 4] is! ASN1Sequence ||
          elements[offset + 5] is! ASN1Sequence) {
        throw const FormatException();
      }
      final tbsSignatureAlgorithm = elements[offset + 1];
      if (!_constantTimeBytesEqual(
        tbsSignatureAlgorithm.encodedBytes!,
        signatureAlgorithm.encodedBytes!,
      )) {
        throw const FormatException();
      }
      final validity = elements[offset + 3] as ASN1Sequence;
      final validityElements = validity.elements;
      if (validityElements == null ||
          validityElements.length != 2 ||
          validityElements.any(
            (value) => value is! ASN1UtcTime && value is! ASN1GeneralizedTime,
          )) {
        throw const FormatException();
      }
      return _certificatePublicKey(elements[offset + 5] as ASN1Sequence);
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
  }

  List<_PackedAttestationCertificate> _parsePackedCertificateChain(
    Object value, {
    required Uint8List aaguid,
  }) {
    if (value is! List || value.isEmpty || value.length > 8) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    final certificates = <_PackedAttestationCertificate>[];
    for (final item in value) {
      if (item is! List ||
          item.isEmpty ||
          item.length > 16384 ||
          item.any((byte) => byte is! int || byte < 0 || byte > 255)) {
        throw AuthFlowException('webauthn_attestation_invalid');
      }
      certificates.add(
        _parsePackedCertificate(Uint8List.fromList(item.cast<int>())),
      );
    }
    final leaf = certificates.first;
    if (!leaf.isVersion3 ||
        !leaf.hasBasicConstraints ||
        leaf.isCertificateAuthority ||
        leaf.country?.isNotEmpty != true ||
        leaf.organization?.isNotEmpty != true ||
        leaf.organizationalUnit != 'Authenticator Attestation' ||
        leaf.commonName?.isNotEmpty != true ||
        (leaf.aaguid != null &&
            !_constantTimeBytesEqual(leaf.aaguid!, aaguid))) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
    return certificates;
  }

  _PackedAttestationCertificate _parsePackedCertificate(Uint8List bytes) {
    try {
      final parser = ASN1Parser(bytes);
      final certificate = parser.nextObject();
      if (parser.hasNext() || certificate is! ASN1Sequence) {
        throw const FormatException();
      }
      final certificateElements = certificate.elements;
      if (certificateElements == null || certificateElements.length != 3) {
        throw const FormatException();
      }
      final tbsCertificate = certificateElements[0];
      final signatureAlgorithm = certificateElements[1];
      final signatureValue = certificateElements[2];
      if (tbsCertificate is! ASN1Sequence ||
          signatureAlgorithm is! ASN1Sequence ||
          signatureValue is! ASN1BitString ||
          signatureValue.unusedbits != 0 ||
          signatureValue.stringValues == null) {
        throw const FormatException();
      }
      final elements = tbsCertificate.elements;
      if (elements == null || elements.length < 7) {
        throw const FormatException();
      }
      var offset = 0;
      var isVersion3 = false;
      if (elements.first.tag == 0xa0) {
        final versionParser = ASN1Parser(elements.first.valueBytes);
        final version = versionParser.nextObject();
        if (versionParser.hasNext() || version is! ASN1Integer) {
          throw const FormatException();
        }
        isVersion3 = version.integer == BigInt.two;
        offset = 1;
      }
      if (elements.length < offset + 7) throw const FormatException();
      final tbsSignatureAlgorithm = elements[offset + 1];
      final issuer = elements[offset + 2];
      final validity = elements[offset + 3];
      final subject = elements[offset + 4];
      final subjectPublicKeyInfo = elements[offset + 5];
      if (issuer is! ASN1Sequence ||
          tbsSignatureAlgorithm is! ASN1Sequence ||
          validity is! ASN1Sequence ||
          subject is! ASN1Sequence ||
          subjectPublicKeyInfo is! ASN1Sequence) {
        throw const FormatException();
      }
      if (!_constantTimeBytesEqual(
        tbsSignatureAlgorithm.encodedBytes!,
        signatureAlgorithm.encodedBytes!,
      )) {
        throw const FormatException();
      }
      _validateCertificateValidity(validity);
      final names = _certificateNames(subject);
      var hasBasicConstraints = false;
      var isCertificateAuthority = false;
      var hasTpmSubjectAlternativeName = false;
      var hasTpmAikExtendedKeyUsage = false;
      Uint8List? certificateAaguid;
      Uint8List? androidKeyAttestationExtension;
      Uint8List? appleNonceExtension;
      final extensionIdentifiers = <String>{};
      for (final element in elements.skip(offset + 6)) {
        if (element.tag != 0xa3) continue;
        final extensionParser = ASN1Parser(element.valueBytes);
        final extensions = extensionParser.nextObject();
        if (extensionParser.hasNext() || extensions is! ASN1Sequence) {
          throw const FormatException();
        }
        for (final extension in extensions.elements ?? const <ASN1Object>[]) {
          if (extension is! ASN1Sequence) throw const FormatException();
          final extensionElements = extension.elements;
          if (extensionElements == null ||
              (extensionElements.length != 2 &&
                  extensionElements.length != 3)) {
            throw const FormatException();
          }
          final identifier = extensionElements.first;
          final value = extensionElements.last;
          if (identifier is! ASN1ObjectIdentifier ||
              value is! ASN1OctetString) {
            throw const FormatException();
          }
          final extensionIdentifier = identifier.objectIdentifierAsString;
          if (extensionIdentifier == null ||
              !extensionIdentifiers.add(extensionIdentifier)) {
            throw const FormatException();
          }
          final isCritical = extensionElements.length == 3;
          if (isCritical && extensionElements[1] is! ASN1Boolean) {
            throw const FormatException();
          }
          if (extensionIdentifier == '2.5.29.19') {
            if (hasBasicConstraints) throw const FormatException();
            final basicConstraintsParser = ASN1Parser(value.octets);
            final basicConstraints = basicConstraintsParser.nextObject();
            if (basicConstraintsParser.hasNext() ||
                basicConstraints is! ASN1Sequence) {
              throw const FormatException();
            }
            hasBasicConstraints = true;
            final fields = basicConstraints.elements ?? const <ASN1Object>[];
            if (fields.length > 2 ||
                (fields.isNotEmpty && fields.first is! ASN1Boolean) ||
                (fields.length == 2 && fields[1] is! ASN1Integer)) {
              throw const FormatException();
            }
            if (fields.isNotEmpty) {
              isCertificateAuthority =
                  (fields.first as ASN1Boolean).boolValue == true;
              if (!isCertificateAuthority && fields.length == 2) {
                throw const FormatException();
              }
            }
          } else if (extensionIdentifier == '2.5.29.17') {
            hasTpmSubjectAlternativeName =
                isCritical &&
                (extensionElements[1] as ASN1Boolean).boolValue == true &&
                _hasTpmSubjectAlternativeName(value.octets);
          } else if (extensionIdentifier == '2.5.29.37') {
            hasTpmAikExtendedKeyUsage = _hasTpmAikExtendedKeyUsage(
              value.octets,
            );
          } else if (extensionIdentifier == '1.3.6.1.4.1.45724.1.1.4') {
            if (isCritical &&
                (extensionElements[1] as ASN1Boolean).boolValue == true) {
              throw const FormatException();
            }
            final encodedAaguid = ASN1Parser(value.octets).nextObject();
            if (encodedAaguid is! ASN1OctetString ||
                encodedAaguid.octets?.length != 16) {
              throw const FormatException();
            }
            certificateAaguid = Uint8List.fromList(encodedAaguid.octets!);
          } else if (extensionIdentifier == '1.3.6.1.4.1.11129.2.1.17') {
            if (androidKeyAttestationExtension != null ||
                value.octets == null ||
                value.octets!.isEmpty ||
                value.octets!.length > 16384) {
              throw const FormatException();
            }
            androidKeyAttestationExtension = Uint8List.fromList(value.octets!);
          } else if (extensionIdentifier == '1.2.840.113635.100.8.2') {
            if (value.octets == null ||
                value.octets!.isEmpty ||
                value.octets!.length > 1024) {
              throw const FormatException();
            }
            appleNonceExtension = Uint8List.fromList(value.octets!);
          }
        }
      }
      return _PackedAttestationCertificate(
        derBytes: Uint8List.fromList(bytes),
        tbsCertificate: Uint8List.fromList(tbsCertificate.encodedBytes!),
        signatureAlgorithm: _certificateSignatureAlgorithm(signatureAlgorithm),
        signature: Uint8List.fromList(signatureValue.stringValues!),
        publicKey: _certificatePublicKey(subjectPublicKeyInfo),
        issuer: Uint8List.fromList(issuer.encodedBytes!),
        subject: Uint8List.fromList(subject.encodedBytes!),
        isVersion3: isVersion3,
        hasBasicConstraints: hasBasicConstraints,
        isCertificateAuthority: isCertificateAuthority,
        hasTpmSubjectAlternativeName: hasTpmSubjectAlternativeName,
        hasTpmAikExtendedKeyUsage: hasTpmAikExtendedKeyUsage,
        country: names['2.5.4.6'],
        organization: names['2.5.4.10'],
        organizationalUnit: names['2.5.4.11'],
        commonName: names['2.5.4.3'],
        aaguid: certificateAaguid,
        androidKeyAttestationExtension: androidKeyAttestationExtension,
        appleNonceExtension: appleNonceExtension,
      );
    } catch (_) {
      throw AuthFlowException('webauthn_attestation_invalid');
    }
  }

  bool _hasTpmSubjectAlternativeName(Uint8List? bytes) {
    try {
      if (bytes == null || bytes.isEmpty || bytes.length > 4096) {
        return false;
      }
      final parser = ASN1Parser(bytes);
      final generalNames = parser.nextObject();
      if (parser.hasNext() || generalNames is! ASN1Sequence) return false;
      var validDirectoryName = false;
      for (final generalName in generalNames.elements ?? const <ASN1Object>[]) {
        if (generalName.tag != 0xa4 || generalName.valueBytes == null) continue;
        final nameParser = ASN1Parser(generalName.valueBytes);
        final name = nameParser.nextObject();
        if (nameParser.hasNext() || name is! ASN1Sequence) return false;
        final attributes = <String, String>{};
        for (final relativeName in name.elements ?? const <ASN1Object>[]) {
          if (relativeName is! ASN1Set) return false;
          for (final attribute
              in relativeName.elements ?? const <ASN1Object>[]) {
            if (attribute is! ASN1Sequence || attribute.elements?.length != 2) {
              return false;
            }
            final identifier = attribute.elements![0];
            final value = attribute.elements![1];
            if (identifier is! ASN1ObjectIdentifier ||
                value is! ASN1UTF8String ||
                value.valueBytes == null ||
                value.valueBytes!.isEmpty ||
                value.valueBytes!.length > 256) {
              return false;
            }
            final oid = identifier.objectIdentifierAsString;
            if (oid == null || attributes.containsKey(oid)) return false;
            attributes[oid] = utf8.decode(
              value.valueBytes!,
              allowMalformed: false,
            );
          }
        }
        if (_isTpmHexIdentifier(attributes['2.23.133.2.1']) &&
            attributes['2.23.133.2.2']?.trim().isNotEmpty == true &&
            _isTpmHexIdentifier(attributes['2.23.133.2.3'])) {
          validDirectoryName = true;
        }
      }
      return validDirectoryName;
    } catch (_) {
      return false;
    }
  }

  bool _isTpmHexIdentifier(String? value) {
    if (value == null || value.length != 11 || !value.startsWith('id:')) {
      return false;
    }
    for (final codeUnit in value.codeUnits.skip(3)) {
      final decimal = codeUnit >= 0x30 && codeUnit <= 0x39;
      final uppercase = codeUnit >= 0x41 && codeUnit <= 0x46;
      final lowercase = codeUnit >= 0x61 && codeUnit <= 0x66;
      if (!decimal && !uppercase && !lowercase) return false;
    }
    return true;
  }

  bool _hasTpmAikExtendedKeyUsage(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty || bytes.length > 4096) {
      throw const FormatException();
    }
    final parser = ASN1Parser(bytes);
    final sequence = parser.nextObject();
    if (parser.hasNext() || sequence is! ASN1Sequence) {
      throw const FormatException();
    }
    final identifiers = <String>{};
    for (final value in sequence.elements ?? const <ASN1Object>[]) {
      if (value is! ASN1ObjectIdentifier) throw const FormatException();
      final identifier = value.objectIdentifierAsString;
      if (identifier == null || !identifiers.add(identifier)) {
        throw const FormatException();
      }
    }
    return identifiers.contains('2.23.133.8.3');
  }

  void _validateCertificateValidity(ASN1Sequence validity) {
    final elements = validity.elements;
    if (elements == null || elements.length != 2) {
      throw const FormatException();
    }
    DateTime? date(ASN1Object value) => switch (value) {
      ASN1UtcTime() => value.time,
      ASN1GeneralizedTime() => value.dateTimeValue,
      _ => null,
    };

    final notBefore = date(elements[0])?.toUtc();
    final notAfter = date(elements[1])?.toUtc();
    final current = DateTime.now().toUtc();
    if (notBefore == null ||
        notAfter == null ||
        current.isBefore(notBefore) ||
        current.isAfter(notAfter)) {
      throw const FormatException();
    }
  }

  Map<String, String> _certificateNames(ASN1Sequence name) {
    final result = <String, String>{};
    for (final relativeName in name.elements ?? const <ASN1Object>[]) {
      if (relativeName is! ASN1Set) throw const FormatException();
      for (final attribute in relativeName.elements ?? const <ASN1Object>[]) {
        if (attribute is! ASN1Sequence || attribute.elements?.length != 2) {
          throw const FormatException();
        }
        final identifier = attribute.elements![0];
        final value = attribute.elements![1];
        if (identifier is! ASN1ObjectIdentifier || value.valueBytes == null) {
          throw const FormatException();
        }
        final objectIdentifier = identifier.objectIdentifierAsString;
        if ((objectIdentifier == '2.5.4.6' && value is! ASN1PrintableString) ||
            (const <String>{
                  '2.5.4.3',
                  '2.5.4.10',
                  '2.5.4.11',
                }.contains(objectIdentifier) &&
                value is! ASN1UTF8String)) {
          throw const FormatException();
        }
        final decoded = utf8.decode(value.valueBytes!, allowMalformed: false);
        result[objectIdentifier!] = decoded;
      }
    }
    return result;
  }

  int _certificateSignatureAlgorithm(ASN1Sequence algorithm) {
    final elements = algorithm.elements;
    if (elements == null ||
        elements.isEmpty ||
        elements.first is! ASN1ObjectIdentifier) {
      throw const FormatException();
    }
    return switch ((elements.first as ASN1ObjectIdentifier)
        .objectIdentifierAsString) {
      '1.2.840.10045.4.3.2' => -7,
      '1.2.840.113549.1.1.11' => -257,
      '1.3.101.112' => -8,
      _ => throw const FormatException(),
    };
  }

  _CosePublicKey _certificatePublicKey(ASN1Sequence subjectPublicKeyInfo) {
    final elements = subjectPublicKeyInfo.elements;
    if (elements == null ||
        elements.length != 2 ||
        elements[0] is! ASN1Sequence ||
        elements[1] is! ASN1BitString) {
      throw const FormatException();
    }
    final algorithm = elements[0] as ASN1Sequence;
    final keyBits = elements[1] as ASN1BitString;
    final algorithmElements = algorithm.elements;
    final keyBytes = keyBits.stringValues;
    if (keyBits.unusedbits != 0 ||
        algorithmElements == null ||
        algorithmElements.isEmpty ||
        algorithmElements.first is! ASN1ObjectIdentifier ||
        keyBytes == null) {
      throw const FormatException();
    }
    final identifier = (algorithmElements.first as ASN1ObjectIdentifier)
        .objectIdentifierAsString;
    if (identifier == '1.2.840.10045.2.1') {
      if (algorithmElements.length != 2 ||
          algorithmElements[1] is! ASN1ObjectIdentifier ||
          (algorithmElements[1] as ASN1ObjectIdentifier)
                  .objectIdentifierAsString !=
              '1.2.840.10045.3.1.7' ||
          keyBytes.length != 65 ||
          keyBytes.first != 0x04) {
        throw const FormatException();
      }
      return _CosePublicKey(
        algorithm: -7,
        x: Uint8List.fromList(keyBytes.sublist(1, 33)),
        y: Uint8List.fromList(keyBytes.sublist(33)),
      );
    }
    if (identifier == '1.2.840.113549.1.1.1') {
      final parser = ASN1Parser(Uint8List.fromList(keyBytes));
      final rsaKey = parser.nextObject();
      if (parser.hasNext() ||
          rsaKey is! ASN1Sequence ||
          rsaKey.elements?.length != 2) {
        throw const FormatException();
      }
      final modulus = rsaKey.elements![0];
      final exponent = rsaKey.elements![1];
      if (modulus is! ASN1Integer || exponent is! ASN1Integer) {
        throw const FormatException();
      }
      final modulusBytes = _bigIntToUnsignedBytes(modulus.integer!);
      final exponentBytes = _bigIntToUnsignedBytes(exponent.integer!);
      if (modulusBytes.length < 256 ||
          modulusBytes.length > 1024 ||
          exponentBytes.length > 8) {
        throw const FormatException();
      }
      return _CosePublicKey(
        algorithm: -257,
        modulus: modulusBytes,
        exponent: exponentBytes,
      );
    }
    if (identifier == '1.3.101.112') {
      if (algorithmElements.length != 1 || keyBytes.length != 32) {
        throw const FormatException();
      }
      return _CosePublicKey(
        algorithm: -8,
        ed25519PublicKey: Uint8List.fromList(keyBytes),
      );
    }
    throw const FormatException();
  }

  bool _cosePublicKeysEqual(_CosePublicKey first, _CosePublicKey second) {
    if (first.algorithm != second.algorithm) return false;
    return switch (first.algorithm) {
      -8 =>
        first.ed25519PublicKey != null &&
            second.ed25519PublicKey != null &&
            _constantTimeBytesEqual(
              first.ed25519PublicKey!,
              second.ed25519PublicKey!,
            ),
      -7 =>
        first.x != null &&
            first.y != null &&
            second.x != null &&
            second.y != null &&
            _constantTimeBytesEqual(first.x!, second.x!) &&
            _constantTimeBytesEqual(first.y!, second.y!),
      -257 =>
        first.modulus != null &&
            first.exponent != null &&
            second.modulus != null &&
            second.exponent != null &&
            _constantTimeBytesEqual(first.modulus!, second.modulus!) &&
            _constantTimeBytesEqual(first.exponent!, second.exponent!),
      _ => false,
    };
  }

  Future<bool> _verifyCertificateSignature(
    _PackedAttestationCertificate certificate,
    _CosePublicKey issuerKey,
  ) => _verifySignatureWithKey(
    key: issuerKey,
    algorithm: certificate.signatureAlgorithm,
    message: certificate.tbsCertificate,
    signature: certificate.signature,
  );

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
      aaguid: Uint8List.fromList(bytes.sublist(37, 53)),
    );
  }

  Future<bool> _verifySignature({
    required Uint8List coseKey,
    required Uint8List message,
    required Uint8List signature,
  }) async {
    try {
      final key = _decodeCosePublicKey(coseKey);
      return await _verifySignatureWithKey(
        key: key,
        algorithm: key.algorithm,
        message: message,
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifySignatureWithKey({
    required _CosePublicKey key,
    required int algorithm,
    required Uint8List message,
    required Uint8List signature,
    bool derOnly = false,
  }) async {
    try {
      switch (algorithm) {
        case -8:
          final publicKey = key.ed25519PublicKey;
          if (publicKey == null ||
              publicKey.length != 32 ||
              signature.length != 64) {
            return false;
          }
          return await cryptography.Ed25519().verify(
            message,
            signature: cryptography.Signature(
              signature,
              publicKey: cryptography.SimplePublicKey(
                publicKey,
                type: cryptography.KeyPairType.ed25519,
              ),
            ),
          );
        case -7:
          if (key.x == null || key.y == null) {
            return false;
          }
          final parameters = ECDomainParameters('secp256r1');
          final point = parameters.curve.createPoint(
            _bytesToBigInt(key.x!),
            _bytesToBigInt(key.y!),
          );
          if (point.isInfinity) return false;
          final parsedSignature = _decodeEs256Signature(
            signature,
            parameters,
            derOnly: derOnly,
          );
          if (parsedSignature == null) return false;
          final verifier = ECDSASigner(SHA256Digest())
            ..init(
              false,
              PublicKeyParameter<ECPublicKey>(ECPublicKey(point, parameters)),
            );
          return verifier.verifySignature(message, parsedSignature);
        case -257:
          final modulus = key.modulus;
          final exponent = key.exponent;
          if (modulus == null || exponent == null || signature.isEmpty) {
            return false;
          }
          final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
            ..init(
              false,
              PublicKeyParameter<RSAPublicKey>(
                RSAPublicKey(_bytesToBigInt(modulus), _bytesToBigInt(exponent)),
              ),
            );
          return verifier.verifySignature(
            message,
            RSASignature(Uint8List.fromList(signature)),
          );
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  ECSignature? _decodeEs256Signature(
    Uint8List bytes,
    ECDomainParameters parameters, {
    bool derOnly = false,
  }) {
    BigInt? r;
    BigInt? s;
    if (!derOnly && bytes.length == 64) {
      r = _bytesToBigInt(bytes.sublist(0, 32));
      s = _bytesToBigInt(bytes.sublist(32));
    } else {
      // WebAuthn authenticators encode ECDSA signatures as an ASN.1 DER
      // sequence of two positive INTEGER values. P-256 values fit in at most
      // 33 encoded bytes each, including an optional sign-padding byte.
      if (bytes.length < 8 ||
          bytes.length > 72 ||
          bytes[0] != 0x30 ||
          bytes[1] != bytes.length - 2) {
        return null;
      }
      var offset = 2;
      BigInt? readInteger() {
        if (offset + 2 > bytes.length || bytes[offset] != 0x02) return null;
        final length = bytes[offset + 1];
        offset += 2;
        if (length < 1 || length > 33 || offset + length > bytes.length) {
          return null;
        }
        final first = bytes[offset];
        if (first & 0x80 != 0 ||
            (length > 1 && first == 0 && bytes[offset + 1] & 0x80 == 0)) {
          return null;
        }
        final value = _bytesToBigInt(bytes.sublist(offset, offset + length));
        offset += length;
        return value;
      }

      r = readInteger();
      s = readInteger();
      if (r == null || s == null || offset != bytes.length) return null;
    }
    if (r <= BigInt.zero ||
        s <= BigInt.zero ||
        r >= parameters.n ||
        s >= parameters.n) {
      return null;
    }
    return ECSignature(r, s);
  }

  _CosePublicKey _decodeCosePublicKey(Uint8List bytes) {
    dynamic decoded;
    try {
      decoded = cbor.cbor.decode(bytes, decodeBase64: false);
    } catch (_) {
      throw AuthFlowException('webauthn_public_key_invalid');
    }
    if (decoded is! Map) {
      throw AuthFlowException('webauthn_public_key_unsupported');
    }
    final algorithm = decoded[3];
    if (algorithm is! int) {
      throw AuthFlowException('webauthn_public_key_unsupported');
    }
    if (algorithm == -8) {
      if (decoded[1] is! int ||
          decoded[1] != 1 ||
          decoded[-1] is! int ||
          decoded[-1] != 6) {
        throw AuthFlowException('webauthn_public_key_unsupported');
      }
      final publicKey = _coseBytes(decoded[-2], expectedLength: 32);
      return _CosePublicKey(algorithm: algorithm, ed25519PublicKey: publicKey);
    }
    if (algorithm == -7) {
      if (decoded[1] != 2 || decoded[-1] != 1) {
        throw AuthFlowException('webauthn_public_key_unsupported');
      }
      final x = _coseBytes(decoded[-2], expectedLength: 32);
      final y = _coseBytes(decoded[-3], expectedLength: 32);
      return _CosePublicKey(algorithm: algorithm, x: x, y: y);
    }
    if (algorithm == -257) {
      if (decoded[1] != 3) {
        throw AuthFlowException('webauthn_public_key_unsupported');
      }
      final modulus = _coseBytes(decoded[-1]);
      final exponent = _coseBytes(decoded[-2]);
      if (modulus.length < 256 ||
          modulus.length > 1024 ||
          exponent.isEmpty ||
          exponent.length > 8) {
        throw AuthFlowException('webauthn_public_key_invalid');
      }
      return _CosePublicKey(
        algorithm: algorithm,
        modulus: modulus,
        exponent: exponent,
      );
    }
    throw AuthFlowException('webauthn_public_key_unsupported');
  }

  Uint8List _coseBytes(Object? value, {int? expectedLength}) {
    if (value is! List ||
        value.any((item) => item is! int || item < 0 || item > 255) ||
        (expectedLength != null && value.length != expectedLength)) {
      throw AuthFlowException('webauthn_public_key_invalid');
    }
    return Uint8List.fromList(value.cast<int>());
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
    const supported = <String>{'none', 'direct', 'indirect'};
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

String _formatAaguid(List<int> bytes) {
  if (bytes.length != 16) {
    throw AuthFlowException('webauthn_attestation_invalid');
  }
  final encoded = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${encoded.substring(0, 8)}-'
      '${encoded.substring(8, 12)}-'
      '${encoded.substring(12, 16)}-'
      '${encoded.substring(16, 20)}-'
      '${encoded.substring(20)}';
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
    required this.metadata,
  });

  final Uint8List credentialId;
  final Uint8List publicKeyCose;
  final int counter;
  final WebAuthnAttestationMetadata metadata;
}

final class _VerifiedAttestationStatement {
  const _VerifiedAttestationStatement({
    required this.kind,
    this.certificateTrustPath = const <Uint8List>[],
  });

  final WebAuthnAttestationKind kind;
  final List<Uint8List> certificateTrustPath;
}

final class _ParsedAuthenticatorData {
  const _ParsedAuthenticatorData({
    required this.counter,
    this.credentialId,
    this.publicKeyCose,
    this.aaguid,
  });

  final int counter;
  final Uint8List? credentialId;
  final Uint8List? publicKeyCose;
  final Uint8List? aaguid;
}

final class _PackedAttestationCertificate {
  const _PackedAttestationCertificate({
    required this.derBytes,
    required this.tbsCertificate,
    required this.signatureAlgorithm,
    required this.signature,
    required this.publicKey,
    required this.issuer,
    required this.subject,
    required this.isVersion3,
    required this.hasBasicConstraints,
    required this.isCertificateAuthority,
    required this.hasTpmSubjectAlternativeName,
    required this.hasTpmAikExtendedKeyUsage,
    this.country,
    this.organization,
    this.organizationalUnit,
    this.commonName,
    this.aaguid,
    this.androidKeyAttestationExtension,
    this.appleNonceExtension,
  });

  final Uint8List derBytes;
  final Uint8List tbsCertificate;
  final int signatureAlgorithm;
  final Uint8List signature;
  final _CosePublicKey publicKey;
  final Uint8List issuer;
  final Uint8List subject;
  final bool isVersion3;
  final bool hasBasicConstraints;
  final bool isCertificateAuthority;
  final bool hasTpmSubjectAlternativeName;
  final bool hasTpmAikExtendedKeyUsage;
  final String? country;
  final String? organization;
  final String? organizationalUnit;
  final String? commonName;
  final Uint8List? aaguid;
  final Uint8List? androidKeyAttestationExtension;
  final Uint8List? appleNonceExtension;
}

final class _TpmPublicArea {
  const _TpmPublicArea({required this.nameAlgorithm, required this.publicKey});

  final int nameAlgorithm;
  final _CosePublicKey publicKey;
}

final class _TpmCertInfo {
  const _TpmCertInfo({required this.extraData, required this.name});

  final Uint8List extraData;
  final Uint8List name;
}

final class _TpmReader {
  _TpmReader(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;

  int uint8() => _take(1).single;

  int uint16() {
    final bytes = _take(2);
    return (bytes[0] << 8) | bytes[1];
  }

  int uint32() {
    final bytes = _take(4);
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  BigInt uint64() {
    final bytes = _take(8);
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  Uint8List sized({required int maximum}) {
    final length = uint16();
    if (length > maximum) throw const FormatException();
    return Uint8List.fromList(_take(length));
  }

  void requireEnd() {
    if (_offset != _bytes.length) throw const FormatException();
  }

  Uint8List _take(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException();
    }
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }
}

final class _AndroidAuthorizationList {
  const _AndroidAuthorizationList({
    required this.purposes,
    required this.origin,
    required this.hasAllApplications,
  });

  final Set<int> purposes;
  final int? origin;
  final bool hasAllApplications;
}

/// Performs the structural checks that the simple CBOR decoder cannot retain,
/// most importantly duplicate map keys. WebAuthn inputs are attacker-controlled
/// and duplicate security-sensitive fields must not be silently overwritten.
final class _StrictCborReader {
  _StrictCborReader(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;
  var _depth = 0;
  var _items = 0;

  void validateSingle() {
    _readItem();
    if (_offset != _bytes.length) throw const FormatException();
  }

  String _readItem({bool asKey = false}) {
    if (++_items > 16384 || ++_depth > 32 || _offset >= _bytes.length) {
      throw const FormatException();
    }
    final start = _offset;
    try {
      final initial = _bytes[_offset++];
      final major = initial >> 5;
      final argument = _readArgument(initial & 0x1f);
      switch (major) {
        case 0:
        case 1:
          if (argument == null) throw const FormatException();
          return asKey ? 'integer:$major:$argument' : '';
        case 2:
        case 3:
          final value = _readString(major, argument);
          if (!asKey) return '';
          if (major == 2) return 'bytes:${base64UrlEncode(value)}';
          return 'text:${utf8.decode(value, allowMalformed: false)}';
        case 4:
          _readSequence(argument, map: false);
          break;
        case 5:
          _readSequence(argument, map: true);
          break;
        case 6:
          if (argument == null) throw const FormatException();
          _readItem();
          break;
        case 7:
          if (argument == null) throw const FormatException();
          break;
        default:
          throw const FormatException();
      }
      return asKey
          ? 'encoded:${base64UrlEncode(_bytes.sublist(start, _offset))}'
          : '';
    } finally {
      _depth--;
    }
  }

  void _readSequence(int? length, {required bool map}) {
    final seen = map ? <String>{} : null;
    var count = 0;
    while (length == null || count < length) {
      if (length == null && _peekBreak()) {
        _offset++;
        return;
      }
      if (map) {
        final key = _readItem(asKey: true);
        if (!seen!.add(key)) throw const FormatException();
        _readItem();
      } else {
        _readItem();
      }
      count++;
    }
  }

  Uint8List _readString(int major, int? length) {
    if (length != null) return _take(length);
    final builder = BytesBuilder(copy: false);
    while (!_peekBreak()) {
      if (_offset >= _bytes.length) throw const FormatException();
      final initial = _bytes[_offset++];
      if (initial >> 5 != major) throw const FormatException();
      final chunkLength = _readArgument(initial & 0x1f);
      if (chunkLength == null) throw const FormatException();
      builder.add(_take(chunkLength));
      if (builder.length > 65536) throw const FormatException();
    }
    _offset++;
    return builder.takeBytes();
  }

  int? _readArgument(int additionalInfo) {
    if (additionalInfo < 24) return additionalInfo;
    final octets = switch (additionalInfo) {
      24 => 1,
      25 => 2,
      26 => 4,
      27 => 8,
      31 => 0,
      _ => throw const FormatException(),
    };
    if (additionalInfo == 31) return null;
    final valueBytes = _take(octets);
    var value = 0;
    for (final byte in valueBytes) {
      value = (value << 8) | byte;
    }
    if (value > (1 << 30)) throw const FormatException();
    return value;
  }

  Uint8List _take(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException();
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  bool _peekBreak() => _offset < _bytes.length && _bytes[_offset] == 0xff;
}

final class _DerValue {
  const _DerValue({
    required this.tagClass,
    required this.constructed,
    required this.tagNumber,
    required this.value,
  });

  final int tagClass;
  final bool constructed;
  final int tagNumber;
  final Uint8List value;
}

final class _DerReader {
  _DerReader(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;

  _DerValue readSingle() {
    final value = read();
    if (_offset != _bytes.length) throw const FormatException();
    return value;
  }

  _DerValue read() {
    if (_offset >= _bytes.length) throw const FormatException();
    final identifier = _bytes[_offset++];
    final tagClass = identifier >> 6;
    final constructed = identifier & 0x20 != 0;
    var tagNumber = identifier & 0x1f;
    if (tagNumber == 0x1f) {
      tagNumber = 0;
      var octets = 0;
      while (true) {
        if (_offset >= _bytes.length || octets == 5) {
          throw const FormatException();
        }
        final byte = _bytes[_offset++];
        if (octets == 0 && byte == 0x80) throw const FormatException();
        tagNumber = (tagNumber << 7) | (byte & 0x7f);
        octets++;
        if (byte & 0x80 == 0) break;
      }
      if (tagNumber < 31) throw const FormatException();
    }
    if (_offset >= _bytes.length) throw const FormatException();
    final firstLength = _bytes[_offset++];
    int length;
    if (firstLength & 0x80 == 0) {
      length = firstLength;
    } else {
      final lengthOctets = firstLength & 0x7f;
      if (lengthOctets == 0 ||
          lengthOctets > 4 ||
          _offset + lengthOctets > _bytes.length ||
          _bytes[_offset] == 0) {
        throw const FormatException();
      }
      length = 0;
      for (var index = 0; index < lengthOctets; index++) {
        length = (length << 8) | _bytes[_offset++];
      }
      if (length < 128) throw const FormatException();
    }
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException();
    }
    final value = Uint8List.fromList(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return _DerValue(
      tagClass: tagClass,
      constructed: constructed,
      tagNumber: tagNumber,
      value: value,
    );
  }

  bool get hasNext => _offset < _bytes.length;
}

List<_DerValue> _derChildren(
  _DerValue value, {
  required int universalTag,
  required int maxElements,
}) {
  if (value.tagClass != 0 ||
      value.tagNumber != universalTag ||
      !value.constructed) {
    throw const FormatException();
  }
  final reader = _DerReader(value.value);
  final result = <_DerValue>[];
  while (reader.hasNext) {
    if (result.length == maxElements) throw const FormatException();
    result.add(reader.read());
  }
  return result;
}

int _derUnsignedInteger(_DerValue value, {required int universalTag}) {
  if (value.tagClass != 0 ||
      value.tagNumber != universalTag ||
      value.constructed ||
      value.value.isEmpty ||
      value.value.length > 8 ||
      value.value.first & 0x80 != 0 ||
      (value.value.length > 1 &&
          value.value.first == 0 &&
          value.value[1] & 0x80 == 0)) {
    throw const FormatException();
  }
  var result = 0;
  for (final byte in value.value) {
    result = (result << 8) | byte;
  }
  return result;
}

Uint8List _derOctets(_DerValue value) {
  if (value.tagClass != 0 || value.tagNumber != 4 || value.constructed) {
    throw const FormatException();
  }
  return Uint8List.fromList(value.value);
}

final class _CosePublicKey {
  const _CosePublicKey({
    required this.algorithm,
    this.x,
    this.y,
    this.modulus,
    this.exponent,
    this.ed25519PublicKey,
  });

  final int algorithm;
  final Uint8List? x;
  final Uint8List? y;
  final Uint8List? modulus;
  final Uint8List? exponent;
  final Uint8List? ed25519PublicKey;
}

BigInt _bytesToBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

Uint8List _bigIntToUnsignedBytes(BigInt value) {
  if (value <= BigInt.zero) throw const FormatException();
  final result = <int>[];
  var remaining = value;
  while (remaining > BigInt.zero) {
    result.add((remaining & BigInt.from(0xff)).toInt());
    remaining >>= 8;
  }
  return Uint8List.fromList(result.reversed.toList(growable: false));
}

bool _constantTimeBytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
