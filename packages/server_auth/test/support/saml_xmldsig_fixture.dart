import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:crypto_keys/crypto_keys.dart' as keys;
import 'package:einvoicesign/einvoicesign.dart' show canonicalizeSubtree;
import 'package:server_auth/server_auth.dart';
import 'package:x509/x509.dart' as x509;
import 'package:xml/xml.dart';

const samlXmlDsigResponseId = '_response';
const samlXmlDsigAssertionId = '_assertion';
const _xmlDsigNamespace = 'http://www.w3.org/2000/09/xmldsig#';

enum SamlXmlDsigSignedTarget { response, assertion }

String samlXmlDsigFixture(String name) {
  for (final root in const ['', 'packages/server_auth/']) {
    final file = File('${root}test/fixtures/saml_xmldsig/$name');
    if (file.existsSync()) return file.readAsStringSync();
  }
  throw StateError('SAML XMLDSig fixture not found: $name');
}

String get samlXmlDsigCertificatePem => samlXmlDsigFixture('idp-cert.pem');

String get samlXmlDsigSignedAssertion =>
    samlXmlDsigFixture('signed_assertion.xml');

AuthSamlConnection samlXmlDsigConnection({String? certificate}) =>
    AuthSamlConnection(
      providerId: 'enterprise',
      idpEntityId: 'https://idp.example.test/entity',
      idpSsoUrl: Uri.parse('https://idp.example.test/sso'),
      idpSigningCertificate: certificate ?? samlXmlDsigCertificatePem,
      spEntityId: 'https://sp.example.test/entity',
      assertionConsumerServiceUrl: Uri.parse(
        'https://sp.example.test/auth/sso/saml/acs/enterprise',
      ),
    );

AuthSamlVerificationInput samlXmlDsigInput(
  String xml, {
  AuthSamlConnection? connection,
  String responseId = samlXmlDsigResponseId,
  String assertionId = samlXmlDsigAssertionId,
}) => AuthSamlVerificationInput(
  xml: xml,
  connection: connection ?? samlXmlDsigConnection(),
  responseId: responseId,
  assertionId: assertionId,
);

String signSamlXmlDsigFixture({
  SamlXmlDsigSignedTarget target = SamlXmlDsigSignedTarget.assertion,
  AuthSamlXmlDsigSignatureAlgorithm signatureAlgorithm =
      AuthSamlXmlDsigSignatureAlgorithm.rsaSha256,
  AuthSamlXmlDsigDigestAlgorithm digestAlgorithm =
      AuthSamlXmlDsigDigestAlgorithm.sha256,
  bool includeKeyInfo = true,
}) {
  final document = XmlDocument.parse(samlXmlDsigSignedAssertion);
  final signature = _element(document, 'Signature').copy();
  final previousParent = _element(document, 'Signature').parent!;
  previousParent.children.removeWhere(
    (node) => node is XmlElement && _isDsig(node, 'Signature'),
  );

  _element(
    signature,
    'SignatureMethod',
  ).setAttribute('Algorithm', signatureAlgorithm.uri);
  _element(
    signature,
    'DigestMethod',
  ).setAttribute('Algorithm', digestAlgorithm.uri);
  final targetElement = switch (target) {
    SamlXmlDsigSignedTarget.response => document.rootElement,
    SamlXmlDsigSignedTarget.assertion =>
      document.descendantElements.singleWhere(
        (element) => element.name.local == 'Assertion',
      ),
  };
  final targetId = targetElement.getAttribute('ID')!;
  _element(signature, 'Reference').setAttribute('URI', '#$targetId');
  _element(signature, 'DigestValue').innerText = '';
  _element(signature, 'SignatureValue').innerText = '';
  if (!includeKeyInfo) {
    signature.children.removeWhere(
      (node) => node is XmlElement && _isDsig(node, 'KeyInfo'),
    );
  }

  final issuerIndex = targetElement.children.indexWhere(
    (node) => node is XmlElement && node.name.local == 'Issuer',
  );
  targetElement.children.insert(issuerIndex + 1, signature);

  final canonicalTarget = canonicalizeSubtree(targetElement, omit: {signature});
  final digest = switch (digestAlgorithm) {
    AuthSamlXmlDsigDigestAlgorithm.sha256 =>
      crypto.sha256.convert(canonicalTarget).bytes,
    AuthSamlXmlDsigDigestAlgorithm.sha384 =>
      crypto.sha384.convert(canonicalTarget).bytes,
    AuthSamlXmlDsigDigestAlgorithm.sha512 =>
      crypto.sha512.convert(canonicalTarget).bytes,
  };
  _element(signature, 'DigestValue').innerText = base64.encode(digest);

  final privateKey = x509
      .parsePem(samlXmlDsigFixture('idp-private.pem'))
      .single;
  if (privateKey is! x509.PrivateKeyInfo) {
    throw StateError('Expected a PKCS#8 private key fixture.');
  }
  final signerAlgorithm = switch (signatureAlgorithm) {
    AuthSamlXmlDsigSignatureAlgorithm.rsaSha256 =>
      keys.algorithms.signing.rsa.sha256,
    AuthSamlXmlDsigSignatureAlgorithm.rsaSha384 =>
      keys.algorithms.signing.rsa.sha384,
    AuthSamlXmlDsigSignatureAlgorithm.rsaSha512 =>
      keys.algorithms.signing.rsa.sha512,
  };
  final signedInfo = _element(signature, 'SignedInfo');
  final signatureBytes = privateKey.keyPair
      .createSigner(signerAlgorithm)
      .sign(canonicalizeSubtree(signedInfo))
      .data;
  _element(signature, 'SignatureValue').innerText = base64.encode(
    signatureBytes,
  );
  return document.toXmlString(pretty: false);
}

String mutateSamlXmlDsig(
  String source,
  void Function(XmlDocument document) mutate,
) {
  final document = XmlDocument.parse(source);
  mutate(document);
  return document.toXmlString(pretty: false);
}

XmlElement samlXmlDsigElement(XmlNode root, String local) =>
    _element(root, local);

XmlElement _element(XmlNode root, String local) {
  final candidates = root is XmlElement
      ? <XmlElement>[root, ...root.descendantElements]
      : root.descendantElements.toList(growable: false);
  return candidates.singleWhere((element) => _isDsig(element, local));
}

bool _isDsig(XmlElement element, String local) =>
    element.name.local == local &&
    element.name.namespaceUri == _xmlDsigNamespace;
