import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: '
    '${result.error ?? 'unknown failure'}; input=${result.failingInput}; '
    'seed=${result.seed}';

void main() {
  test(
    'hostile operation identifiers never cross persistence unsanitized',
    () async {
      final generator = Gen.frequency<String>([
        (7, Chaos.string(minLength: 0, maxLength: 400)),
        (
          3,
          Gen.oneOf<String>([
            '',
            ' ',
            '\toperation',
            'operation\n',
            'operation\u0000suffix',
            'x' * 257,
            '<script>alert(1)</script>',
            '../../anonymous',
            '正常な識別子',
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(generator, (input) {
        try {
          final normalized = validateAuthAnonymousOperationId(input);
          expect(normalized, input);
          expect(normalized, isNotEmpty);
          expect(normalized.length, lessThanOrEqualTo(256));
          expect(normalized.trim(), normalized);
          expect(
            normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f),
            isFalse,
          );
        } on ArgumentError {
          expect(
            input.isEmpty ||
                input.trim() != input ||
                input.length > 256 ||
                input.runes.any((rune) => rune < 0x20 || rune == 0x7f),
            isTrue,
          );
        }
      }, PropertyConfig(numTests: 1500, seed: 20260820));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test('generated display names are bounded and control-free', () async {
    final generator = Gen.frequency<String>([
      (8, Chaos.string(minLength: 0, maxLength: 260)),
      (
        2,
        Gen.oneOf<String>([
          '',
          '   ',
          'Guest\u0000Admin',
          'Guest\nAdmin',
          '<script>alert(1)</script>',
          '訪問者',
          'x' * 129,
        ]),
      ),
    ]);
    final runner = PropertyTestRunner<String>(generator, (input) {
      try {
        final normalized = normalizeAuthAnonymousDisplayName(input);
        if (normalized == null) {
          expect(input.trim(), isEmpty);
          return;
        }
        expect(normalized, input.trim());
        expect(normalized.length, lessThanOrEqualTo(128));
        expect(
          normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f),
          isFalse,
        );
      } on ArgumentError {
        final trimmed = input.trim();
        expect(
          trimmed.length > 128 ||
              trimmed.runes.any((rune) => rune < 0x20 || rune == 0x7f),
          isTrue,
        );
      }
    }, PropertyConfig(numTests: 1500, seed: 20260821));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test('anonymous create commands reject privilege-bearing users', () {
    for (final user in <AuthUser>[
      AuthUser(id: 'email-user', email: 'guest@example.com', isAnonymous: true),
      AuthUser(id: 'role-user', roles: const ['admin'], isAnonymous: true),
      AuthUser(
        id: 'attribute-user',
        attributes: const <String, dynamic>{'trusted': true},
        isAnonymous: true,
      ),
      AuthUser(
        id: 'image-user',
        image: 'https://example.com/a.png',
        isAnonymous: true,
      ),
      AuthUser(id: 'regular-user'),
    ]) {
      expect(
        () => AuthAnonymousCreateAccountCommand(
          operationId: 'operation-${user.id}',
          user: user,
        ),
        throwsArgumentError,
      );
    }
  });
}
