import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show Hmac, sha256;

import 'authentication_methods.dart';
import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'models.dart';
import 'phone_number_store.dart';
import 'plugin.dart';
import 'rate_limit.dart';
import 'tokens.dart' show base64UrlNoPadding, secureRandomToken;
import 'users.dart' show authUserIsDisabled;

/// Stable identifier for the phone-number plugin.
const String authPhoneNumberPluginId = 'phone_number';

/// Authentication-method identifier recorded for verified phone sign-ins.
const String authPhoneNumberAuthenticationMethod = 'phone_number';

/// Rate-limit operation for sending phone verification codes.
const AuthRateLimitOperation authPhoneNumberSendRateLimitOperation =
    AuthRateLimitOperation(authPhoneNumberPluginId, 'send_code');

/// Rate-limit operation for verifying phone verification codes.
const AuthRateLimitOperation authPhoneNumberVerifyRateLimitOperation =
    AuthRateLimitOperation(authPhoneNumberPluginId, 'verify_code');

/// Rate-limit operation for removing a verified phone identity.
const AuthRateLimitOperation authPhoneNumberRemovalRateLimitOperation =
    AuthRateLimitOperation(authPhoneNumberPluginId, 'remove');

/// Normalizes application input into a canonical phone number or rejects it.
abstract interface class AuthPhoneNumberPolicy {
  /// Normalizes [input], or returns `null` when it is not accepted.
  String? normalize(String input);
}

/// Strict E.164 policy without locale-dependent guessing.
///
/// Input is trimmed at its edges, then must already be `+` followed by 2 to
/// 15 ASCII digits. The first digit cannot be zero. Formatting punctuation,
/// national numbers, Unicode digits, extensions, and embedded whitespace are
/// rejected rather than interpreted ambiguously.
final class AuthE164PhoneNumberPolicy implements AuthPhoneNumberPolicy {
  /// Creates a policy that accepts strict E.164 values.
  const AuthE164PhoneNumberPolicy();

  static final RegExp _pattern = RegExp(r'^\+[1-9][0-9]{1,14}$');

  @override
  String? normalize(String input) {
    final candidate = input.trim();
    return _pattern.hasMatch(candidate) ? candidate : null;
  }
}

/// Delivers a newly generated phone verification code.
typedef AuthPhoneNumberCodeSender<TContext> =
    FutureOr<void> Function(AuthPhoneNumberCodeDelivery<TContext> delivery);

/// Builds candidate user data for backend-owned sign-up.
///
/// This callback must not persist the user or perform other durable side
/// effects. [AuthPhoneNumberBackend.verifyPhoneNumberCode] owns creation,
/// phone binding, verified projection, and challenge consumption atomically.
typedef AuthPhoneNumberUserFactory<TContext> =
    FutureOr<AuthUser> Function(
      TContext context,
      String phoneNumber,
      String? name,
    );

/// Notifies the application after a phone identity is committed.
typedef AuthPhoneNumberVerifiedCallback<TContext> =
    FutureOr<void> Function(
      TContext context,
      String phoneNumber,
      AuthUser user,
    );

/// The one boundary where the raw verification code is exposed.
///
/// Delivery providers should enqueue or send the code without logging it.
/// Serverless implementations can schedule durable background work through
/// [context] and return once that work has been accepted.
final class AuthPhoneNumberCodeDelivery<TContext> {
  /// Creates a delivery request containing the raw verification code.
  const AuthPhoneNumberCodeDelivery({
    required this.context,
    required this.phoneNumber,
    required this.code,
    required this.expiresAt,
  });

  /// Application context associated with the request.
  final TContext context;

  /// Canonical phone number receiving the code.
  final String phoneNumber;

  /// Raw code to deliver through the trusted channel.
  final String code;

  /// Time at which the code expires.
  final DateTime expiresAt;
}

