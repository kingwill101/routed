import '../core/api_key.dart';
import '../core/email_otp.dart';
import '../core/models.dart';
import '../core/phone_number.dart';
import '../core/phone_number_store.dart';
import '../core/providers.dart';
import 'auth_test_primitives.dart';

/// Credentials provider with a deterministic, explicitly test-only identity.
final class AuthCredentialsProviderFixture {
  /// Creates a credentials fixture.
  AuthCredentialsProviderFixture({
    this.email = 'fixture@example.test',
    this.username = 'fixture-user',
    this.password = 'fixture-password-not-a-secret',
    AuthUser? user,
  }) : user = user ?? AuthUser(id: 'fixture-user-id', email: email) {
    provider = CredentialsProvider(
      authorize: (context, provider, credentials) {
        authorizationAttempts.add(credentials.redacted());
        return matches(credentials) ? this.user : null;
      },
      register: (context, provider, credentials) {
        registrationAttempts.add(credentials.redacted());
        return matches(credentials) ? this.user : null;
      },
    );
  }

  /// Test email accepted by [provider].
  final String email;

  /// Test username accepted by [provider].
  final String username;

  /// Obvious fixture password. It must never be used outside tests.
  final String password;

  /// User returned for matching requests.
  final AuthUser user;

  /// Real credentials provider configured by the fixture.
  late final CredentialsProvider provider;

  /// Redacted authorization attempts.
  final List<AuthCredentials> authorizationAttempts = <AuthCredentials>[];

  /// Redacted registration attempts.
  final List<AuthCredentials> registrationAttempts = <AuthCredentials>[];

  /// Valid credentials for success-path tests.
  AuthCredentials get credentials =>
      AuthCredentials(email: email, username: username, password: password);

  /// Whether [credentials] match the fixture identity.
  bool matches(AuthCredentials credentials) =>
      credentials.password == password &&
      (credentials.email?.trim().toLowerCase() == email.toLowerCase() ||
          credentials.username?.trim() == username);
}

/// Captures email OTP delivery and supplies deterministic numeric codes.
final class AuthEmailOtpFixture<TContext> {
  /// Creates an email OTP fixture from [codes].
  AuthEmailOtpFixture({Iterable<String> codes = const <String>['123456']})
    : _codes = AuthTestSequence<String>(codes);

  final AuthTestSequence<String> _codes;

  static const String _testOnlyHashKey =
      'fixture-only-email-otp-key-not-for-production-use';

  /// Raw delivery payloads retained in memory for the test only.
  final AuthTestDeliveryLog<AuthEmailOtpDelivery<TContext>> deliveries =
      AuthTestDeliveryLog<AuthEmailOtpDelivery<TContext>>();

  /// Creates a real email OTP plugin wired to this fixture.
  EmailOtpPlugin<TContext> plugin({
    Duration expiresIn = const Duration(minutes: 5),
    int allowedAttempts = 3,
    bool disableSignUp = false,
  }) => EmailOtpPlugin<TContext>(
    sendCode: deliveries.capture,
    secret: _testOnlyHashKey,
    generateOtp: _nextCode,
    expiresIn: expiresIn,
    allowedAttempts: allowedAttempts,
    disableSignUp: disableSignUp,
  );

  String _nextCode(int length) {
    final code = _codes.next();
    if (code.length != length) {
      throw StateError('Email OTP fixture code has the wrong length');
    }
    return code;
  }
}

/// Captures phone OTP delivery and supplies deterministic numeric codes.
final class AuthPhoneOtpFixture<TContext> {
  /// Creates a phone OTP fixture from [codes].
  AuthPhoneOtpFixture({Iterable<String> codes = const <String>['123456']})
    : _codes = AuthTestSequence<String>(codes);

  static const String _testOnlyHashKey =
      'fixture-only-phone-code-key-not-for-production-use';

  final AuthTestSequence<String> _codes;

  /// Raw delivery payloads retained in memory for the test only.
  final AuthTestDeliveryLog<AuthPhoneNumberCodeDelivery<TContext>> deliveries =
      AuthTestDeliveryLog<AuthPhoneNumberCodeDelivery<TContext>>();

