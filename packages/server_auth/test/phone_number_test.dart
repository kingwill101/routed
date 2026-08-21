import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _hashKey = '0123456789abcdef0123456789abcdef';
final _now = DateTime.utc(2030, 1, 1);

void main() {
  group('AuthPhoneNumberBackend', () {
    test('rejects unbounded process-local challenge configuration', () {
      expect(
        () => InMemoryAuthStore(maxPhoneNumberVerifications: 0),
        throwsArgumentError,
      );
    });

    test('persists only a digest and binds issue replays to payload', () async {
      final backend = InMemoryAuthStore();
      final command = _issue(id: 'issue-1', digest: 'digest-secret');

      final first = await backend.issuePhoneNumberCode(command);
      final replay = await backend.issuePhoneNumberCode(command);
      final mismatch = await backend.issuePhoneNumberCode(
        _issue(id: 'issue-1', digest: 'different-digest'),
      );

      expect(first.status, AuthPhoneNumberIssueStatus.issued);
      expect(replay.status, AuthPhoneNumberIssueStatus.replayed);
      expect(mismatch.status, AuthPhoneNumberIssueStatus.replayMismatch);
      final storage = first.verification!.toStorageJson();
      expect(storage.keys, isNot(contains('code')));
      expect(storage.values, isNot(contains('123456')));
      expect(storage['code_digest'], 'digest-secret');
    });

    test('exactly one concurrent verifier consumes a challenge', () async {
      final backend = InMemoryAuthStore();
      await backend.issuePhoneNumberCode(_issue());
      final command = _verify(candidateId: 'user-1');

      final results = await Future.wait([
        backend.verifyPhoneNumberCode(command),
        backend.verifyPhoneNumberCode(command),
        backend.verifyPhoneNumberCode(command),
      ]);

      expect(
        results
            .where(
              (result) => result.status == AuthPhoneNumberVerifyStatus.verified,
            )
            .length,
        1,
      );
      expect(
        results
            .where(
              (result) => result.status == AuthPhoneNumberVerifyStatus.invalid,
            )
            .length,
        2,
      );
      expect(
        (await backend.findPhoneNumberIdentity('+18765551234'))!.userId,
        'user-1',
      );
    });

    test('wrong attempts lock the challenge at its bound', () async {
      final backend = InMemoryAuthStore();
      await backend.issuePhoneNumberCode(_issue(maxAttempts: 2));

      final first = await backend.verifyPhoneNumberCode(
        _verify(digest: 'wrong-1'),
      );
      final second = await backend.verifyPhoneNumberCode(
        _verify(digest: 'wrong-2'),
      );
      final correct = await backend.verifyPhoneNumberCode(_verify());

      expect(first.status, AuthPhoneNumberVerifyStatus.invalid);
      expect(second.status, AuthPhoneNumberVerifyStatus.tooManyAttempts);
      expect(second.verification!.attempts, 2);
      expect(second.verification!.lockedAt, _now);
      expect(correct.status, AuthPhoneNumberVerifyStatus.tooManyAttempts);
      expect(await backend.findPhoneNumberIdentity('+18765551234'), isNull);
    });

    test('expired challenges never consume or create users', () async {
      final backend = InMemoryAuthStore();
      await backend.issuePhoneNumberCode(
        _issue(expiresAt: _now.add(const Duration(minutes: 1))),
      );

      final result = await backend.verifyPhoneNumberCode(
        _verify(now: _now.add(const Duration(minutes: 1))),
      );

      expect(result.status, AuthPhoneNumberVerifyStatus.expired);
      expect(await backend.users.findById('user-1'), isNull);
    });

    test('phone ownership and verified projection commit together', () async {
      final backend = InMemoryAuthStore();
      await backend.issuePhoneNumberCode(_issue());

      final result = await backend.verifyPhoneNumberCode(
        _verify(candidateId: 'user-1'),
      );

      expect(result.status, AuthPhoneNumberVerifyStatus.verified);
      expect(result.identity!.phoneNumber, '+18765551234');
      expect(result.identity!.userId, result.user!.id);
      expect(result.user!.attributes, {
        'phoneNumber': '+18765551234',
        'phoneNumberVerified': true,
      });
      expect(
        await backend.findPhoneNumberIdentityForUser('user-1'),
        same(result.identity),
      );
    });

    test('issue faults restore the prior active challenge', () async {
      var armed = false;
      final backend = InMemoryAuthStore(
        phoneNumberFaultInjector: (point) {
          if (armed &&
              point ==
                  AuthPhoneNumberInMemoryFaultPoint.issueAfterChallengeWrite) {
            throw StateError('injected issue fault');
          }
        },
      );
      await backend.issuePhoneNumberCode(_issue(id: 'original'));
      armed = true;
      await expectLater(
        backend.issuePhoneNumberCode(
          _issue(id: 'replacement', digest: 'replacement'),
        ),
        throwsStateError,
      );
      armed = false;

      final original = await backend.verifyPhoneNumberCode(
        _verify(candidateId: 'user-1'),
      );
      expect(original.status, AuthPhoneNumberVerifyStatus.verified);
    });

    for (final point in <AuthPhoneNumberInMemoryFaultPoint>[
      AuthPhoneNumberInMemoryFaultPoint.verifyAfterChallengeConsumption,
      AuthPhoneNumberInMemoryFaultPoint.verifyAfterUserWrite,
      AuthPhoneNumberInMemoryFaultPoint.verifyAfterIdentityWrite,
      AuthPhoneNumberInMemoryFaultPoint.verifyAfterUserProjection,
    ]) {
      test('$point rolls back the complete verification mutation', () async {
        var armed = false;
        final backend = InMemoryAuthStore(
          phoneNumberFaultInjector: (current) {
            if (armed && current == point) {
              throw StateError('injected verification fault');
            }
          },
        );
        await backend.issuePhoneNumberCode(_issue());
        armed = true;
        await expectLater(
          backend.verifyPhoneNumberCode(_verify(candidateId: 'user-1')),
          throwsStateError,
        );
        armed = false;

        expect(await backend.users.findById('user-1'), isNull);
        expect(await backend.findPhoneNumberIdentity('+18765551234'), isNull);
        final retry = await backend.verifyPhoneNumberCode(
          _verify(candidateId: 'user-1'),
        );
        expect(retry.status, AuthPhoneNumberVerifyStatus.verified);
      });
    }

    test('attempt-write faults do not consume an attempt', () async {
      var armed = false;
      final backend = InMemoryAuthStore(
        phoneNumberFaultInjector: (point) {
          if (armed &&
              point ==
                  AuthPhoneNumberInMemoryFaultPoint.verifyAfterAttemptWrite) {
            throw StateError('injected attempt fault');
          }
        },
      );
      await backend.issuePhoneNumberCode(_issue(maxAttempts: 2));
      armed = true;
      await expectLater(
        backend.verifyPhoneNumberCode(_verify(digest: 'wrong')),
        throwsStateError,
      );
      armed = false;

      final firstCommittedFailure = await backend.verifyPhoneNumberCode(
        _verify(digest: 'wrong'),
      );
      expect(firstCommittedFailure.status, AuthPhoneNumberVerifyStatus.invalid);
      expect(firstCommittedFailure.verification!.attempts, 1);
      expect(
        (await backend.verifyPhoneNumberCode(
          _verify(candidateId: 'user-1'),
        )).status,
        AuthPhoneNumberVerifyStatus.verified,
      );
    });

    test(
      'deletion rollback cannot overwrite concurrent phone issuance',
      () async {
        final deletionEntered = Completer<void>();
        final releaseDeletion = Completer<void>();
        var watchIssuance = false;
        var issuanceEntered = false;
        final backend = InMemoryAuthStore(
          phoneNumberFaultInjector: (point) {
            if (watchIssuance &&
                point ==
                    AuthPhoneNumberInMemoryFaultPoint
                        .issueAfterChallengeWrite) {
              issuanceEntered = true;
            }
          },
          userDeletionFaultInjector: (point) async {
            if (point != AuthUserDeletionFaultPoint.beforeMutation) return;
            deletionEntered.complete();
            await releaseDeletion.future;
            throw StateError('injected deletion fault');
          },
        );
        backend.bindUserDeletionPlanContributors(const []);
        await backend.issuePhoneNumberCode(_issue());
        expect(
          (await backend.verifyPhoneNumberCode(
            _verify(candidateId: 'user-1'),
          )).status,
          AuthPhoneNumberVerifyStatus.verified,
        );

        final deletion = backend.userDeletionCoordinator.deleteUser('user-1');
        await deletionEntered.future;
        watchIssuance = true;
        final issuance = backend.issuePhoneNumberCode(
          _issue(id: 'replacement', digest: 'replacement'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(issuanceEntered, isFalse);

        releaseDeletion.complete();
        await expectLater(deletion, throwsStateError);
        expect((await issuance).status, AuthPhoneNumberIssueStatus.issued);
        expect(issuanceEntered, isTrue);
        expect(
          (await backend.verifyPhoneNumberCode(
            _verify(digest: 'replacement'),
          )).status,
          AuthPhoneNumberVerifyStatus.verified,
        );
      },
    );
  });

  group('PhoneNumberPlugin', () {
    test(
      'derives one bounded keyed limiter identifier from decoded requests',
      () {
        final plugin = PhoneNumberPlugin<Object>(
          sendCode: (_) {},
          codeHashKey: _hashKey,
        );
        final endpoints = <String, AuthEndpointRateLimitIdentifierDescriptor>{
          for (final endpoint in plugin.endpoints)
            endpoint.id: endpoint as AuthEndpointRateLimitIdentifierDescriptor,
        };
        final sendKey = endpoints['phoneNumber.sendCode']!
            .resolveRateLimitIdentifier(
              AuthEndpointRequest(
                body: const <String, dynamic>{'phoneNumber': ' +18765551234 '},
              ),
            );
        final verifyKey = endpoints['phoneNumber.verifyCode']!
            .resolveRateLimitIdentifier(
              AuthEndpointRequest(
                body: const <String, dynamic>{
                  'phoneNumber': '+18765551234',
                  'code': '123456',
                },
              ),
            );
        final otherCodeKey = endpoints['phoneNumber.verifyCode']!
            .resolveRateLimitIdentifier(
              AuthEndpointRequest(
                body: const <String, dynamic>{
                  'phoneNumber': '+18765551234',
                  'code': 'never-copy-this-otp',
                },
              ),
            );

        expect(sendKey, startsWith('phone:'));
        expect(sendKey, verifyKey);
        expect(verifyKey, otherCodeKey);
        expect(sendKey, hasLength(49));
        expect(sendKey!.length, lessThan(authRateLimitIdentifierMaximumLength));
        expect(sendKey, isNot(contains('+18765551234')));
        expect(sendKey, isNot(contains('123456')));
        expect(sendKey, isNot(contains('never-copy-this-otp')));
        expect(
          endpoints['phoneNumber.sendCode']!.resolveRateLimitIdentifier(
            AuthEndpointRequest(
              body: const <String, dynamic>{'phoneNumber': 'not-a-phone'},
            ),
          ),
          isNull,
        );
        expect(
          endpoints['phoneNumber.verifyCode']!.resolveRateLimitIdentifier(
            AuthEndpointRequest(
              body: const <String, dynamic>{'phoneNumber': '+18765551234'},
            ),
          ),
          isNull,
        );
      },
    );

    test('verification responses defer token projection to the host', () async {
      final intent = AuthPhoneNumberVerifyResponse(
        phoneNumber: '+18765551234',
        user: AuthUser(id: 'user-1'),
      ).toAuthenticationIntent();
      final response = await intent.projectResponse(
        AuthSession(
          user: AuthUser(id: 'user-1'),
          expiresAt: DateTime.utc(2030),
          strategy: AuthSessionStrategy.jwt,
          token: 'secret-jwt',
        ).toJson(),
      );

      expect(intent.authenticationMethod, authPhoneNumberAuthenticationMethod);
      expect((response as Map<String, dynamic>)['user'], isNotNull);
      expect(response, isNot(contains('token')));
      expect(response.toString(), isNot(contains('secret-jwt')));
    });

    test('requires a root backend and a production-strength digest key', () {
      expect(
        () => PhoneNumberPlugin<Object>(sendCode: (_) {}, codeHashKey: 'short'),
        throwsArgumentError,
      );
      final plugin = PhoneNumberPlugin<Object>(
        sendCode: (_) {},
        codeHashKey: _hashKey,
      );
      expect(
        () => AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const [],
            store: _StoreWithoutPhoneBackend(),
            runtimeMode: AuthRuntimeMode.localDevelopment,
            plugins: [plugin],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('AuthPhoneNumberBackend'),
          ),
        ),
      );
    });

    test('delivers raw code only after digest issuance commits', () async {
      final delivered = <AuthPhoneNumberCodeDelivery<Object>>[];
      final store = InMemoryAuthStore();
      final plugin = PhoneNumberPlugin<Object>(
        sendCode: delivered.add,
        codeHashKey: _hashKey,
        generateCode: (_) => '123456',
      );
      _runtime(plugin, store);

      await plugin.issueCode(
        context: Object(),
        phoneNumber: ' +18765551234 ',
        now: _now,
      );

      expect(delivered.single.code, '123456');
      final replay = await store.verifyPhoneNumberCode(
        AuthPhoneNumberVerifyCodeCommand(
          phoneNumber: '+18765551234',
          codeDigest: _digest('+18765551234', '123456'),
          now: _now,
        ),
      );
      expect(replay.status, AuthPhoneNumberVerifyStatus.userNotFound);
    });

    test(
      'SMS failure is explicit postcommit state, not compensation',
      () async {
        final store = InMemoryAuthStore();
        final plugin = PhoneNumberPlugin<Object>(
          sendCode: (_) => throw StateError('SMS unavailable'),
          codeHashKey: _hashKey,
          allowSignUp: true,
          generateCode: (_) => '123456',
        );
        _runtime(plugin, store);

        await expectLater(
          plugin.issueCode(
            context: Object(),
            phoneNumber: '+18765551234',
            now: _now,
          ),
          throwsStateError,
        );
        final verified = await plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '123456',
          now: _now,
        );
        expect(verified.user.attributes['phoneNumberVerified'], isTrue);
      },
    );

    test('signs up once and rejects OTP replay', () async {
      final store = InMemoryAuthStore();
      final plugin = PhoneNumberPlugin<Object>(
        sendCode: (_) {},
        codeHashKey: _hashKey,
        allowSignUp: true,
        generateCode: (_) => '123456',
      );
      final runtime = _runtime(plugin, store);
      await plugin.issueCode(
        context: Object(),
        phoneNumber: '+18765551234',
        now: _now,
      );

      final result = await plugin.verifyCode(
        context: Object(),
        phoneNumber: '+18765551234',
        code: '123456',
        name: 'Ada',
        now: _now,
      );

      expect(result.user.name, 'Ada');
      expect(result.user.attributes['phoneNumber'], '+18765551234');
      expect(runtime.hasPlugin(authPhoneNumberPluginId), isTrue);
      await expectLater(
        plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '123456',
          now: _now,
        ),
        _flow('invalid_phone_code'),
      );
    });

    test('new issuance supersedes an earlier code', () async {
      final codes = <String>['111111', '222222'];
      final plugin = PhoneNumberPlugin<Object>(
        sendCode: (_) {},
        codeHashKey: _hashKey,
        generateCode: (_) => codes.removeAt(0),
      );
      _runtime(plugin, InMemoryAuthStore());

      await plugin.issueCode(
        context: Object(),
        phoneNumber: '+18765551234',
        now: _now,
      );
      await plugin.issueCode(
        context: Object(),
        phoneNumber: '+18765551234',
        now: _now.add(const Duration(seconds: 1)),
      );
      await expectLater(
        plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '111111',
          now: _now.add(const Duration(seconds: 2)),
        ),
        _flow('invalid_phone_code'),
      );
      await expectLater(
        plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '222222',
          now: _now.add(const Duration(seconds: 2)),
        ),
        _flow('user_not_found'),
      );
    });

    test(
      'hard deletion scrubs phone identity, challenge, and receipt',
      () async {
        final store = InMemoryAuthStore();
        final plugin = PhoneNumberPlugin<Object>(
          sendCode: (_) {},
          codeHashKey: _hashKey,
          allowSignUp: true,
          generateCode: (_) => '123456',
          createUser: (_, _, _) => AuthUser(id: 'user-1'),
        );
        _runtime(plugin, store);
        await plugin.issueCode(
          context: Object(),
          phoneNumber: '+18765551234',
          now: _now,
        );
        await plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '123456',
          now: _now,
        );
        await plugin.issueCode(
          context: Object(),
          phoneNumber: '+18765551234',
          now: _now.add(const Duration(seconds: 1)),
        );

        expect(
          await store.userDeletionCoordinator.deleteUser('user-1'),
          isTrue,
        );
        expect(await store.findPhoneNumberIdentity('+18765551234'), isNull);
        expect(
          (await store.verifyPhoneNumberCode(
            AuthPhoneNumberVerifyCodeCommand(
              phoneNumber: '+18765551234',
              codeDigest: _digest('+18765551234', '123456'),
              now: _now.add(const Duration(seconds: 2)),
            ),
          )).status,
          AuthPhoneNumberVerifyStatus.invalid,
        );
        expect(
          () => store.users.create(AuthUser(id: 'user-1')),
          throwsStateError,
        );
      },
    );

    test(
      'removes a phone identity only when a usable fallback remains',
      () async {
        final store = InMemoryAuthStore();
        final plugin = PhoneNumberPlugin<Object>(
          sendCode: (_) {},
          codeHashKey: _hashKey,
          allowSignUp: true,
          generateCode: (_) => '123456',
          createUser: (_, _, _) => AuthUser(id: 'user-1'),
        );
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: <AuthProvider>[CredentialsProvider()],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: <AuthServerPlugin<Object>>[plugin],
          ),
        );
        await plugin.issueCode(
          context: Object(),
          phoneNumber: '+18765551234',
          now: _now,
        );
        await plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '123456',
          now: _now,
        );

        await expectLater(
          plugin.removePhoneNumber(userId: 'user-1'),
          _flow('last_authentication_method'),
        );

        await store.upsertCredentialForAdministration(
          AuthPasswordCredential(
            id: 'password-1',
            userId: 'user-1',
            identifier: 'user-1@example.com',
            passwordHash: 'encoded-hash',
            createdAt: _now,
            updatedAt: _now,
          ),
        );
        await plugin.removePhoneNumber(userId: 'user-1');

        expect(await store.findPhoneNumberIdentity('+18765551234'), isNull);
        final user = await store.users.findById('user-1');
        expect(user!.attributes, isNot(contains('phoneNumber')));
        expect(user.attributes, isNot(contains('phoneNumberVerified')));
        final staleVerification = await store.verifyPhoneNumberCode(
          _verify(now: _now.add(const Duration(seconds: 1))),
        );
        expect(staleVerification.status, AuthPhoneNumberVerifyStatus.invalid);
      },
    );

    test('endpoint metadata advertises backend-atomic commands', () {
      final plugin = PhoneNumberPlugin<Object>(
        sendCode: (_) {},
        codeHashKey: _hashKey,
      );
      final endpoints = {
        for (final endpoint in plugin.endpoints) endpoint.id: endpoint,
      };

      for (final endpoint in endpoints.values) {
        final semantics = endpoint.semantics as AuthMutationOperationSemantics;
        expect(semantics.persistence.atomicity, AuthMutationAtomicity.atomic);
        expect(
          semantics.persistence.reference?.schemaId,
          authPhoneNumberPluginId,
        );
      }
      expect(endpoints['phoneNumber.issueCode'], isNull);
      expect(
        (endpoints['phoneNumber.sendCode']!.semantics
                as AuthMutationOperationSemantics)
            .persistence
            .reference
            ?.atomicOperationId,
        'phoneNumber.issueCode',
      );
      expect(
        (endpoints['phoneNumber.verifyCode']!.semantics
                as AuthMutationOperationSemantics)
            .persistence
            .reference
            ?.atomicOperationId,
        'phoneNumber.verifyCode',
      );
      expect(
        (endpoints['phoneNumber.remove']! as AuthEndpointSecurityDescriptor)
            .requiresRecentAuthentication,
        isTrue,
      );
      expect(
        (endpoints['phoneNumber.remove']!.semantics
                as AuthMutationOperationSemantics)
            .persistence
            .reference
            ?.atomicOperationId,
        'phoneNumber.remove',
      );
    });
  });
}

