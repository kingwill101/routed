import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/saml_xmldsig_fixture.dart';

void main() {
  group('AuthPortableSamlXmlDsigVerifier properties', () {
    final verifier = AuthPortableSamlXmlDsigVerifier();

    test('arbitrary signed attribute values invalidate the digest', () async {
      final safeText = Gen.integer(min: 0, max: _safeCharacters.length - 1)
          .list(minLength: 0, maxLength: 160)
          .map(
            (values) => values.map((value) => _safeCharacters[value]).join(),
          );
      final runner = PropertyTestRunner<String>(safeText, (candidate) {
        final value = candidate == 'signed@example.test'
            ? '$candidate!'
            : candidate;
        final xml = mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
          document.descendantElements
                  .singleWhere(
                    (element) => element.name.local == 'AttributeValue',
                  )
                  .innerText =
              value;
        });
        _requireRejected(verifier, samlXmlDsigInput(xml));
      }, PropertyConfig(numTests: 750, seed: 20260828));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    });

    test('arbitrary reference URIs never become implicit lookups', () async {
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 0, maxLength: 512),
        (candidate) {
          final expected = '#$samlXmlDsigAssertionId';
          final uri = candidate == expected ? '$candidate-attacker' : candidate;
          final xml = mutateSamlXmlDsig(
            samlXmlDsigSignedAssertion,
            (document) => samlXmlDsigElement(
              document,
              'Reference',
            ).setAttribute('URI', uri),
          );
          _requireRejected(verifier, samlXmlDsigInput(xml));
        },
        PropertyConfig(numTests: 750, seed: 20260829),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    });

    test('arbitrary algorithm identifiers fail the allowlist', () async {
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 0, maxLength: 512),
        (candidate) {
          final expected = AuthSamlXmlDsigSignatureAlgorithm.rsaSha256.uri;
          final algorithm = candidate == expected
              ? '$candidate-attacker'
              : candidate;
          final xml = mutateSamlXmlDsig(
            samlXmlDsigSignedAssertion,
            (document) => samlXmlDsigElement(
              document,
              'SignatureMethod',
            ).setAttribute('Algorithm', algorithm),
          );
          _requireRejected(verifier, samlXmlDsigInput(xml));
        },
        PropertyConfig(numTests: 750, seed: 20260830),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    });

    test('all additive wrapping and confusion combinations fail', () async {
      final runner = PropertyTestRunner<int>(Gen.integer(min: 1, max: 0x7f), (
        mask,
      ) {
        final xml = mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
          final assertion = document.descendantElements.singleWhere(
            (element) => element.name.local == 'Assertion',
          );
          final signature = samlXmlDsigElement(document, 'Signature');
          final signedInfo = samlXmlDsigElement(document, 'SignedInfo');
          final reference = samlXmlDsigElement(document, 'Reference');
          final transforms = samlXmlDsigElement(document, 'Transforms');
          final digestMethod = samlXmlDsigElement(document, 'DigestMethod');
          final digestValue = samlXmlDsigElement(document, 'DigestValue');
          if (mask & 0x01 != 0) {
            document.rootElement.children.add(
              assertion.copy()..setAttribute('ID', '_wrapped-$mask'),
            );
          }
          if (mask & 0x02 != 0) {
            assertion.setAttribute('Id', '_alias-$mask');
          }
          if (mask & 0x04 != 0) {
            assertion.children.add(signature.copy());
          }
          if (mask & 0x08 != 0) {
            signedInfo.children.add(reference.copy());
          }
          if (mask & 0x10 != 0) {
            transforms.children.add(transforms.childElements.last.copy());
          }
          if (mask & 0x20 != 0) {
            digestValue.children.add(digestMethod.copy());
          }
          if (mask & 0x40 != 0) {
            document.rootElement.children.add(signature.copy());
          }
        });
        _requireRejected(verifier, samlXmlDsigInput(xml));
      }, PropertyConfig(numTests: 512, seed: 20260831));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    });

    test(
      'arbitrary signature, digest, and certificate bit flips fail',
      () async {
        final runner = PropertyTestRunner<int>(
          Gen.integer(min: 0, max: 0x7fffffff),
          (seed) {
            final xml = mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (
              document,
            ) {
              final names = [
                'SignatureValue',
                'DigestValue',
                'X509Certificate',
              ];
              final element = samlXmlDsigElement(
                document,
                names[seed % names.length],
              );
              final compact = element.innerText.replaceAll(RegExp(r'\s'), '');
              final index = (seed ~/ names.length) % compact.length;
              final replacement = compact[index] == 'A' ? 'B' : 'A';
              element.innerText = compact.replaceRange(
                index,
                index + 1,
                replacement,
              );
            });
            _requireRejected(verifier, samlXmlDsigInput(xml));
          },
          PropertyConfig(numTests: 1000, seed: 20260901),
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );
  });
}

const _safeCharacters =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._- ';

void _requireRejected(
  AuthPortableSamlXmlDsigVerifier verifier,
  AuthSamlVerificationInput input,
) {
  var rejected = false;
  try {
    verifier.verify(input);
  } on AuthSamlXmlDsigVerificationException {
    rejected = true;
  }
  if (!rejected) fail('Hostile XMLDSig input was accepted.');
}

String _propertyReport(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return [
    'Property failed after ${result.numTests} cases',
    'Original input: ${result.originalFailingInput}',
    'Shrunk input: ${result.failingInput}',
    'Shrinks: ${result.numShrinks}',
    'Error: ${result.error}',
    'Seed: ${result.seed}',
  ].join('\n');
}
