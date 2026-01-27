import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('WebAuthnProvider', () {
    test('creates provider with default id and name', () {
      final provider = WebAuthnProvider(
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      expect(provider.id, equals('webauthn'));
      expect(provider.name, equals('Passkey'));
      expect(provider.type, equals(AuthProviderType.webauthn));
    });

    test('creates provider with custom id and name', () {
      final provider = WebAuthnProvider(
        id: 'passkeys',
        name: 'Sign in with Passkey',
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      expect(provider.id, equals('passkeys'));
      expect(provider.name, equals('Sign in with Passkey'));
    });

    test('default timeout is 5 minutes', () {
      final provider = WebAuthnProvider(
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      expect(provider.timeout, equals(const Duration(minutes: 5)));
    });

    test('custom timeout is respected', () {
      final provider = WebAuthnProvider(
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
        timeout: const Duration(minutes: 10),
      );

      expect(provider.timeout, equals(const Duration(minutes: 10)));
    });

    test('conditional UI is enabled by default', () {
      final provider = WebAuthnProvider(
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      expect(provider.enableConditionalUI, isTrue);
    });

    test('default form fields include email', () {
      final provider = WebAuthnProvider(
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      expect(provider.formFields.containsKey('email'), isTrue);
      expect(provider.formFields['email']?.required, isTrue);
    });

    test('custom form fields are accepted', () {
      final provider = WebAuthnProvider(
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
        formFields: const {
          'username': WebAuthnFormField(
            label: 'Username',
            required: true,
            autocomplete: 'username webauthn',
          ),
        },
      );

      expect(provider.formFields.containsKey('username'), isTrue);
      expect(
        provider.formFields['username']?.autocomplete,
        equals('username webauthn'),
      );
    });

    test('getRelyingParty returns configuration', () {
      final provider = WebAuthnProvider(
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (context, provider) => const WebAuthnRelyingParty(
          id: 'myapp.example.com',
          name: 'My Application',
          origin: 'https://myapp.example.com',
        ),
      );

      final rp = provider.getRelyingParty(_MockEngineContext(), provider);

      expect(rp.id, equals('myapp.example.com'));
      expect(rp.name, equals('My Application'));
      expect(rp.origin, equals('https://myapp.example.com'));
    });

    test('getUserInfo returns existing user', () async {
      final existingUser = AuthUser(
        id: 'user-1',
        email: 'user@example.com',
        name: 'Existing User',
      );

      final provider = WebAuthnProvider(
        getUserInfo: (context, provider, request) {
          final email = request['email']?.toString();
          if (email == 'user@example.com') {
            return WebAuthnUserInfo(user: existingUser, exists: true);
          }
          return null;
        },
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      final result = await provider.getUserInfo(
        _MockEngineContext(),
        provider,
        {'email': 'user@example.com'},
      );

      expect(result, isNotNull);
      expect(result?.exists, isTrue);
      expect(result?.user.id, equals('user-1'));
    });

    test('getUserInfo returns new user for registration', () async {
      final provider = WebAuthnProvider(
        getUserInfo: (context, provider, request) {
          final email = request['email']?.toString();
          if (email != null) {
            return WebAuthnUserInfo(
              user: AuthUser(id: '', email: email),
              exists: false,
            );
          }
          return null;
        },
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      final result = await provider.getUserInfo(
        _MockEngineContext(),
        provider,
        {'email': 'new@example.com'},
      );

      expect(result, isNotNull);
      expect(result?.exists, isFalse);
      expect(result?.user.email, equals('new@example.com'));
    });

    test('getUserInfo returns null for missing email', () async {
      final provider = WebAuthnProvider(
        getUserInfo: (context, provider, request) {
          final email = request['email']?.toString();
          if (email == null || email.isEmpty) {
            return null;
          }
          return WebAuthnUserInfo(
            user: AuthUser(id: '', email: email),
            exists: false,
          );
        },
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      final result = await provider.getUserInfo(
        _MockEngineContext(),
        provider,
        {},
      );

      expect(result, isNull);
    });

    test('toJson returns provider metadata', () {
      final provider = WebAuthnProvider(
        id: 'passkey',
        name: 'Passkey Login',
        getUserInfo: (_, __, ___) => null,
        getRelyingParty: (_, __) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );

      final json = provider.toJson();

      expect(json['id'], equals('passkey'));
      expect(json['name'], equals('Passkey Login'));
      expect(json['type'], equals('webauthn'));
    });
  });

  group('WebAuthnRelyingParty', () {
    test('stores all required fields', () {
      const rp = WebAuthnRelyingParty(
        id: 'example.com',
        name: 'Example App',
        origin: 'https://example.com',
      );

      expect(rp.id, equals('example.com'));
      expect(rp.name, equals('Example App'));
      expect(rp.origin, equals('https://example.com'));
    });
  });

  group('WebAuthnAuthenticator', () {
    test('stores all required fields', () {
      final authenticator = WebAuthnAuthenticator(
        credentialId: 'cred-123',
        publicKey: 'base64-encoded-public-key',
        counter: 0,
      );

      expect(authenticator.credentialId, equals('cred-123'));
      expect(authenticator.publicKey, equals('base64-encoded-public-key'));
      expect(authenticator.counter, equals(0));
    });

    test('stores optional fields', () {
      final now = DateTime.now();
      final authenticator = WebAuthnAuthenticator(
        credentialId: 'cred-123',
        publicKey: 'public-key',
        counter: 5,
        userId: 'user-1',
        transports: ['usb', 'nfc'],
        createdAt: now,
        lastUsedAt: now,
        name: 'My YubiKey',
      );

      expect(authenticator.userId, equals('user-1'));
      expect(authenticator.transports, equals(['usb', 'nfc']));
      expect(authenticator.createdAt, equals(now));
      expect(authenticator.lastUsedAt, equals(now));
      expect(authenticator.name, equals('My YubiKey'));
    });

    test('toJson serializes all fields', () {
      final now = DateTime.parse('2024-01-15T10:30:00Z');
      final authenticator = WebAuthnAuthenticator(
        credentialId: 'cred-abc',
        publicKey: 'pk-data',
        counter: 10,
        userId: 'user-42',
        transports: ['internal'],
        createdAt: now,
        lastUsedAt: now,
        name: 'Touch ID',
      );

      final json = authenticator.toJson();

      expect(json['credential_id'], equals('cred-abc'));
      expect(json['public_key'], equals('pk-data'));
      expect(json['counter'], equals(10));
      expect(json['user_id'], equals('user-42'));
      expect(json['transports'], equals(['internal']));
      expect(json['created_at'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['name'], equals('Touch ID'));
    });

    test('fromJson deserializes all fields', () {
      final json = {
        'credential_id': 'cred-xyz',
        'public_key': 'pk-abc',
        'counter': 25,
        'user_id': 'user-99',
        'transports': ['ble', 'usb'],
        'created_at': '2024-02-01T08:00:00.000Z',
        'last_used_at': '2024-02-10T14:30:00.000Z',
        'name': 'Security Key',
      };

      final authenticator = WebAuthnAuthenticator.fromJson(json);

      expect(authenticator.credentialId, equals('cred-xyz'));
      expect(authenticator.publicKey, equals('pk-abc'));
      expect(authenticator.counter, equals(25));
      expect(authenticator.userId, equals('user-99'));
      expect(authenticator.transports, equals(['ble', 'usb']));
      expect(
        authenticator.createdAt,
        equals(DateTime.parse('2024-02-01T08:00:00.000Z')),
      );
      expect(
        authenticator.lastUsedAt,
        equals(DateTime.parse('2024-02-10T14:30:00.000Z')),
      );
      expect(authenticator.name, equals('Security Key'));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'credential_id': 'cred-minimal',
        'public_key': 'pk-minimal',
        'counter': 0,
      };

      final authenticator = WebAuthnAuthenticator.fromJson(json);

      expect(authenticator.credentialId, equals('cred-minimal'));
      expect(authenticator.userId, isNull);
      expect(authenticator.transports, isNull);
      expect(authenticator.createdAt, isNull);
      expect(authenticator.name, isNull);
    });
  });

  group('WebAuthnFormField', () {
    test('default values', () {
      const field = WebAuthnFormField();

      expect(field.label, isNull);
      expect(field.required, isFalse);
      expect(field.type, equals('text'));
      expect(field.autocomplete, isNull);
    });

    test('custom values', () {
      const field = WebAuthnFormField(
        label: 'Email Address',
        required: true,
        type: 'email',
        autocomplete: 'username webauthn',
      );

      expect(field.label, equals('Email Address'));
      expect(field.required, isTrue);
      expect(field.type, equals('email'));
      expect(field.autocomplete, equals('username webauthn'));
    });
  });

  group('WebAuthnRegistrationOptions', () {
    test('default values', () {
      const options = WebAuthnRegistrationOptions();

      expect(options.attestation, equals('none'));
      expect(options.authenticatorSelection, isNull);
      expect(options.excludeCredentials, isTrue);
    });

    test('custom values', () {
      const options = WebAuthnRegistrationOptions(
        attestation: 'direct',
        authenticatorSelection: WebAuthnAuthenticatorSelection(
          authenticatorAttachment: 'platform',
          residentKey: 'required',
          userVerification: 'required',
        ),
        excludeCredentials: false,
      );

      expect(options.attestation, equals('direct'));
      expect(
        options.authenticatorSelection?.authenticatorAttachment,
        equals('platform'),
      );
      expect(options.authenticatorSelection?.residentKey, equals('required'));
      expect(options.excludeCredentials, isFalse);
    });
  });

  group('WebAuthnAuthenticationOptions', () {
    test('default values', () {
      const options = WebAuthnAuthenticationOptions();

      expect(options.userVerification, equals('preferred'));
    });

    test('custom values', () {
      const options = WebAuthnAuthenticationOptions(
        userVerification: 'required',
      );

      expect(options.userVerification, equals('required'));
    });
  });

  group('WebAuthnAuthenticatorSelection', () {
    test('default values', () {
      const selection = WebAuthnAuthenticatorSelection();

      expect(selection.authenticatorAttachment, isNull);
      expect(selection.residentKey, equals('preferred'));
      expect(selection.userVerification, equals('preferred'));
    });

    test('platform authenticator selection', () {
      const selection = WebAuthnAuthenticatorSelection(
        authenticatorAttachment: 'platform',
        residentKey: 'required',
        userVerification: 'required',
      );

      expect(selection.authenticatorAttachment, equals('platform'));
      expect(selection.residentKey, equals('required'));
      expect(selection.userVerification, equals('required'));
    });

    test('cross-platform authenticator selection', () {
      const selection = WebAuthnAuthenticatorSelection(
        authenticatorAttachment: 'cross-platform',
        residentKey: 'discouraged',
        userVerification: 'discouraged',
      );

      expect(selection.authenticatorAttachment, equals('cross-platform'));
      expect(selection.residentKey, equals('discouraged'));
      expect(selection.userVerification, equals('discouraged'));
    });
  });

  group('WebAuthnUserInfo', () {
    test('stores user and existence status', () {
      final user = AuthUser(id: 'user-1', email: 'user@example.com');
      final info = WebAuthnUserInfo(user: user, exists: true);

      expect(info.user.id, equals('user-1'));
      expect(info.exists, isTrue);
    });

    test('new user has exists=false', () {
      final user = AuthUser(id: '', email: 'new@example.com');
      final info = WebAuthnUserInfo(user: user, exists: false);

      expect(info.exists, isFalse);
    });
  });
}

/// Minimal mock for EngineContext - tests don't need full context.
class _MockEngineContext implements EngineContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