/// Result returned after a phone verification code is issued.
final class AuthPhoneNumberCodeIssued {
  /// Creates a response for an issued verification code.
  const AuthPhoneNumberCodeIssued({required this.expiresAt});

  /// Time at which the code expires.
  final DateTime expiresAt;
}

/// Result returned after a phone verification code authenticates a user.
final class AuthPhoneNumberSignInResult {
  /// Creates a successful phone-number sign-in result.
  const AuthPhoneNumberSignInResult({
    required this.phoneNumber,
    required this.user,
  });

  /// Canonical phone number that was verified.
  final String phoneNumber;

  /// User authenticated by the verified phone number.
  final AuthUser user;
}

/// JSON request for sending a phone verification code.
final class AuthPhoneNumberSendCodeRequest {
  /// Creates a phone-code request for [phoneNumber].
  const AuthPhoneNumberSendCodeRequest({required this.phoneNumber});

  /// Phone number supplied by the caller.
  final String phoneNumber;

  /// Decodes a phone-code request from JSON.
  factory AuthPhoneNumberSendCodeRequest.fromJson(Map<String, dynamic> json) =>
      AuthPhoneNumberSendCodeRequest(
        phoneNumber: _requiredString(json, 'phoneNumber'),
      );

  /// Encodes this request as JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'phoneNumber': phoneNumber,
  };
}

/// JSON response returned after sending a phone verification code.
final class AuthPhoneNumberSendCodeResponse {
  /// Creates a response with the code expiry time.
  const AuthPhoneNumberSendCodeResponse({required this.expiresAt});

  /// Time at which the sent code expires.
  final DateTime expiresAt;

  /// Encodes this response as JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': 'verification_sent',
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

/// JSON request for verifying a phone verification code.
final class AuthPhoneNumberVerifyRequest {
  /// Creates a phone-code verification request.
  const AuthPhoneNumberVerifyRequest({
    required this.phoneNumber,
    required this.code,
    this.name,
  });

  /// Phone number associated with the code.
  final String phoneNumber;

  /// Raw verification code supplied by the caller.
  final String code;

  /// Optional display name for a newly created user.
  final String? name;

  /// Decodes a verification request from JSON.
  factory AuthPhoneNumberVerifyRequest.fromJson(Map<String, dynamic> json) =>
      AuthPhoneNumberVerifyRequest(
        phoneNumber: _requiredString(json, 'phoneNumber'),
        code: _requiredString(json, 'code'),
        name: _optionalString(json, 'name'),
      );

  /// Encodes this request as JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'phoneNumber': phoneNumber,
    'code': code,
    if (name != null) 'name': name,
  };
}

/// JSON response returned after successful phone verification.
final class AuthPhoneNumberVerifyResponse {
  /// Creates a successful phone verification response.
  const AuthPhoneNumberVerifyResponse({
    required this.phoneNumber,
    required this.user,
  });

  /// Canonical phone number that was verified.
  final String phoneNumber;

  /// User authenticated by the verified phone number.
  final AuthUser user;

  /// Converts this response into the common authentication intent.
  AuthEndpointAuthenticationIntent toAuthenticationIntent() =>
      AuthEndpointAuthenticationIntent(
        user: user,
        authenticationMethod: authPhoneNumberAuthenticationMethod,
        metadata: <String, dynamic>{
          'status': 'authenticated',
          'phoneNumber': phoneNumber,
        },
      );
}

