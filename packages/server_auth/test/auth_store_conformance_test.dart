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

    test(
      'does not require optional WebAuthn or deletion capabilities',
      () async {
        final coreOnlySuite = AuthStoreConformanceSuite.fromStoreFactory(
          createStore: () => _CoreOnlyAuthStore(InMemoryAuthStore()),
        );

        final results = await Future.wait(
          coreOnlySuite.cases.map((conformanceCase) => conformanceCase.run()),
        );
        final skipped = <AuthStoreConformanceCapability>[
          for (var index = 0; index < results.length; index++)
            if (results[index].isSkipped)
              coreOnlySuite.cases[index].optionalCapability!,
        ];

        expect(
          skipped,
          equals([AuthStoreConformanceCapability.accountDeletion]),
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