AuthRuntime<Object> _runtime(
  PhoneNumberPlugin<Object> plugin,
  InMemoryAuthStore store,
) => AuthRuntime<Object>(
  options: AuthOptions<Object>(
    providers: const <AuthProvider>[],
    store: store,
    storeMode: AuthStoreMode.ephemeral,
    plugins: <AuthServerPlugin<Object>>[plugin],
  ),
);

AuthPhoneNumberIssueCodeCommand _issue({
  String id = 'issue-1',
  String digest = 'digest-1',
  int maxAttempts = 3,
  DateTime? expiresAt,
}) => AuthPhoneNumberIssueCodeCommand(
  verification: AuthPhoneNumberVerification(
    id: id,
    phoneNumber: '+18765551234',
    codeDigest: digest,
    createdAt: _now,
    expiresAt: expiresAt ?? _now.add(const Duration(minutes: 5)),
    maxAttempts: maxAttempts,
  ),
);

AuthPhoneNumberVerifyCodeCommand _verify({
  String digest = 'digest-1',
  String? candidateId,
  DateTime? now,
}) => AuthPhoneNumberVerifyCodeCommand(
  phoneNumber: '+18765551234',
  codeDigest: digest,
  now: now ?? _now,
  candidateUser: candidateId == null ? null : AuthUser(id: candidateId),
);