/// Phone-number OTP authentication as an opt-in server plugin.
final class PhoneNumberPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding,
        AuthUserDeletionPlanContributor {
  /// Creates a phone-number plugin with an application-owned code sender.
  PhoneNumberPlugin({
    required this.sendCode,
    required String codeHashKey,
    this.phoneNumberPolicy = const AuthE164PhoneNumberPolicy(),
    this.codeLength = 6,
    this.expiresIn = const Duration(minutes: 5),
    this.allowedAttempts = 3,
    this.allowSignUp = false,
    this.createUser,
    this.onVerified,
    String Function(int length)? generateCode,
  }) : _codeHashKey = utf8.encode(codeHashKey),
       _generateCode = generateCode ?? _defaultCode {
    if (_codeHashKey.length < 32) {
      throw ArgumentError(
        'codeHashKey must contain at least 32 UTF-8 bytes',
        'codeHashKey',
      );
    }
    if (codeLength < 4 || codeLength > 12) {
      throw ArgumentError.value(codeLength, 'codeLength', 'must be 4 to 12');
    }
    if (expiresIn <= Duration.zero) {
      throw ArgumentError.value(expiresIn, 'expiresIn', 'must be positive');
    }
    if (allowedAttempts <= 0) {
      throw ArgumentError.value(
        allowedAttempts,
        'allowedAttempts',
        'must be positive',
      );
    }
  }

  /// Callback that delivers each generated verification code.
  final AuthPhoneNumberCodeSender<TContext> sendCode;

  /// Policy used to normalize and validate phone input.
  final AuthPhoneNumberPolicy phoneNumberPolicy;

  /// Number of decimal digits in generated verification codes.
  final int codeLength;

  /// Duration for which an issued code remains valid.
  final Duration expiresIn;

  /// Maximum failed attempts allowed for one code.
  final int allowedAttempts;

  /// Whether an unknown phone number may create a user.
  final bool allowSignUp;

  /// Builds a candidate user when sign-up is enabled.
  final AuthPhoneNumberUserFactory<TContext>? createUser;

  /// Callback invoked after the phone identity is committed.
  final AuthPhoneNumberVerifiedCallback<TContext>? onVerified;
  final List<int> _codeHashKey;
  final String Function(int length) _generateCode;

  late AuthPhoneNumberBackend _backend;
  late AuthUserDeletionDomain _deletionDomain;
  late AuthAuthenticationMethodService _authenticationMethods;
  bool _configured = false;

  @override
  String get id => authPhoneNumberPluginId;

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract(
        authenticationMethodNamespace: authPhoneNumberPluginId,
        userDataNamespace: authPhoneNumberPluginId,
        removalEndpointIds: <String>['phoneNumber.remove'],
      );

  @override
  String get userDataNamespace => authPhoneNumberPluginId;

  @override
  String get authenticationMethodNamespace => authPhoneNumberPluginId;

  @override
  Object get authenticationMethodStore => _backend;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.phone,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async {
    _ensureConfigured();
    final identity = await _backend.findPhoneNumberIdentityForUser(userId);
    return AuthAuthenticationMethodSnapshot.complete([
      if (identity != null)
        AuthAuthenticationMethod.phone(identity.phoneNumber),
    ]);
  }

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final host = context.store;
    if (host is! AuthPhoneNumberBackend) {
      throw StateError(
        'PhoneNumberPlugin requires an AuthPhoneNumberBackend. Durable '
        'topologies must provide transactional phone commands; no in-memory '
        'fallback is installed.',
      );
    }
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError(
        'PhoneNumberPlugin requires a deletion-coordinator host store.',
      );
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
    _backend = host as AuthPhoneNumberBackend;
    final authenticationMethods = context.authenticationMethods;
    if (authenticationMethods == null) {
      throw StateError(
        'PhoneNumberPlugin requires an authentication-method service.',
      );
    }
    _authenticationMethods = authenticationMethods;
    _configured = true;
  }

  /// Removes the current phone identity only when another usable method
  /// remains.
  ///
  /// This is a persistence capability, not an authorization check. Hosts must
  /// require recent authentication or an explicit step-up proof before
  /// calling it.
  Future<void> removePhoneNumber({required String userId}) async {
    _ensureConfigured();
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw AuthFlowException('phone_identity_removal_failed');
    }
    final identity = await _backend.findPhoneNumberIdentityForUser(
      normalizedUserId,
    );
    if (identity == null) return;
    final mutation = _backend is AuthPhoneNumberMutationStore
        ? _backend as AuthPhoneNumberMutationStore
        : null;
    if (mutation == null) {
      throw AuthFlowException('authentication_method_mutation_unavailable');
    }
    final result = await mutation.removePhoneNumberIfSafe(
      AuthPhoneNumberRemovalCommand(
        userId: normalizedUserId,
        phoneNumber: identity.phoneNumber,
        loadInventory: () =>
            _authenticationMethods.snapshotForUser(normalizedUserId),
      ),
    );
    switch (result) {
      case AuthAuthenticationMethodMutationResult.mutated:
      case AuthAuthenticationMethodMutationResult.notFound:
        return;
      case AuthAuthenticationMethodMutationResult.lastAuthenticationMethod:
        throw AuthFlowException('last_authentication_method');
      case AuthAuthenticationMethodMutationResult.atomicityUnavailable:
        throw AuthFlowException('authentication_method_mutation_unavailable');
    }
  }

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      <AuthEndpointDescriptor<TContext>>[
        TypedAuthEndpointDescriptor<
          TContext,
          AuthPhoneNumberSendCodeRequest,
          AuthPhoneNumberSendCodeResponse
        >(
          id: 'phoneNumber.sendCode',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/phone-number/send-code'),
          semantics: const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.atomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authPhoneNumberPluginId,
                atomicOperationId: 'phoneNumber.issueCode',
              ),
            ),
            replaySafety: AuthMutationReplaySafety.repeatable,
          ),
          requestCodec: _sendRequestCodec,
          responseCodec: _sendResponseCodec,
          authentication: AuthOperationAuthentication.none,
          originPolicy: AuthOperationOriginPolicy.browser,
          csrfPolicy: AuthOperationCsrfPolicy.none,
          rateLimitOperation: authPhoneNumberSendRateLimitOperation,
          rateLimitIdentifier: (request) =>
              _phoneRateLimitIdentifier(request.phoneNumber),
          handler: (invocation, request) async {
            final issued = await issueCode(
              context: invocation.context,
              phoneNumber: request.phoneNumber,
            );
            return AuthPhoneNumberSendCodeResponse(expiresAt: issued.expiresAt);
          },
        ),
        TypedAuthEndpointDescriptor<
          TContext,
          AuthPhoneNumberVerifyRequest,
          AuthPhoneNumberVerifyResponse
        >(
          id: 'phoneNumber.verifyCode',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/phone-number/verify-code'),
          semantics: const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.atomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authPhoneNumberPluginId,
                atomicOperationId: 'phoneNumber.verifyCode',
              ),
            ),
            replaySafety: AuthMutationReplaySafety.singleUse,
          ),
          requestCodec: _verifyRequestCodec,
          responseCodec: _verifyResponseCodec,
          authentication: AuthOperationAuthentication.none,
          originPolicy: AuthOperationOriginPolicy.browser,
          csrfPolicy: AuthOperationCsrfPolicy.none,
          rateLimitOperation: authPhoneNumberVerifyRateLimitOperation,
          rateLimitIdentifier: (request) =>
              _phoneRateLimitIdentifier(request.phoneNumber),
          handler: (invocation, request) async {
            final result = await verifyCode(
              context: invocation.context,
              phoneNumber: request.phoneNumber,
              code: request.code,
              name: request.name,
            );
            return AuthPhoneNumberVerifyResponse(
              phoneNumber: result.phoneNumber,
              user: result.user,
            );
          },
        ),
        TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
          id: 'phoneNumber.remove',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/phone-number/remove'),
          semantics: const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.atomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authPhoneNumberPluginId,
                atomicOperationId: 'phoneNumber.remove',
              ),
            ),
            replaySafety: AuthMutationReplaySafety.idempotent,
          ),
          requestCodec: _emptyRequestCodec,
          responseCodec: _objectResponseCodec,
          authentication: AuthOperationAuthentication.session,
          csrfPolicy: AuthOperationCsrfPolicy.required,
          requiresRecentAuthentication: true,
          rateLimitOperation: authPhoneNumberRemovalRateLimitOperation,
          handler: (invocation, _) async {
            final user = invocation.user;
            if (user == null) throw AuthFlowException('unauthorized');
            await removePhoneNumber(userId: user.id);
            return const <String, dynamic>{'status': 'phone_number_removed'};
          },
        ),
      ];

  String? _phoneRateLimitIdentifier(String input) {
    final phoneNumber = phoneNumberPolicy.normalize(input);
    if (phoneNumber == null) return null;
    final digest = Hmac(
      sha256,
      _codeHashKey,
    ).convert(utf8.encode('rate-limit:phone:$phoneNumber'));
    return 'phone:${base64UrlNoPadding(digest.bytes)}';
  }

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      mount: endpoint.mount,
      serverOnly: endpoint.serverOnly,
    ),
  );

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations =>
      const <AuthRateLimitOperation>[
        authPhoneNumberSendRateLimitOperation,
        authPhoneNumberVerifyRateLimitOperation,
        authPhoneNumberRemovalRateLimitOperation,
      ];

  @override
  Iterable<AuthPersistenceSchema>
  get persistenceSchemas => const <AuthPersistenceSchema>[
    AuthPersistenceSchema(
      id: authPhoneNumberPluginId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'auth_phone_number_identity',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'phoneNumber', kind: 'e164'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'verifiedAt', kind: 'datetime'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['phoneNumber'],
            <String>['userId'],
          ],
          indexes: <List<String>>[
            <String>['userId'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'auth_phone_number_verification',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'phoneNumber', kind: 'e164'),
            AuthFieldDescriptor(name: 'codeDigest', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'maxAttempts', kind: 'integer'),
            AuthFieldDescriptor(name: 'attempts', kind: 'integer'),
            AuthFieldDescriptor(name: 'lockedAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'consumedAt', kind: 'datetime'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['phoneNumber'],
          ],
          indexes: <List<String>>[
            <String>['expiresAt'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'auth_phone_number_issue_receipt',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'operationId', kind: 'id'),
            AuthFieldDescriptor(name: 'fingerprint', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'phoneNumber', kind: 'e164'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['operationId'],
          ],
          indexes: <List<String>>[
            <String>['phoneNumber'],
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'phoneNumber.issueCode',
          description:
              'Install one digest-only challenge and its replay binding atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'phoneNumber.verifyCode',
          description:
              'Update attempts or lockout and atomically consume, bind, and project one verified phone identity.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'phoneNumber.remove',
          description:
              'Recheck the authentication-method inventory and remove one phone identity and its artifacts atomically.',
        ),
      ],
    ),
  ];

  /// Issues a verification code and delivers it through [sendCode].
  Future<AuthPhoneNumberCodeIssued> issueCode({
    required TContext context,
    required String phoneNumber,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalized = _normalizePhoneNumber(phoneNumber);
    final current = (now ?? DateTime.now()).toUtc();
    final rawCode = _generateCode(codeLength);
    if (!RegExp('^[0-9]{${codeLength.toString()}}\$').hasMatch(rawCode)) {
      throw StateError('Phone code generator returned an invalid code');
    }
    final verification = AuthPhoneNumberVerification(
      id: secureRandomToken(length: 18),
      phoneNumber: normalized,
      codeDigest: _digest(normalized, rawCode),
      createdAt: current,
      expiresAt: current.add(expiresIn),
      maxAttempts: allowedAttempts,
    );
    final issued = await _backend.issuePhoneNumberCode(
      AuthPhoneNumberIssueCodeCommand(verification: verification),
    );
    if (!issued.committed) {
      throw AuthFlowException('phone_code_issue_unavailable');
    }
    await sendCode(
      AuthPhoneNumberCodeDelivery<TContext>(
        context: context,
        phoneNumber: normalized,
        code: rawCode,
        expiresAt: verification.expiresAt,
      ),
    );
    return AuthPhoneNumberCodeIssued(expiresAt: verification.expiresAt);
  }

  /// Verifies a code and returns the authenticated user.
  Future<AuthPhoneNumberSignInResult> verifyCode({
    required TContext context,
    required String phoneNumber,
    required String code,
    String? name,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalized = _normalizePhoneNumber(phoneNumber);
    final normalizedCode = code.trim();
    if (!RegExp(
      '^[0-9]{${codeLength.toString()}}\$',
    ).hasMatch(normalizedCode)) {
      throw AuthFlowException('invalid_phone_code');
    }
    final current = (now ?? DateTime.now()).toUtc();
    AuthUser? candidate;
    final knownIdentity = await _backend.findPhoneNumberIdentity(normalized);
    if (allowSignUp && knownIdentity == null) {
      final requestedName = name?.trim();
      if (requestedName != null && requestedName.length > 256) {
        throw AuthFlowException('invalid_request');
      }
      candidate = await Future.sync(
        () =>
            createUser?.call(
              context,
              normalized,
              requestedName?.isEmpty == true ? null : requestedName,
            ) ??
            AuthUser(
              id: secureRandomToken(length: 24),
              name: requestedName?.isEmpty == true ? null : requestedName,
            ),
      );
    }
    final verification = await _backend.verifyPhoneNumberCode(
      AuthPhoneNumberVerifyCodeCommand(
        phoneNumber: normalized,
        codeDigest: _digest(normalized, normalizedCode),
        now: current,
        candidateUser: candidate,
      ),
    );
    switch (verification.status) {
      case AuthPhoneNumberVerifyStatus.invalid:
        throw AuthFlowException('invalid_phone_code');
      case AuthPhoneNumberVerifyStatus.expired:
        throw AuthFlowException('phone_code_expired');
      case AuthPhoneNumberVerifyStatus.tooManyAttempts:
        throw AuthFlowException('phone_code_too_many_attempts');
      case AuthPhoneNumberVerifyStatus.userNotFound:
      case AuthPhoneNumberVerifyStatus.userUnavailable:
        throw AuthFlowException('user_not_found');
      case AuthPhoneNumberVerifyStatus.conflict:
        throw AuthFlowException('phone_account_conflict');
      case AuthPhoneNumberVerifyStatus.verified:
        break;
    }
    final user = verification.user;
    if (user == null || authUserIsDisabled(user)) {
      throw AuthFlowException('user_not_found');
    }
    await onVerified?.call(context, normalized, user);
    return AuthPhoneNumberSignInResult(phoneNumber: normalized, user: user);
  }

  @override
  AuthUserDeletionPlan createUserDeletionPlan(AuthUser user) {
    _ensureConfigured();
    return AuthNoopUserDeletionPlan(
      domain: _deletionDomain,
      userId: user.id,
      namespace: userDataNamespace,
    );
  }

  String _normalizePhoneNumber(String value) {
    final normalized = phoneNumberPolicy.normalize(value);
    if (normalized == null) throw AuthFlowException('invalid_phone_number');
    return normalized;
  }

  String _digest(String phoneNumber, String code) {
    final digest = Hmac(
      sha256,
      _codeHashKey,
    ).convert(utf8.encode('$phoneNumber\u0000$code'));
    return base64UrlNoPadding(digest.bytes);
  }

  void _ensureConfigured() {
    if (!_configured) throw StateError('PhoneNumberPlugin is not configured');
  }

  static String _defaultCode(int length) {
    final random = Random.secure();
    return List<String>.generate(length, (_) => '${random.nextInt(10)}').join();
  }

  static final AuthOperationCodec<AuthPhoneNumberSendCodeRequest>
  _sendRequestCodec = AuthOperationCodec<AuthPhoneNumberSendCodeRequest>(
    decode: AuthPhoneNumberSendCodeRequest.fromJson,
    encode: (value) => value.toJson(),
    required: true,
    schema: _sendRequestSchema,
  );

  static final AuthOperationCodec<AuthPhoneNumberSendCodeResponse>
  _sendResponseCodec = AuthOperationCodec<AuthPhoneNumberSendCodeResponse>(
    decode: (_) => throw UnsupportedError('Response-only codec'),
    encode: (value) => value.toJson(),
    schema: _sendResponseSchema,
  );

  static final AuthOperationCodec<AuthPhoneNumberVerifyRequest>
  _verifyRequestCodec = AuthOperationCodec<AuthPhoneNumberVerifyRequest>(
    decode: AuthPhoneNumberVerifyRequest.fromJson,
    encode: (value) => value.toJson(),
    required: true,
    schema: _verifyRequestSchema,
  );

  static final AuthOperationCodec<AuthPhoneNumberVerifyResponse>
  _verifyResponseCodec = AuthOperationCodec<AuthPhoneNumberVerifyResponse>(
    decode: (_) => throw UnsupportedError('Response-only codec'),
    encode: (value) => value.toAuthenticationIntent(),
    schema: _verifyResponseSchema,
  );

  static final AuthOperationCodec<Map<String, dynamic>> _emptyRequestCodec =
      AuthOperationCodec<Map<String, dynamic>>(
        decode: (_) => const <String, dynamic>{},
        encode: (value) => value,
        schema: const <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
        },
      );

  static final AuthOperationCodec<Object?> _objectResponseCodec =
      AuthOperationCodec<Object?>(
        decode: (_) => throw UnsupportedError('Response-only codec'),
        encode: (value) => value,
        schema: _removeResponseSchema,
      );
}