  /// Creates a real phone plugin with in-memory storage.
  ///
  /// The digest key is intentionally public and fixture-only. Production code
  /// must supply an application secret instead of copying this setup.
  PhoneNumberPlugin<TContext> plugin({
    AuthPhoneNumberStore? store,
    Duration expiresIn = const Duration(minutes: 5),
    int allowedAttempts = 3,
    bool allowSignUp = true,
  }) => PhoneNumberPlugin<TContext>(
    store: store ?? InMemoryAuthPhoneNumberStore(),
    sendCode: deliveries.capture,
    codeHashKey: _testOnlyHashKey,
    generateCode: _nextCode,
    expiresIn: expiresIn,
    allowedAttempts: allowedAttempts,
    allowSignUp: allowSignUp,
  );

  String _nextCode(int length) {
    final code = _codes.next();
    if (code.length != length) {
      throw StateError('Phone OTP fixture code has the wrong length');
    }
    return code;
  }
}

/// OAuth/OIDC provider metadata with deterministic test endpoints and profile.
final class AuthOAuthProviderFixture {
  /// Creates a provider fixture hosted below `https://provider.example.test`.
  AuthOAuthProviderFixture({
    this.providerId = 'fixture-oauth',
    this.profile = const <String, dynamic>{
      'sub': 'fixture-account',
      'email': 'fixture@example.test',
      'name': 'Fixture User',
    },
    this.type = AuthProviderType.oauth,
  }) {
    provider = OAuthProvider<Map<String, dynamic>>(
      id: providerId,
      name: 'Fixture OAuth',
      clientId: 'fixture-client-id',
      clientSecret: 'fixture-client-secret-not-a-secret',
      authorizationEndpoint: origin.resolve('/authorize'),
      tokenEndpoint: origin.resolve('/token'),
      userInfoEndpoint: origin.resolve('/userinfo'),
      redirectUri: 'https://app.example.test/auth/callback/$providerId',
      type: type,
      scopes: const <String>['openid', 'profile', 'email'],
      profile: (claims) => AuthUser(
        id: claims['sub']?.toString() ?? '',
        email: claims['email']?.toString(),
        name: claims['name']?.toString(),
      ),
    );
  }

  /// Stable provider origin used by token and userinfo requests.
  static final Uri origin = Uri.parse('https://provider.example.test');

  final String providerId;
  final Map<String, dynamic> profile;
  final AuthProviderType type;

  /// Real OAuth provider configured by the fixture.
  late final OAuthProvider<Map<String, dynamic>> provider;

  /// Successful token endpoint payload.
  Map<String, dynamic> tokenResponse({String accessToken = 'fixture-access'}) =>
      <String, dynamic>{
        'access_token': accessToken,
        'token_type': 'Bearer',
        'expires_in': 3600,
      };

  /// Successful userinfo endpoint payload.
  Map<String, dynamic> userInfoResponse() => Map<String, dynamic>.from(profile);
}

/// Browser-shaped WebAuthn values for typed client codec tests.
///
/// The credential bytes are placeholders, not cryptographic assertions. Use a
/// platform authenticator integration test for server signature verification.
final class AuthWebAuthnClientFixture {
  /// Creates a deterministic passkey client fixture.
  const AuthWebAuthnClientFixture({
    this.userId = 'fixture-user-id',
    this.credentialId = 'Zml4dHVyZS1jcmVkZW50aWFs',
  });

  final String userId;
  final String credentialId;

  /// Registration options accepted by the real typed client parser.
  Map<String, dynamic> registrationOptions() => <String, dynamic>{
    'challenge': 'Zml4dHVyZS1yZWdpc3RyYXRpb24',
    'rp': <String, dynamic>{'id': 'example.test', 'name': 'Fixture RP'},
    'user': <String, dynamic>{
      'id': userId,
      'name': 'fixture@example.test',
      'displayName': 'Fixture User',
    },
    'pubKeyCredParams': <Map<String, dynamic>>[
      <String, dynamic>{'type': 'public-key', 'alg': -7},
    ],
    'timeout': 60000,
  };

