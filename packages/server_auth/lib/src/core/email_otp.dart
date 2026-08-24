import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;

import 'authentication_methods.dart';
import 'deletion_transaction.dart';
import 'email_auth_backend.dart';
import 'email_otp_store.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show base64UrlNoPadding, secureRandomToken;
import 'users.dart' show authUserIsDisabled;

/// Stable identifier for the optional email OTP plugin.
const String authEmailOtpPluginId = 'email_otp';

/// Delivers a transient raw OTP after its digest is committed.
typedef AuthEmailOtpSender<TContext> =
    FutureOr<void> Function(AuthEmailOtpDelivery<TContext> delivery);

/// Transient delivery payload for an email OTP.
///
/// The raw [code] is available only to the sender and must never be logged or
/// persisted; the backend stores a digest instead.
final class AuthEmailOtpDelivery<TContext> {
  /// Creates the transient payload passed to [AuthEmailOtpSender].
  ///
  /// [code] is a raw secret and must be used only for delivery; it must not be
  /// logged or persisted. The backend already stores its digest.
  const AuthEmailOtpDelivery({
    required this.context,
    required this.email,
    required this.code,
    required this.type,
    required this.expiresAt,
  });

  /// Application context for delivery.
  final TContext context;

  /// Canonical recipient email address.
  final String email;

  /// Raw numeric OTP for transient delivery.
  final String code;

  /// Flow purpose for the OTP.
  final AuthEmailOtpType type;

  /// UTC expiry deadline for [code].
  final DateTime expiresAt;
}

/// Result of consuming an email OTP for sign-in.
final class AuthEmailOtpSignInResult {
  /// Creates the result of a successful OTP sign-in transition.
  const AuthEmailOtpSignInResult({required this.user});

  /// Authenticated or newly created user.
  final AuthUser user;
}