const Map<String, Object?> _sendRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['phoneNumber'],
  'properties': <String, Object?>{
    'phoneNumber': <String, Object?>{
      'type': 'string',
      'pattern': r'^\+[1-9][0-9]{1,14}$',
      'maxLength': 16,
    },
  },
};

const Map<String, Object?> _sendResponseSchema = <String, Object?>{
  'type': 'object',
  'required': <String>['status', 'expiresAt'],
  'properties': <String, Object?>{
    'status': <String, Object?>{'const': 'verification_sent'},
    'expiresAt': <String, Object?>{'type': 'string', 'format': 'date-time'},
  },
};

const Map<String, Object?> _verifyRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['phoneNumber', 'code'],
  'properties': <String, Object?>{
    'phoneNumber': <String, Object?>{
      'type': 'string',
      'pattern': r'^\+[1-9][0-9]{1,14}$',
      'maxLength': 16,
    },
    'code': <String, Object?>{
      'type': 'string',
      'pattern': r'^[0-9]{4,12}$',
      'maxLength': 12,
    },
    'name': <String, Object?>{'type': 'string', 'maxLength': 256},
  },
};

const Map<String, Object?> _verifyResponseSchema = <String, Object?>{
  'type': 'object',
  'required': <String>['status', 'phoneNumber', 'user'],
  'properties': <String, Object?>{
    'status': <String, Object?>{'const': 'authenticated'},
    'phoneNumber': <String, Object?>{'type': 'string'},
    'user': <String, Object?>{'type': 'object'},
    'expires': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
    'strategy': <String, Object?>{'type': 'string'},
  },
};

const Map<String, Object?> _removeResponseSchema = <String, Object?>{
  'type': 'object',
  'required': <String>['status'],
  'properties': <String, Object?>{
    'status': <String, Object?>{'const': 'phone_number_removed'},
  },
};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw AuthFlowException('invalid_request');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.length > 256) {
    throw AuthFlowException('invalid_request');
  }
  return value;
}
