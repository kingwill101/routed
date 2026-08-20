import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show Hmac, sha256;

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'models.dart';
import 'phone_number_store.dart';
import 'plugin.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show base64UrlNoPadding, secureRandomToken;
import 'users.dart' show authUserIsDisabled;

const String authPhoneNumberPluginId = 'phone_number';
const String authPhoneNumberAuthenticationMethod = 'phone_number';

const AuthRateLimitOperation authPhoneNumberSendRateLimitOperation =
    AuthRateLimitOperation(authPhoneNumberPluginId, 'send_code');
const AuthRateLimitOperation authPhoneNumberVerifyRateLimitOperation =
    AuthRateLimitOperation(authPhoneNumberPluginId, 'verify_code');

/// Normalizes application input into a canonical phone number or rejects it.
abstract interface class AuthPhoneNumberPolicy {
  String? normalize(String input);
}

/// Strict E.164 policy without locale-dependent guessing.
///
/// Input is trimmed at its edges, then must already be `+` followed by 2 to
/// 15 ASCII digits. The first digit cannot be zero. Formatting punctuation,
/// national numbers, Unicode digits, extensions, and embedded whitespace are
/// rejected rather than interpreted ambiguously.
final class AuthE164PhoneNumberPolicy implements AuthPhoneNumberPolicy {
  const AuthE164PhoneNumberPolicy();

  static final RegExp _pattern = RegExp(r'^\+[1-9][0-9]{1,14}$');

  @override
  String? normalize(String input) {
    final candidate = input.trim();
    return _pattern.hasMatch(candidate) ? candidate : null;
  }
}

typedef AuthPhoneNumberCodeSender<TContext> =
    FutureOr<void> Function(AuthPhoneNumberCodeDelivery<TContext> delivery);

typedef AuthPhoneNumberUserFactory<TContext> =
    FutureOr<AuthUser> Function(
      TContext context,
      String phoneNumber,
      String? name,
    );

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
  const AuthPhoneNumberCodeDelivery({
    required this.context,
    required this.phoneNumber,
    required this.code,
    required this.expiresAt,
  });

  final TContext context;
  final String phoneNumber;
  final String code;
  final DateTime expiresAt;
}

final class AuthPhoneNumberCodeIssued {
  const AuthPhoneNumberCodeIssued({required this.expiresAt});

  final DateTime expiresAt;
}

final class AuthPhoneNumberSignInResult {
  const AuthPhoneNumberSignInResult({
    required this.phoneNumber,
    required this.user,
    this.session,
  });

  final String phoneNumber;
  final AuthUser user;
  final AuthSession? session;
}

final class AuthPhoneNumberSendCodeRequest {
  const AuthPhoneNumberSendCodeRequest({required this.phoneNumber});

  final String phoneNumber;

  factory AuthPhoneNumberSendCodeRequest.fromJson(Map<String, dynamic> json) =>
      AuthPhoneNumberSendCodeRequest(
        phoneNumber: _requiredString(json, 'phoneNumber'),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'phoneNumber': phoneNumber,
  };
}

final class AuthPhoneNumberSendCodeResponse {
  const AuthPhoneNumberSendCodeResponse({required this.expiresAt});

  final DateTime expiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': 'verification_sent',
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

final class AuthPhoneNumberVerifyRequest {
  const AuthPhoneNumberVerifyRequest({
    required this.phoneNumber,
    required this.code,
    this.name,
  });

  final String phoneNumber;
  final String code;
  final String? name;

  factory AuthPhoneNumberVerifyRequest.fromJson(Map<String, dynamic> json) =>
      AuthPhoneNumberVerifyRequest(
        phoneNumber: _requiredString(json, 'phoneNumber'),
        code: _requiredString(json, 'code'),
        name: _optionalString(json, 'name'),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'phoneNumber': phoneNumber,
    'code': code,
    if (name != null) 'name': name,
  };
}

final class AuthPhoneNumberVerifyResponse {
  const AuthPhoneNumberVerifyResponse({
    required this.phoneNumber,
    required this.user,
    this.session,
  });

  final String phoneNumber;
  final AuthUser user;
  final AuthSession? session;