String _digest(String phoneNumber, String code) {
  // This mirrors the public plugin's HMAC input only to inspect postcommit
  // state through the backend command API in a focused test.
  final key = utf8.encode(_hashKey);
  return base64UrlNoPadding(
    Hmac(sha256, key).convert(utf8.encode('$phoneNumber\u0000$code')).bytes,
  );
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);

final class _StoreWithoutPhoneBackend implements AuthStore {
  final InMemoryAuthStore _delegate = InMemoryAuthStore();

  @override
  AuthAccountStore get accounts => _delegate.accounts;

  @override
  AuthCredentialStore get credentials => _delegate.credentials;

  @override
  AuthDeviceAuthorizationStore get deviceAuthorizations =>
      _delegate.deviceAuthorizations;

  @override
  AuthEmailChangeTokenStore get emailChangeTokens =>
      _delegate.emailChangeTokens;

  @override
  AuthEmailOtpStore get emailOtps => _delegate.emailOtps;

  @override
  AuthJwtVersionStore get jwtVersions => _delegate.jwtVersions;

  @override
  AuthOAuthChallengeStore get oauthChallenges => _delegate.oauthChallenges;

  @override
  AuthPasswordResetTokenStore get passwordResetTokens =>
      _delegate.passwordResetTokens;

  @override
  AuthSessionStore get sessions => _delegate.sessions;

  @override
  AuthUserStore get users => _delegate.users;

  @override
  AuthVerificationTokenStore get verificationTokens =>
      _delegate.verificationTokens;
}
