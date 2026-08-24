import 'package:server_auth/testing.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/saml_xmldsig_fixture.dart';

void main() {
  group('AuthPortableSamlXmlDsigVerifier', () {
    late AuthPortableSamlXmlDsigVerifier verifier;

    setUp(() {
      verifier = AuthPortableSamlXmlDsigVerifier();
    });

    test('verifies an independent xmlsec1 RSA-SHA256 assertion fixture', () {
      final proof = verifier.verify(
        samlXmlDsigInput(samlXmlDsigSignedAssertion),
      );

      expect(proof.signedResponseId, isNull);
      expect(proof.signedAssertionId, samlXmlDsigAssertionId);
      expect(
        proof.signatureAlgorithm,
        AuthSamlXmlDsigSignatureAlgorithm.rsaSha256.uri,
      );
      expect(proof.digestAlgorithm, AuthSamlXmlDsigDigestAlgorithm.sha256.uri);
      expect(
        proof.canonicalizationAlgorithm,
        AuthPortableSamlXmlDsigVerifier.exclusiveCanonicalizationAlgorithm,
      );
    });

    test('preserves verification after namespace-safe DOM serialization', () {
      final serialized = XmlDocument.parse(
        samlXmlDsigSignedAssertion,
      ).toXmlString();

      expect(
        verifier.verify(samlXmlDsigInput(serialized)).signedAssertionId,
        samlXmlDsigAssertionId,
      );
    });

    test('binds a valid signature to the exact response parent', () {
      final xml = signSamlXmlDsigFixture(
        target: SamlXmlDsigSignedTarget.response,
      );

      final proof = verifier.verify(samlXmlDsigInput(xml));
      expect(proof.signedResponseId, samlXmlDsigResponseId);
      expect(proof.signedAssertionId, isNull);
    });

    test('uses the pin when KeyInfo is omitted', () {
      final xml = signSamlXmlDsigFixture(includeKeyInfo: false);

      expect(
        verifier.verify(samlXmlDsigInput(xml)).signedAssertionId,
        samlXmlDsigAssertionId,
      );
    });

    test('never trusts an embedded certificate over the selected pin', () {
      final wrongPin = samlXmlDsigFixture('wrong-idp-cert.pem');

      _expectRejected(
        verifier,
        samlXmlDsigInput(
          samlXmlDsigSignedAssertion,
          connection: samlXmlDsigConnection(certificate: wrongPin),
        ),
      );
    });

    test('requires one bounded pinned certificate, not a PEM chain', () {
      _expectRejected(
        verifier,
        samlXmlDsigInput(
          samlXmlDsigSignedAssertion,
          connection: samlXmlDsigConnection(
            certificate:
                '$samlXmlDsigCertificatePem\n$samlXmlDsigCertificatePem',
          ),
        ),
      );
    });

    test('requires explicit opt-in for every non-default algorithm', () {
      for (final vector
          in <
            (AuthSamlXmlDsigSignatureAlgorithm, AuthSamlXmlDsigDigestAlgorithm)
          >[
            (
              AuthSamlXmlDsigSignatureAlgorithm.rsaSha384,
              AuthSamlXmlDsigDigestAlgorithm.sha384,
            ),
            (
              AuthSamlXmlDsigSignatureAlgorithm.rsaSha512,
              AuthSamlXmlDsigDigestAlgorithm.sha512,
            ),
          ]) {
        final xml = signSamlXmlDsigFixture(
          signatureAlgorithm: vector.$1,
          digestAlgorithm: vector.$2,
        );
        _expectRejected(verifier, samlXmlDsigInput(xml));

        final optedIn = AuthPortableSamlXmlDsigVerifier(
          policy: AuthSamlXmlDsigPolicy(
            signatureAlgorithms: {vector.$1},
            digestAlgorithms: {vector.$2},
          ),
        );
        final proof = optedIn.verify(samlXmlDsigInput(xml));
        expect(proof.signatureAlgorithm, vector.$1.uri);
        expect(proof.digestAlgorithm, vector.$2.uri);
      }
    });

    test('rejects invalid and unbounded policy construction', () {
      expect(
        () => AuthSamlXmlDsigPolicy(signatureAlgorithms: const {}),
        throwsArgumentError,
      );
      expect(
        () => AuthSamlXmlDsigPolicy(digestAlgorithms: const {}),
        throwsArgumentError,
      );
      expect(
        () => AuthSamlXmlDsigPolicy(maxSignatures: 3),
        throwsArgumentError,
      );
    });

    test('returns one stable non-diagnostic failure', () {
      expect(
        () => verifier.verify(samlXmlDsigInput('<not-saml/>')),
        throwsA(
          isA<AuthSamlXmlDsigVerificationException>().having(
            (error) => error.toString(),
            'toString',
            'AuthSamlXmlDsigVerificationException()',
          ),
        ),
      );
    });

    test('passes public conformance with hostile XMLDSig vectors', () async {
      final valid = samlXmlDsigInput(samlXmlDsigSignedAssertion);
      final hostile = <String, AuthSamlVerificationInput>{
        'modified-signed-content': samlXmlDsigInput(
          samlXmlDsigSignedAssertion.replaceFirst(
            'signed@example.test',
            'attacker@example.test',
          ),
        ),
        'wrapping-extra-assertion': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final assertion = _samlAssertion(document);
            final wrapped = assertion.copy()
              ..setAttribute('ID', '_unsigned-wrapper');
            document.rootElement.children.add(wrapped);
          }),
        ),
        'duplicate-id': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            document.rootElement.setAttribute('Id', samlXmlDsigAssertionId);
          }),
        ),
        'id-alias': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            _samlAssertion(document).setAttribute('Id', '_alias');
          }),
        ),
        'reference-substitution': samlXmlDsigInput(
          _setAttribute(
            samlXmlDsigSignedAssertion,
            'Reference',
            'URI',
            '#$samlXmlDsigResponseId',
          ),
        ),
        'external-reference': samlXmlDsigInput(
          _setAttribute(
            samlXmlDsigSignedAssertion,
            'Reference',
            'URI',
            'https://attacker.example/signed.xml',
          ),
        ),
        'empty-reference': samlXmlDsigInput(
          _setAttribute(samlXmlDsigSignedAssertion, 'Reference', 'URI', ''),
        ),
        'multiple-references': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final signedInfo = samlXmlDsigElement(document, 'SignedInfo');
            signedInfo.children.add(
              samlXmlDsigElement(document, 'Reference').copy(),
            );
          }),
        ),
        'xpath-transform': samlXmlDsigInput(
          _setFirstTransform(
            samlXmlDsigSignedAssertion,
            'http://www.w3.org/TR/1999/REC-xpath-19991116',
          ),
        ),
        'reordered-transforms': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final transforms = samlXmlDsigElement(document, 'Transforms');
            final elements = transforms.childElements.toList();
            transforms.children
              ..remove(elements[0])
              ..add(elements[0]);
          }),
        ),
        'implicit-transform': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final transforms = samlXmlDsigElement(document, 'Transforms');
            transforms.children.remove(transforms.childElements.last);
          }),
        ),
        'sha1-signature': samlXmlDsigInput(
          _setAlgorithm(
            samlXmlDsigSignedAssertion,
            'SignatureMethod',
            'http://www.w3.org/2000/09/xmldsig#rsa-sha1',
          ),
        ),
        'sha1-digest': samlXmlDsigInput(
          _setAlgorithm(
            samlXmlDsigSignedAssertion,
            'DigestMethod',
            'http://www.w3.org/2000/09/xmldsig#sha1',
          ),
        ),
        'comments-canonicalization': samlXmlDsigInput(
          _setAlgorithm(
            samlXmlDsigSignedAssertion,
            'CanonicalizationMethod',
            'http://www.w3.org/2001/10/xml-exc-c14n#WithComments',
          ),
        ),
        'inclusive-prefix-list': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final method = samlXmlDsigElement(
              document,
              'CanonicalizationMethod',
            );
            method.children.add(
              XmlDocument.parse(
                '<ec:InclusiveNamespaces '
                'xmlns:ec="http://www.w3.org/2001/10/xml-exc-c14n#" '
                'PrefixList="saml samlp"/>',
              ).rootElement.copy(),
            );
          }),
        ),
        'moved-signature': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final signature = samlXmlDsigElement(document, 'Signature');
            signature.parent!.children.remove(signature);
            document.rootElement.children.add(signature);
          }),
        ),
        'duplicate-signature': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final assertion = _samlAssertion(document);
            assertion.children.add(
              samlXmlDsigElement(document, 'Signature').copy(),
            );
          }),
        ),
        'embedded-certificate-substitution': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final certificate = samlXmlDsigElement(document, 'X509Certificate');
            final compact = certificate.innerText.replaceAll(RegExp(r'\s'), '');
            certificate.innerText =
                '${compact[0] == 'A' ? 'B' : 'A'}'
                '${compact.substring(1)}';
          }),
        ),
        'key-value-confusion': samlXmlDsigInput(
          mutateSamlXmlDsig(samlXmlDsigSignedAssertion, (document) {
            final keyInfo = samlXmlDsigElement(document, 'KeyInfo');
            keyInfo.children.add(
              XmlDocument.parse(
                '<ds:KeyValue '
                'xmlns:ds="http://www.w3.org/2000/09/xmldsig#"/>',
              ).rootElement.copy(),
            );
          }),
        ),
        'doctype-entity': samlXmlDsigInput(
          samlXmlDsigSignedAssertion.replaceFirst(
            '<samlp:Response',
            '<!DOCTYPE samlp:Response [<!ENTITY injected "x">]>\n'
                '<samlp:Response',
          ),
        ),
        'xml-1.1': samlXmlDsigInput(
          samlXmlDsigSignedAssertion.replaceFirst(
            '<?xml version="1.0"?>',
            '<?xml version="1.1"?>',
          ),
        ),
        'foreign-signature-namespace': samlXmlDsigInput(
          samlXmlDsigSignedAssertion.replaceFirst(
            '<saml:Subject>',
            '<Signature xmlns="urn:attacker"/><saml:Subject>',
          ),
        ),
      };

      await AuthSamlVerifierConformanceSuite(
        verifier: verifier,
        vector: AuthSamlVerifierConformanceVector(
          valid: valid,
          hostile: hostile,
        ),
      ).run();
    });

    test('enforces verifier-local XML bounds before cryptography', () {
      final bounded = AuthPortableSamlXmlDsigVerifier(
        limits: const AuthSamlLimits(maxDecodedXmlBytes: 128),
      );

      _expectRejected(bounded, samlXmlDsigInput(samlXmlDsigSignedAssertion));
    });
  });
}

void _expectRejected(
  AuthPortableSamlXmlDsigVerifier verifier,
  AuthSamlVerificationInput input,
) {
  expect(
    () => verifier.verify(input),
    throwsA(isA<AuthSamlXmlDsigVerificationException>()),
  );
}

XmlElement _samlAssertion(XmlDocument document) =>
    document.descendantElements.singleWhere(
      (element) =>
          element.name.local == 'Assertion' &&
          element.name.namespaceUri == 'urn:oasis:names:tc:SAML:2.0:assertion',
    );

String _setAttribute(
  String source,
  String element,
  String attribute,
  String value,
) => mutateSamlXmlDsig(source, (document) {
  samlXmlDsigElement(document, element).setAttribute(attribute, value);
});

String _setAlgorithm(String source, String element, String value) =>
    _setAttribute(source, element, 'Algorithm', value);

String _setFirstTransform(String source, String value) => mutateSamlXmlDsig(
  source,
  (document) => samlXmlDsigElement(
    document,
    'Transforms',
  ).childElements.first.setAttribute('Algorithm', value),
);