  Map<String, dynamic> toJson() {
    final sourceSession = session;
    final safeSession = sourceSession == null
        ? null
        : AuthSession(
            user: sourceSession.user.redacted(),
            expiresAt: sourceSession.expiresAt,
            strategy: sourceSession.strategy,
            token: sourceSession.token,
          );
    return <String, dynamic>{
      'status': 'authenticated',
      'phoneNumber': phoneNumber,
      if (safeSession != null)
        ...safeSession.toJson(includeToken: true)
      else
        'user': user.redacted().toJson(),
    };
  }
}

/// Phone-number OTP authentication as an opt-in server plugin.
final class PhoneNumberPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthReversibleUserDataDeletionContributor {
  PhoneNumberPlugin({
    required this.store,
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

  final AuthPhoneNumberStore store;
  final AuthPhoneNumberCodeSender<TContext> sendCode;
  final AuthPhoneNumberPolicy phoneNumberPolicy;
  final int codeLength;
  final Duration expiresIn;
  final int allowedAttempts;
  final bool allowSignUp;
  final AuthPhoneNumberUserFactory<TContext>? createUser;
  final AuthPhoneNumberVerifiedCallback<TContext>? onVerified;
  final List<int> _codeHashKey;
  final String Function(int length) _generateCode;

  late AuthUserStore _users;
  bool _configured = false;

  @override
  String get id => authPhoneNumberPluginId;

  @override
  String get userDataNamespace => authPhoneNumberPluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _users = context.store.users;
    _configured = true;
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
          path: '/phone-number/send-code',
          requestCodec: _sendRequestCodec,
          responseCodec: _sendResponseCodec,
          authentication: AuthOperationAuthentication.none,
          originPolicy: AuthOperationOriginPolicy.browser,
          csrfPolicy: AuthOperationCsrfPolicy.none,
          rateLimitOperation: authPhoneNumberSendRateLimitOperation,
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
          path: '/phone-number/verify-code',
          requestCodec: _verifyRequestCodec,
          responseCodec: _verifyResponseCodec,
          authentication: AuthOperationAuthentication.none,
          originPolicy: AuthOperationOriginPolicy.browser,
          csrfPolicy: AuthOperationCsrfPolicy.none,
          rateLimitOperation: authPhoneNumberVerifyRateLimitOperation,
          handler: (invocation, request) async {
            final result = await verifyCode(
              context: invocation.context,
              phoneNumber: request.phoneNumber,
              code: request.code,
              name: request.name,
              sessionControl: invocation.sessionControl,
            );
            return AuthPhoneNumberVerifyResponse(
              phoneNumber: result.phoneNumber,
              user: result.user,
              session: result.session,
            );
          },
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

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations =>
      const <AuthRateLimitOperation>[
        authPhoneNumberSendRateLimitOperation,
        authPhoneNumberVerifyRateLimitOperation,
      ];

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas =>
      const <AuthPersistenceSchema>[
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
                AuthFieldDescriptor(name: 'consumedAt', kind: 'datetime'),
              ],
              uniqueConstraints: <List<String>>[
                <String>['phoneNumber'],
              ],
              indexes: <List<String>>[
                <String>['expiresAt'],
              ],
            ),
          ],
          atomicOperations: <AuthAtomicOperationDescriptor>[
            AuthAtomicOperationDescriptor(
              id: 'phoneNumber.consumeVerification',
              description:
                  'Increment attempts and consume a matching active code once.',
            ),
            AuthAtomicOperationDescriptor(
              id: 'phoneNumber.bindIdentity',
              description:
                  'Bind one unique E.164 phone number to one auth user.',
            ),
          ],
        ),
      ];

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
    await store.saveVerification(verification);
    try {
      await sendCode(
        AuthPhoneNumberCodeDelivery<TContext>(
          context: context,
          phoneNumber: normalized,
          code: rawCode,
          expiresAt: verification.expiresAt,
        ),
      );
    } catch (_) {
      await store.deleteVerificationIfCurrent(normalized, verification.id);
      rethrow;
    }
    return AuthPhoneNumberCodeIssued(expiresAt: verification.expiresAt);
  }

  Future<AuthPhoneNumberSignInResult> verifyCode({
    required TContext context,
    required String phoneNumber,
    required String code,
    String? name,
    DateTime? now,
    AuthServerPluginSessionControl? sessionControl,
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
    final verification = await store.consumeVerification(
      normalized,
      _digest(normalized, normalizedCode),
      now: current,
    );
    switch (verification.status) {
      case AuthPhoneNumberVerificationStatus.invalid:
        throw AuthFlowException('invalid_phone_code');
      case AuthPhoneNumberVerificationStatus.expired:
        throw AuthFlowException('phone_code_expired');
      case AuthPhoneNumberVerificationStatus.tooManyAttempts:
        throw AuthFlowException('phone_code_too_many_attempts');
      case AuthPhoneNumberVerificationStatus.verified:
        break;
    }

    var identity = await store.findIdentity(normalized);
    var user = identity == null ? null : await _users.findById(identity.userId);
    if (identity != null && user == null) {
      throw AuthFlowException('user_not_found');
    }
    if (user == null) {
      if (!allowSignUp) throw AuthFlowException('user_not_found');
      final requestedName = name?.trim();
      final candidate = await Future.sync(
        () =>
            createUser?.call(
              context,
              normalized,
              requestedName?.isEmpty == true ? null : requestedName,
            ) ??
            AuthUser(
              id: secureRandomToken(length: 24),
              name: requestedName?.isEmpty == true ? null : requestedName,
              attributes: const <String, dynamic>{'phoneNumberVerified': true},
            ),
      );
      final created = await _users.create(candidate);
      final requestedIdentity = AuthPhoneNumberIdentity(
        phoneNumber: normalized,
        userId: created.id,
        createdAt: current,
        verifiedAt: current,
      );
      try {
        identity = await store.bindIdentity(requestedIdentity);
      } catch (_) {
        await _users.delete(created.id);
        rethrow;
      }
      if (identity.userId != created.id) {
        await _users.delete(created.id);
        user = await _users.findById(identity.userId);
      } else {
        user = created;
      }
    }
    if (user == null || authUserIsDisabled(user)) {
      throw AuthFlowException('user_not_found');
    }
    if (user.attributes['phoneNumberVerified'] != true) {
      final verifiedUser = AuthUser(
        id: user.id,
        email: user.email,
        name: user.name,
        image: user.image,
        roles: user.roles,
        isAnonymous: user.isAnonymous,
        attributes: <String, dynamic>{
          ...user.attributes,
          'phoneNumberVerified': true,
        },
      );
      user = await _users.update(verifiedUser) ?? verifiedUser;
    }
    await onVerified?.call(context, normalized, user);
    final session = sessionControl == null
        ? null
        : await sessionControl.replaceIdentity(
            user,
            authenticationMethod: authPhoneNumberAuthenticationMethod,
          );
    return AuthPhoneNumberSignInResult(
      phoneNumber: normalized,
      user: user,
      session: session,
    );
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
    await store.deleteForUser(userId);
  }

  @override
  AuthUserDataDeletionCheckpoint checkpointUserData(String userId) {
    _ensureConfigured();
    return AuthUserDataDeletionCheckpoint.capture(<Object>[store]);
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
    encode: (value) => value.toJson(),
    schema: _verifyResponseSchema,
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