  /// Discoverable authentication options accepted by the typed client parser.
  Map<String, dynamic> authenticationOptions() => <String, dynamic>{
    'challenge': 'Zml4dHVyZS1hdXRoZW50aWNhdGlvbg',
    'rpId': 'example.test',
    'timeout': 60000,
    'userVerification': 'preferred',
    'allowCredentials': <Map<String, dynamic>>[],
  };

  /// Browser-shaped assertion request passed through the real client codec.
  Map<String, dynamic> assertion() => <String, dynamic>{
    'id': credentialId,
    'rawId': credentialId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': 'Zml4dHVyZS1jbGllbnQtZGF0YQ',
      'authenticatorData': 'Zml4dHVyZS1hdXRoLWRhdGE',
      'signature': 'Zml4dHVyZS1zaWduYXR1cmU',
      'userHandle': userId,
    },
  };

  /// Successful authentication payload accepted by the typed client parser.
  Map<String, dynamic> authenticationResult() => <String, dynamic>{
    'user': <String, dynamic>{
      'id': userId,
      'email': 'fixture@example.test',
      'roles': <String>[],
      'attributes': <String, dynamic>{},
    },
    'credential': credentialMetadata(),
  };

  /// Safe passkey metadata response.
  Map<String, dynamic> credentialMetadata() => <String, dynamic>{
    'credential_id': credentialId,
    'user_id': userId,
    'counter': 1,
    'transports': <String>['internal'],
    'created_at': '2030-01-01T00:00:00Z',
    'name': 'Fixture passkey',
  };
}

/// Safe API-key metadata and one-time issuance payloads for client tests.
final class AuthApiKeyClientFixture {
  /// Creates a deterministic API-key fixture.
  const AuthApiKeyClientFixture({
    this.userId = 'fixture-user-id',
    this.keyId = 'fixture-key-id',
  });

  final String userId;
  final String keyId;

  /// Public metadata that never contains a raw key or hash.
  Map<String, dynamic> metadata({bool active = true}) => <String, dynamic>{
    'id': keyId,
    'userId': userId,
    'name': 'Fixture key',
    'keyPrefix': 'rt_fixture',
    'scopes': <String>['tasks:read'],
    'createdAt': '2030-01-01T00:00:00Z',
    'updatedAt': '2030-01-01T00:00:00Z',
    'active': active,
  };

  /// One-time creation or rotation response with an obvious test-only key.
  Map<String, dynamic> issued() => <String, dynamic>{
    ...metadata(),
    'apiKey': 'rt_fixture.fixture-raw-key-not-a-secret',
  };

  /// List response containing only safe metadata.
  Map<String, dynamic> list() => <String, dynamic>{
    'apiKeys': <Map<String, dynamic>>[metadata()],
  };
}

/// Deterministic two-factor response values for typed client codec tests.
final class AuthTwoFactorClientFixture {
  /// Creates a two-factor client fixture using [now] for expirations.
  AuthTwoFactorClientFixture(DateTime now) : now = now.toUtc();

  final DateTime now;

  /// Enrollment response with an obvious test-only TOTP secret.
  Map<String, dynamic> enrollment() => <String, dynamic>{
    'secret': 'JBSWY3DPEHPK3PXP',
    'otpauthUri':
        'otpauth://totp/Fixture:fixture%40example.test?secret=JBSWY3DPEHPK3PXP&issuer=Fixture',
    'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
  };

  /// Enabled status response.
  Map<String, dynamic> status() => <String, dynamic>{
    'enabled': true,
    'recoveryCodesRemaining': 8,
  };

  /// One-time recovery-code response.
  Map<String, dynamic> recoveryCodes() => <String, dynamic>{
    'recoveryCodes': <String>['fixture-recovery-1', 'fixture-recovery-2'],
  };
}

/// Creates public API-key metadata from a persisted test record.
AuthApiKey authTestApiKeyMetadata(AuthApiKeyRecord record, {DateTime? now}) =>
    record.toPublic(now: now);
