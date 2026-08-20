import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('AuthStoreConformanceSuite', () {
    final suite = AuthStoreConformanceSuite.fromStoreFactory(
      createStore: InMemoryAuthStore.new,
    );

    for (final conformanceCase in suite.cases) {
      test(conformanceCase.description, () async {
        final result = await conformanceCase.run();
        expect(result.isSkipped, isFalse);
      });
    }

    test('publishes stable unique case identifiers', () {
      const expectedCaseIds = <String>[
        'users.create-find',
        'users.email-uniqueness',
        'users.email-update-atomicity',
        'users.create-or-find-contention',
        'credentials.registration-lookup',
        'credentials.registration-contention',
        'credentials.user-lookup',
        'accounts.uniqueness',
        'accounts.link-contention',
        'accounts.safe-unlink',
        'sessions.rotation',
        'sessions.rotation-contention',
        'sessions.revocation',
        'tokens.verification-single-use',
        'tokens.verification-replay-contention',
        'tokens.password-reset-single-use',
        'tokens.password-reset-replay-contention',
        'oauth.challenge-replay-contention',
        'jwt.version-rotation',
        'jwt.version-rotation-contention',
        'device-authorization.approve-claim-contention',
        'email-otp.verification-contention',
        'account-deletion.transaction',
      ];
      final caseIds = suite.cases.map((conformanceCase) => conformanceCase.id);

      expect(caseIds, orderedEquals(expectedCaseIds));
      expect(caseIds.toSet(), hasLength(expectedCaseIds.length));
    });

    test(
      'does not require optional mutation or deletion capabilities',
      () async {
        final coreOnlySuite = AuthStoreConformanceSuite.fromStoreFactory(
          createStore: () => _CoreOnlyAuthStore(InMemoryAuthStore()),
        );

        final results = await Future.wait(
          coreOnlySuite.cases.map((conformanceCase) => conformanceCase.run()),
        );
        final skipped = <String, String>{
          for (var index = 0; index < results.length; index++)
            if (results[index].isSkipped)
              coreOnlySuite.cases[index].id: results[index].skippedReason!,
        };

        expect(
          skipped,
          equals({
            'accounts.safe-unlink':
                'Adapter does not expose authenticationMethodMutation.',
            'account-deletion.transaction':
                'Adapter does not expose accountDeletion.',
          }),
        );
      },
    );
  });
}

final class _CoreOnlyAuthStore implements AuthStore {
  _CoreOnlyAuthStore(this._delegate);

  final InMemoryAuthStore _delegate;

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
