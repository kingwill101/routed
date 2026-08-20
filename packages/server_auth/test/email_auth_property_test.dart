import 'package:property_testing/property_testing.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

const _secret = 'email-auth-property-test-secret-key';

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: ${result.error}; '
    'input=${result.failingInput}; seed=${result.seed}';

void main() {
  test(
    'hostile email identifiers fail closed or canonicalize safely',
    () async {
      final values = Gen.frequency<String>([
        (7, Chaos.string(minLength: 0, maxLength: 700)),
        (
          3,
          Gen.oneOf<String>([
            'user@example.test',
            ' USER@EXAMPLE.TEST ',
            'user@example.test\r\nSet-Cookie: auth=stolen',
            'user\u0000@example.test',
            '<script>@example.test',
            "' OR '1'='1@example.test",
            '${'a' * 321}@example.test',
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(values, (input) {
        try {
          final normalized = normalizeAuthOneTimeEmail(input);
          expect(normalized, normalized.toLowerCase());
          expect(normalized, normalized.trim());
          expect(normalized.length, lessThanOrEqualTo(320));
          expect(normalized, matches(RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')));
          expect(normalized.codeUnits, everyElement(isNot(anyOf(0, 10, 13))));
        } on ArgumentError catch (error) {
          if (input.isNotEmpty) {
            expect(error.toString(), isNot(contains(input)));
          }
        }
      }, PropertyConfig(numTests: 1000, seed: 20260824));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test('hostile one-time values never cross persistence raw', () async {
    final values = Gen.frequency<String>([
      (7, Chaos.string(minLength: 0, maxLength: 512)),
      (
        3,
        Gen.oneOf<String>([
          '123456',
          '１２３４５６',
          '123456\u0000suffix',
          '123456\r\nAuthorization: Bearer leaked',
          '<script>alert(1)</script>',
          "' OR '1'='1",
          '9' * 4096,
        ]),
      ),
    ]);
    final runner = PropertyTestRunner<String>(values, (input) {
      try {
        final digest = digestAuthEmailOtpCode(code: input, secret: _secret);
        expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
        if (input.isNotEmpty) expect(digest, isNot(contains(input)));
        final record = AuthEmailOtp(
          id: 'property-otp',
          email: 'property@example.test',
          codeHash: digest,
          type: AuthEmailOtpType.signIn,
          createdAt: DateTime.utc(2030, 1, 1),
          expiresAt: DateTime.utc(2030, 1, 1, 0, 5),
          maxAttempts: 3,
        );
        expect(record.toStorageJson().values, isNot(contains(input)));
      } on ArgumentError catch (error) {
        if (input.isNotEmpty) expect(error.toString(), isNot(contains(input)));
      }
    }, PropertyConfig(numTests: 750, seed: 20260825));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test(
    'state machine preserves replacement, attempts, and one winner',
    () async {
      final operations = Gen.integer(
        min: -100000,
        max: 100000,
      ).list(minLength: 1, maxLength: 100);
      final runner = PropertyTestRunner<List<int>>(operations, (values) async {
        final store = InMemoryAuthStore();
        final now = DateTime.utc(2030, 1, 1);
        String? magicToken;
        String? otpCode;
        var otpAttempts = 0;
        var otpConsumed = false;
        var sequence = 0;
        for (final value in values) {
          switch (value.abs() % 6) {
            case 0:
              magicToken = 'magic-${sequence++}-${value.abs()}';
              await store.issueMagicLink(
                AuthMagicLinkIssueCommand(
                  AuthMagicLinkRecord(
                    providerId: 'email',
                    email: 'machine@example.test',
                    tokenHash: hashOpaqueToken(magicToken),
                    issuedAt: now,
                    expiresAt: now.add(const Duration(minutes: 5)),
                  ),
                ),
              );
            case 1:
              final expectedWinner = magicToken != null;
              final token = magicToken ?? 'missing';
              final result = await store.consumeMagicLink(
                AuthMagicLinkConsumeCommand(
                  providerId: 'email',
                  email: 'machine@example.test',
                  tokenHash: hashOpaqueToken(token),
                  now: now,
                  candidate: AuthUser(
                    id: 'machine-user',
                    email: 'machine@example.test',
                  ),
                ),
              );
              expect(
                result.status == AuthMagicLinkConsumeStatus.consumed,
                expectedWinner,
              );
              if (expectedWinner) magicToken = null;
            case 2:
              final result = await store.consumeMagicLink(
                AuthMagicLinkConsumeCommand(
                  providerId: 'email',
                  email: 'machine@example.test',
                  tokenHash: hashOpaqueToken('wrong-$value'),
                  now: now,
                  candidate: AuthUser(
                    id: 'machine-user',
                    email: 'machine@example.test',
                  ),
                ),
              );
              expect(result.status, AuthMagicLinkConsumeStatus.invalid);
            case 3:
              otpCode = '${100000 + value.abs() % 900000}';
              otpAttempts = 0;
              otpConsumed = false;
              await store.issueEmailOtp(
                AuthEmailOtpIssueCommand(
                  AuthEmailOtp(
                    id: 'machine-otp-${sequence++}',
                    email: 'machine@example.test',
                    codeHash: digestAuthEmailOtpCode(
                      code: otpCode,
                      secret: _secret,
                    ),
                    type: AuthEmailOtpType.signIn,
                    createdAt: now,
                    expiresAt: now.add(const Duration(minutes: 5)),
                    maxAttempts: 3,
                  ),
                ),
              );
            case 4:
              final expectedWinner =
                  otpCode != null && !otpConsumed && otpAttempts < 3;
              final result = await store.verifyEmailOtp(
                AuthEmailOtpVerifyCommand(
                  email: 'machine@example.test',
                  type: AuthEmailOtpType.signIn,
                  codeHash: digestAuthEmailOtpCode(
                    code: otpCode ?? '000000',
                    secret: _secret,
                  ),
                  now: now,
                ),
              );
              expect(
                result.status == AuthEmailOtpVerificationStatus.verified,
                expectedWinner,
              );
              if (expectedWinner) {
                otpConsumed = true;
                otpAttempts++;
              }
            case 5:
              final result = await store.verifyEmailOtp(
                AuthEmailOtpVerifyCommand(
                  email: 'machine@example.test',
                  type: AuthEmailOtpType.signIn,
                  codeHash: digestAuthEmailOtpCode(
                    code: 'wrong-${value.abs()}',
                    secret: _secret,
                  ),
                  now: now,
                ),
              );
              if (otpCode == null || otpConsumed) {
                expect(result.status, AuthEmailOtpVerificationStatus.invalid);
              } else if (otpAttempts >= 2) {
                expect(
                  result.status,
                  AuthEmailOtpVerificationStatus.tooManyAttempts,
                );
                otpAttempts = 3;
              } else {
                expect(result.status, AuthEmailOtpVerificationStatus.invalid);
                otpAttempts++;
              }
          }
        }
      }, PropertyConfig(numTests: 400, seed: 20260826));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );
}