/// Typed email OTP plugin modeled on the common sign-in, verification, and
/// password-recovery OTP flows.
final class EmailOtpPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding,
        AuthUserDeletionPlanContributor {
  /// Creates an email OTP provider for sign-in and verification flows.
  ///
  /// [secret] must contain at least 32 UTF-8 bytes and protects OTP digests
  /// and rate-limit identifiers. [sendCode] runs after the digest record is
  /// committed, so delivery failure does not make the code reusable by a new
  /// issuance. [generateOtp] is intended for controlled tests.
  EmailOtpPlugin({
    required this.sendCode,
    required String secret,
    this.otpLength = 6,
    this.expiresIn = const Duration(minutes: 5),
    this.allowedAttempts = 3,
    this.disableSignUp = false,
    String Function(int length)? generateOtp,
  }) : _secret = secret,
       _rateLimitHashKey = utf8.encode(secret),
       _generateOtp = generateOtp ?? _defaultOtp,
       assert(otpLength >= 4 && otpLength <= 12),
       assert(expiresIn > Duration.zero),
       assert(allowedAttempts > 0) {
    if (_rateLimitHashKey.length < 32) {
      throw ArgumentError(
        'secret must contain at least 32 UTF-8 bytes',
        'secret',
      );
    }
  }

  /// Callback that receives the raw OTP only for delivery.
  final AuthEmailOtpSender<TContext> sendCode;

  /// Number of decimal digits generated for each OTP.
  final int otpLength;

  /// Lifetime of an issued OTP.
  final Duration expiresIn;

  /// Maximum failed attempts before lockout.
  final int allowedAttempts;

  /// Whether sign-in rejects unknown email addresses instead of creating users.
  final bool disableSignUp;
  final String _secret;
  final List<int> _rateLimitHashKey;
  final String Function(int length) _generateOtp;

  late AuthEmailOtpStore _store;
  late AuthEmailOtpBackend _backend;
  late AuthUserStore _users;
  late AuthUserDeletionDomain _deletionDomain;
  bool _configured = false;

  /// Stable plugin identifier.
  @override
  String get id => authEmailOtpPluginId;

  /// Declares the OTP authentication and user-data namespaces.
  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract(
        authenticationMethodNamespace: authEmailOtpPluginId,
        userDataNamespace: authEmailOtpPluginId,
      );

  /// Namespace for user data owned by this plugin.
  @override
  String get userDataNamespace => authEmailOtpPluginId;

  /// Namespace for OTP authentication methods.
  @override
  String get authenticationMethodNamespace => authEmailOtpPluginId;

  /// Configured OTP store used for authentication-method inventory.
  @override
  Object get authenticationMethodStore => _store;

  /// Authentication-method kinds exposed by this plugin.
  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.emailOtp,
  };

  /// Lists the active OTP method for an eligible [userId].
  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async {
    _ensureConfigured();
    final user = await _users.findById(userId);
    return AuthAuthenticationMethodSnapshot.complete([
      if (user?.email?.isNotEmpty == true && !authUserIsDisabled(user!))
        AuthAuthenticationMethod.emailOtp(userId),
    ]);
  }

  /// Configures the typed OTP backend and deletion-coordinator host.
  ///
  /// Throws [StateError] when either required host contract is unavailable.
  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final store = context.store;
    if (store is! AuthEmailOtpBackend) {
      throw StateError(
        'EmailOtpPlugin requires an AuthEmailOtpBackend. Durable adapters '
        'must implement the typed command boundary transactionally.',
      );
    }
    _backend = store as AuthEmailOtpBackend;
    _store = _backend.emailOtpStore;
    _users = context.store.users;
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError(
        'EmailOtpPlugin requires a deletion-coordinator host store.',
      );
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
    _configured = true;
  }

  /// Creates a plan that removes OTP records for [user].
  @override
  Future<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user) async {
    _ensureConfigured();
    final email = user.email;
    final deletionStore = _store;
    if (deletionStore is AuthUserDeletionPlanFactory) {
      return Future.sync(
        () => (deletionStore as AuthUserDeletionPlanFactory).createDeletionPlan(
          domain: _deletionDomain,
          user: user,
          namespace: userDataNamespace,
        ),
      );
    }
    if (email == null || email.trim().isEmpty) {
      return AuthNoopUserDeletionPlan(
        domain: _deletionDomain,
        userId: user.id,
        namespace: userDataNamespace,
      );
    }
    if (_deletionDomain is! AuthInMemoryUserDeletionDomain ||
        deletionStore is! InMemoryAuthEmailOtpStore) {
      throw StateError('The email OTP adapter has no plan for this domain.');
    }
    return AuthInMemoryUserDeletionPlan(
      domain: _deletionDomain as AuthInMemoryUserDeletionDomain,
      userId: user.id,
      namespace: userDataNamespace,
      operation: _InMemoryEmailOtpDeletionOperation(
        store: deletionStore,
        email: email,
      ),
    );
  }

  /// POST endpoint contracts for issuing, checking, signing in, and verifying email.
  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _endpoint(
      id: 'emailOtp.sendVerificationOtp',
      path: const AuthRoutePath('/email-otp/send-verification-otp'),
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'send',
    ),
    _endpoint(
      id: 'emailOtp.checkVerificationOtp',
      path: const AuthRoutePath('/email-otp/check-verification-otp'),
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'check',
    ),
    _endpoint(
      id: 'emailOtp.signIn',
      path: const AuthRoutePath('/sign-in/email-otp'),
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.browser,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'sign_in',
    ),
    _endpoint(
      id: 'emailOtp.verifyEmail',
      path: const AuthRoutePath('/email-otp/verify-email'),
      authentication: AuthOperationAuthentication.session,
      operationName: 'verify_email',
    ),
  ];

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required AuthRoutePath path,
    required AuthOperationAuthentication authentication,
    AuthOperationOriginPolicy originPolicy = AuthOperationOriginPolicy.browser,
    AuthOperationCsrfPolicy csrfPolicy = AuthOperationCsrfPolicy.required,
    required String operationName,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: AuthOperationMethod.post,
    path: path,
    semantics: id == 'emailOtp.checkVerificationOtp'
        ? const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.atomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authEmailOtpPluginId,
                atomicOperationId: 'emailOtp.verify',
              ),
            ),
            replaySafety: AuthMutationReplaySafety.singleUse,
          )
        : AuthOperationSemantics.mutation(
            persistence: const AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.nonAtomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authEmailOtpPluginId,
              ),
            ),
            replaySafety: id == 'emailOtp.sendVerificationOtp'
                ? AuthMutationReplaySafety.repeatable
                : AuthMutationReplaySafety.singleUse,
          ),
    requestCodec: _mapCodec,
    responseCodec: _objectCodec,
    authentication: authentication,
    originPolicy: originPolicy,
    csrfPolicy: csrfPolicy,
    rateLimitOperation: AuthRateLimitOperation('email_otp', operationName),
    rateLimitIdentifier: (request) => _emailRateLimitIdentifier(request),
    handler: (invocation, request) => _invokeEndpoint(id, invocation, request),
  );

  String? _emailRateLimitIdentifier(Map<String, dynamic> request) {
    final value = request['email'];
    if (value is! String) return null;
    String email;
    try {
      email = _email(value);
    } on AuthFlowException {
      return null;
    }
    final digest = Hmac(
      sha256,
      _rateLimitHashKey,
    ).convert(utf8.encode('rate-limit:email-otp:$email'));
    return 'email:${base64UrlNoPadding(digest.bytes)}';
  }

  /// Client operation descriptors derived from [endpoints].
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

  /// Rate-limit operations required by [endpoints].
  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  /// Digest-only OTP persistence schema and atomic verification operation.
  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authEmailOtpPluginId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'auth_email_otp',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'email', kind: 'email'),
            AuthFieldDescriptor(name: 'codeHash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'type', kind: 'enum'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'maxAttempts', kind: 'integer'),
            AuthFieldDescriptor(name: 'attempts', kind: 'integer'),
            AuthFieldDescriptor(name: 'consumed', kind: 'boolean'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['email', 'type'],
          ],
          indexes: <List<String>>[
            <String>['expiresAt'],
            <String>['email', 'type'],
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'emailOtp.verify',
          description: 'Increment attempts and consume a matching OTP once.',
        ),
      ],
    ),
  ];

  /// Issues and delivers a new OTP for [email] and [type].
  ///
  /// The backend commits only the digest before [sendCode] receives the raw
  /// code. Delivery failures therefore leave the committed OTP in place.
  Future<void> sendVerificationOtp({
    required TContext context,
    required String email,
    required AuthEmailOtpType type,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalizedEmail = _email(email);
    final current = (now ?? DateTime.now()).toUtc();
    final code = _generateOtp(otpLength);
    if (!RegExp('^[0-9]{${otpLength.toString()}}\$').hasMatch(code)) {
      throw StateError('Email OTP generator returned an invalid code');
    }
    final expiresAt = current.add(expiresIn);
    await Future.sync(
      () => _backend.issueEmailOtp(
        AuthEmailOtpIssueCommand(
          AuthEmailOtp(
            id: secureRandomToken(length: 16),
            email: normalizedEmail,
            codeHash: digestAuthEmailOtpCode(code: code, secret: _secret),
            type: type,
            createdAt: current,
            expiresAt: expiresAt,
            maxAttempts: allowedAttempts,
          ),
        ),
      ),
    );
    await sendCode(
      AuthEmailOtpDelivery<TContext>(
        context: context,
        email: normalizedEmail,
        code: code,
        type: type,
        expiresAt: expiresAt,
      ),
    );
  }

  /// Verifies and consumes an OTP without creating a session.
  ///
  /// Invalid, expired, and locked records throw [AuthFlowException] with the
  /// corresponding OTP error code.
  Future<void> checkVerificationOtp({
    required String email,
    required AuthEmailOtpType type,
    required String code,
    DateTime? now,
  }) async {
    await _verify(email: email, type: type, code: code, now: now);
  }

  /// Consumes an OTP and signs in or creates its verified user.
  ///
  /// When [disableSignUp] is true, an unknown email maps to `user_not_found`.
  /// Invalid, expired, and locked codes throw [AuthFlowException].
  Future<AuthEmailOtpSignInResult> signInWithOtp({
    required TContext context,
    required String email,
    required String code,
    String? name,
    String? image,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalizedEmail = _email(email);
    final result = await Future.sync(
      () => _backend.signInWithEmailOtp(
        AuthEmailOtpSignInCommand(
          email: normalizedEmail,
          codeHash: _digestCode(code),
          now: now ?? DateTime.now(),
          candidate: AuthUser(
            id: secureRandomToken(length: 24),
            email: normalizedEmail,
            name: name?.trim().isEmpty == true ? null : name?.trim(),
            image: image?.trim().isEmpty == true ? null : image?.trim(),
          ),
          disableSignUp: disableSignUp,
        ),
      ),
    );
    final user = _requireAppliedTransition(result);
    return AuthEmailOtpSignInResult(user: user);
  }

  /// Consumes an OTP to verify the authenticated user's current email.
  ///
  /// Throws [AuthFlowException] for an unknown user, invalid code, expiry, or
  /// lockout. The user returned by the backend contains the verified state.
  Future<AuthUser> verifyEmail({
    required String userId,
    required String code,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final user = await _users.findById(userId);
    final email = user?.email;
    if (user == null || email == null) throw AuthFlowException('invalid_otp');
    final result = await Future.sync(
      () => _backend.verifyUserEmailWithOtp(
        AuthEmailOtpVerifyUserCommand(
          userId: user.id,
          email: email,
          codeHash: _digestCode(code),
          now: now ?? DateTime.now(),
        ),
      ),
    );
    return _requireAppliedTransition(result);
  }

  Future<AuthEmailOtp> _verify({
    required String email,
    required AuthEmailOtpType type,
    required String code,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalizedEmail = _email(email);
    if (code.trim().isEmpty) throw AuthFlowException('invalid_otp');
    final result = await Future.sync(
      () => _backend.verifyEmailOtp(
        AuthEmailOtpVerifyCommand(
          email: normalizedEmail,
          type: type,
          codeHash: _digestCode(code),
          now: now ?? DateTime.now(),
        ),
      ),
    );
    switch (result.status) {
      case AuthEmailOtpVerificationStatus.verified:
        return result.otp!;
      case AuthEmailOtpVerificationStatus.expired:
        throw AuthFlowException('otp_expired');
      case AuthEmailOtpVerificationStatus.tooManyAttempts:
        throw AuthFlowException('otp_too_many_attempts');
      case AuthEmailOtpVerificationStatus.invalid:
        throw AuthFlowException('invalid_otp');
    }
  }

  String _digestCode(String code) {
    try {
      return digestAuthEmailOtpCode(code: code, secret: _secret);
    } on ArgumentError {
      throw AuthFlowException('invalid_otp');
    }
  }

  static AuthUser _requireAppliedTransition(
    AuthEmailOtpUserTransitionResult result,
  ) {
    switch (result.status) {
      case AuthEmailOtpUserTransitionStatus.applied:
        final user = result.user;
        if (user == null || authUserIsDisabled(user)) {
          throw AuthFlowException('user_not_found');
        }
        return user;
      case AuthEmailOtpUserTransitionStatus.expired:
        throw AuthFlowException('otp_expired');
      case AuthEmailOtpUserTransitionStatus.tooManyAttempts:
        throw AuthFlowException('otp_too_many_attempts');
      case AuthEmailOtpUserTransitionStatus.invalid:
        throw AuthFlowException('invalid_otp');
      case AuthEmailOtpUserTransitionStatus.userNotFound:
      case AuthEmailOtpUserTransitionStatus.userUnavailable:
        throw AuthFlowException('user_not_found');
    }
  }

  Future<Object?> _invokeEndpoint(
    String id,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    switch (id) {
      case 'emailOtp.sendVerificationOtp':
        await sendVerificationOtp(
          context: invocation.context,
          email: _string(input, 'email'),
          type: _type(input['type']),
        );
        return <String, dynamic>{'status': 'verification_sent'};
      case 'emailOtp.checkVerificationOtp':
        await checkVerificationOtp(
          email: _string(input, 'email'),
          type: _type(input['type']),
          code: _string(input, 'otp'),
        );
        return <String, dynamic>{'status': 'valid'};
      case 'emailOtp.signIn':
        final result = await signInWithOtp(
          context: invocation.context,
          email: _string(input, 'email'),
          code: _string(input, 'otp'),
          name: input['name']?.toString(),
          image: input['image']?.toString(),
        );
        return AuthEndpointAuthenticationIntent(
          user: result.user,
          authenticationMethod: 'email_otp',
          metadata: const <String, dynamic>{'status': 'authenticated'},
        );
      case 'emailOtp.verifyEmail':
        final user = invocation.user;
        if (user == null) throw AuthFlowException('unauthorized');
        final updated = await verifyEmail(
          userId: user.id,
          code: _string(input, 'otp'),
        );
        return <String, dynamic>{
          'status': 'email_verified',
          'user': updated.redacted().toJson(),
        };
      default:
        throw StateError('Unknown email OTP endpoint $id');
    }
  }

  void _ensureConfigured() {
    if (!_configured) throw StateError('EmailOtpPlugin is not configured');
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

  static String _email(String value) {
    try {
      return normalizeAuthOneTimeEmail(value);
    } on ArgumentError {
      throw AuthFlowException('invalid_email');
    }
  }

  static String _string(Map<String, dynamic> input, String key) {
    final value = input[key];
    if (value is! String || value.trim().isEmpty) {
      throw AuthFlowException('invalid_request');
    }
    return value.trim();
  }

  static AuthEmailOtpType _type(Object? value) {
    switch (value?.toString()) {
      case 'sign-in':
        return AuthEmailOtpType.signIn;
      case 'email-verification':
        return AuthEmailOtpType.emailVerification;
      case 'forget-password':
        return AuthEmailOtpType.forgetPassword;
      case 'change-email':
        return AuthEmailOtpType.changeEmail;
      default:
        throw AuthFlowException('invalid_otp_type');
    }
  }

  static String _defaultOtp(int length) {
    final random = secureRandomToken(length: length + 4);
    return String.fromCharCodes(
      List<int>.generate(length, (index) => 48 + random.codeUnitAt(index) % 10),
    );
  }
}

final class _InMemoryEmailOtpDeletionOperation
    implements AuthInMemoryUserDeletionOperation {
  const _InMemoryEmailOtpDeletionOperation({
    required this.store,
    required this.email,
  });

  final InMemoryAuthEmailOtpStore store;
  final String email;

  @override
  Object captureState() => store.captureDeletionState();

  @override
  Future<void> apply() => store.deleteForEmail(email);

  @override
  void restoreState(Object state) => store.restoreDeletionState(state);
}
