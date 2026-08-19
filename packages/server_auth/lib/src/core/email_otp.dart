import 'dart:async';

import 'email_otp_store.dart';
import 'exceptions.dart';
import 'feature.dart';
import 'models.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show secureRandomToken;
import 'users.dart' show authUserIsDisabled;

const String authEmailOtpFeatureId = 'email_otp';

typedef AuthEmailOtpSender<TContext> =
    FutureOr<void> Function(AuthEmailOtpDelivery<TContext> delivery);

final class AuthEmailOtpDelivery<TContext> {
  const AuthEmailOtpDelivery({
    required this.context,
    required this.email,
    required this.code,
    required this.type,
    required this.expiresAt,
  });

  final TContext context;
  final String email;
  final String code;
  final AuthEmailOtpType type;
  final DateTime expiresAt;
}

final class AuthEmailOtpSignInResult {
  const AuthEmailOtpSignInResult({required this.user, this.session});

  final AuthUser user;
  final AuthSession? session;
}

/// Typed email OTP feature modeled on the common sign-in, verification, and
/// password-recovery OTP flows.
final class EmailOtpFeature<TContext>
    implements
        AuthFeature<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDataDeletionContributor {
  EmailOtpFeature({
    required this.sendCode,
    this.otpLength = 6,
    this.expiresIn = const Duration(minutes: 5),
    this.allowedAttempts = 3,
    this.disableSignUp = false,
    String Function(int length)? generateOtp,
  }) : _generateOtp = generateOtp ?? _defaultOtp,
       assert(otpLength >= 4 && otpLength <= 12),
       assert(expiresIn > Duration.zero),
       assert(allowedAttempts > 0);

  final AuthEmailOtpSender<TContext> sendCode;
  final int otpLength;
  final Duration expiresIn;
  final int allowedAttempts;
  final bool disableSignUp;
  final String Function(int length) _generateOtp;

  late AuthEmailOtpStore _store;
  late AuthUserStore _users;
  bool _configured = false;

  @override
  String get id => authEmailOtpFeatureId;

  @override
  String get userDataNamespace => authEmailOtpFeatureId;

  @override
  void configure(AuthFeatureContext<TContext> context) {
    _store = context.store.emailOtps;
    _users = context.store.users;
    _configured = true;
  }

  @override
  Future<void> validateUserDeletion(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must be non-empty');
    }
  }

  @override
  Future<void> deleteUserData(String userId) async {
    _ensureConfigured();
    final user = await _users.findById(userId);
    final email = user?.email;
    if (email != null) await _store.deleteForEmail(email);
  }

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _endpoint(
      id: 'emailOtp.sendVerificationOtp',
      path: '/email-otp/send-verification-otp',
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'send',
    ),
    _endpoint(
      id: 'emailOtp.checkVerificationOtp',
      path: '/email-otp/check-verification-otp',
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'check',
    ),
    _endpoint(
      id: 'emailOtp.signIn',
      path: '/sign-in/email-otp',
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'sign_in',
    ),
    _endpoint(
      id: 'emailOtp.verifyEmail',
      path: '/email-otp/verify-email',
      authentication: AuthOperationAuthentication.session,
      operationName: 'verify_email',
    ),
  ];

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required String path,
    required AuthOperationAuthentication authentication,
    AuthOperationOriginPolicy originPolicy = AuthOperationOriginPolicy.browser,
    AuthOperationCsrfPolicy csrfPolicy = AuthOperationCsrfPolicy.required,
    required String operationName,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: AuthOperationMethod.post,
    path: path,
    requestCodec: _mapCodec,
    responseCodec: _objectCodec,
    authentication: authentication,
    originPolicy: originPolicy,
    csrfPolicy: csrfPolicy,
    rateLimitOperation: AuthRateLimitOperation('email_otp', operationName),
    handler: (invocation, request) => _invokeEndpoint(id, invocation, request),
  );

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      serverOnly: endpoint.serverOnly,
    ),
  );

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authEmailOtpFeatureId,
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
    await _store.save(
      AuthEmailOtp(
        id: secureRandomToken(length: 16),
        email: normalizedEmail,
        codeHash: hashAuthEmailOtpCode(code),
        type: type,
        createdAt: current,
        expiresAt: expiresAt,
        maxAttempts: allowedAttempts,
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

  Future<void> checkVerificationOtp({
    required String email,
    required AuthEmailOtpType type,
    required String code,
    DateTime? now,
  }) async {
    await _verify(email: email, type: type, code: code, now: now);
  }

  Future<AuthEmailOtpSignInResult> signInWithOtp({
    required TContext context,
    required String email,
    required String code,
    String? name,
    String? image,
    DateTime? now,
    AuthFeatureSessionControl? sessionControl,
  }) async {
    await _verify(
      email: email,
      type: AuthEmailOtpType.signIn,
      code: code,
      now: now,
    );
    final normalizedEmail = _email(email);
    var user = await _users.findByEmail(normalizedEmail);
    if (user == null) {
      if (disableSignUp) throw AuthFlowException('user_not_found');
      final candidate = AuthUser(
        id: secureRandomToken(length: 24),
        email: normalizedEmail,
        name: name?.trim().isEmpty == true ? null : name?.trim(),
        image: image?.trim().isEmpty == true ? null : image?.trim(),
        attributes: const <String, dynamic>{'emailVerified': true},
      );
      try {
        user = (await _users.createOrFindByEmail(candidate)).user;
      } catch (_) {
        user = await _users.findByEmail(normalizedEmail);
      }
    }
    if (user == null || authUserIsDisabled(user)) {
      throw AuthFlowException('user_not_found');
    }
    if (user.attributes['emailVerified'] != true) {
      user = AuthUser(
        id: user.id,
        email: user.email,
        name: user.name,
        image: user.image,
        roles: user.roles,
        attributes: <String, dynamic>{
          ...user.attributes,
          'emailVerified': true,
        },
      );
      user = await _users.update(user) ?? user;
    }
    AuthSession? session;
    if (sessionControl != null) {
      session = await sessionControl.replaceIdentity(
        user,
        authenticationMethod: 'email_otp',
      );
    }
    return AuthEmailOtpSignInResult(user: user, session: session);
  }

  Future<AuthUser> verifyEmail({
    required String userId,
    required String code,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final user = await _users.findById(userId);
    final email = user?.email;
    if (user == null || email == null) throw AuthFlowException('invalid_otp');
    await _verify(
      email: email,
      type: AuthEmailOtpType.emailVerification,
      code: code,
      now: now,
    );
    final updated = AuthUser(
      id: user.id,
      email: user.email,
      name: user.name,
      image: user.image,
      roles: user.roles,
      attributes: <String, dynamic>{...user.attributes, 'emailVerified': true},
    );
    return await _users.update(updated) ?? updated;
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
    final result = await _store.verify(normalizedEmail, type, code, now: now);
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
          sessionControl: invocation.sessionControl,
        );
        final session = result.session;
        if (session != null) return session.redacted().toJson();
        return <String, dynamic>{
          'status': 'authenticated',
          'user': result.user.redacted().toJson(),
        };
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
    if (!_configured) throw StateError('EmailOtpFeature is not configured');
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
    final normalized = normalizeAuthEmailOtpEmail(value);
    if (normalized.isEmpty ||
        normalized.length > 320 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw AuthFlowException('invalid_email');
    }
    return normalized;
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
