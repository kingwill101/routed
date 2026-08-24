import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:crypto_keys/crypto_keys.dart' as keys;
import 'package:einvoicesign/einvoicesign.dart' show canonicalizeSubtree;
import 'package:x509/x509.dart' as x509;
import 'package:xml/xml.dart';

import 'saml.dart' show AuthSamlLimits;
import 'saml_models.dart';

const String _xmlDsigNamespace = 'http://www.w3.org/2000/09/xmldsig#';
const String _samlProtocolNamespace = 'urn:oasis:names:tc:SAML:2.0:protocol';
const String _samlAssertionNamespace = 'urn:oasis:names:tc:SAML:2.0:assertion';

/// Signature methods implemented by [AuthPortableSamlXmlDsigVerifier].
enum AuthSamlXmlDsigSignatureAlgorithm {
  /// RSA with SHA-256.
  rsaSha256('http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'),

  /// RSA with SHA-384.
  rsaSha384('http://www.w3.org/2001/04/xmldsig-more#rsa-sha384'),

  /// RSA with SHA-512.
  rsaSha512('http://www.w3.org/2001/04/xmldsig-more#rsa-sha512');

  /// Creates an algorithm backed by its XMLDSig URI.
  const AuthSamlXmlDsigSignatureAlgorithm(this.uri);

  /// The XMLDSig signature-method URI.
  final String uri;
}

/// Digest methods implemented by [AuthPortableSamlXmlDsigVerifier].
enum AuthSamlXmlDsigDigestAlgorithm {
  /// SHA-256 with a 32-byte digest.
  sha256('http://www.w3.org/2001/04/xmlenc#sha256', 32),

  /// SHA-384 with a 48-byte digest.
  sha384('http://www.w3.org/2001/04/xmldsig-more#sha384', 48),

  /// SHA-512 with a 64-byte digest.
  sha512('http://www.w3.org/2001/04/xmlenc#sha512', 64);

  /// Creates a digest algorithm backed by its XMLDSig URI.
  const AuthSamlXmlDsigDigestAlgorithm(this.uri, this.byteLength);

  /// The XMLDSig digest-method URI.
  final String uri;

  /// The digest length in bytes.
  final int byteLength;
}

/// Explicit algorithm and structural policy for the portable XMLDSig verifier.
///
/// The default accepts the broadly deployed RSA-SHA256/SHA-256 profile only.
/// Applications must deliberately opt into every additional implemented
/// algorithm. SHA-1 is not implemented and cannot be enabled.
final class AuthSamlXmlDsigPolicy {
  /// Creates an explicit XMLDSig algorithm and signature-count policy.
  ///
  /// Throws an [ArgumentError] when no algorithm is enabled or when
  /// [maxSignatures] is outside the supported range of one to two.
  AuthSamlXmlDsigPolicy({
    Set<AuthSamlXmlDsigSignatureAlgorithm> signatureAlgorithms = const {
      AuthSamlXmlDsigSignatureAlgorithm.rsaSha256,
    },
    Set<AuthSamlXmlDsigDigestAlgorithm> digestAlgorithms = const {
      AuthSamlXmlDsigDigestAlgorithm.sha256,
    },
    this.maxSignatures = 2,
  }) : signatureAlgorithms = Set.unmodifiable(signatureAlgorithms),
       digestAlgorithms = Set.unmodifiable(digestAlgorithms) {
    if (signatureAlgorithms.isEmpty ||
        digestAlgorithms.isEmpty ||
        maxSignatures < 1 ||
        maxSignatures > 2) {
      throw ArgumentError('Invalid SAML XMLDSig policy.');
    }
  }

  /// Signature algorithms accepted by the verifier.
  final Set<AuthSamlXmlDsigSignatureAlgorithm> signatureAlgorithms;

  /// Digest algorithms accepted by the verifier.
  final Set<AuthSamlXmlDsigDigestAlgorithm> digestAlgorithms;

  /// Maximum number of XML signatures accepted in one document.
  final int maxSignatures;
}

/// A stable, non-diagnostic failure from portable SAML XMLDSig verification.
final class AuthSamlXmlDsigVerificationException implements Exception {
  /// Creates the non-diagnostic verification failure.
  const AuthSamlXmlDsigVerificationException();

  @override
  String toString() => 'AuthSamlXmlDsigVerificationException()';
}

/// Pure-Dart, application-selectable verifier for the bounded SAML XMLDSig
/// profile documented by [AuthSamlXmlDsigPolicy].
///
/// Trust comes only from the single certificate pinned on the selected
/// [AuthSamlConnection]. An embedded `KeyInfo/X509Certificate` is optional,
/// but when present it must byte-for-byte match that pin. Embedded keys never
/// become trust roots.
///
/// Every signature must be an enveloped direct child of the exact Response or
/// Assertion it references. References are local `#ID` values, use exactly the
/// enveloped-signature and exclusive-C14N transforms, and cannot use XPath,
/// XPointer, external resources, comments, implicit transforms, or an
/// InclusiveNamespaces prefix list.
final class AuthPortableSamlXmlDsigVerifier
    implements AuthSamlAssertionVerifier {
  /// Creates a bounded pure-Dart XMLDSig verifier.
  ///
  /// [policy] controls accepted algorithms. [limits] controls XML resource
  /// consumption and defaults to [AuthSamlLimits].
  AuthPortableSamlXmlDsigVerifier({
    AuthSamlXmlDsigPolicy? policy,
    this.limits = const AuthSamlLimits(),
  }) : policy = policy ?? AuthSamlXmlDsigPolicy() {
    if (limits.maxDecodedXmlBytes < 1 ||
        limits.maxNodes < 1 ||
        limits.maxDepth < 1 ||
        limits.maxAttributes < 1 ||
        limits.maxTextBytes < 1) {
      throw ArgumentError('Invalid SAML XML limits.');
    }
  }

  /// Exclusive XML canonicalization algorithm supported by this verifier.
  static const String exclusiveCanonicalizationAlgorithm =
      'http://www.w3.org/2001/10/xml-exc-c14n#';

  /// Enveloped-signature transform supported by this verifier.
  static const String envelopedSignatureTransform =
      'http://www.w3.org/2000/09/xmldsig#enveloped-signature';

  /// XMLDSig algorithm policy used during verification.
  final AuthSamlXmlDsigPolicy policy;

  /// XML parsing limits used during verification.
  final AuthSamlLimits limits;

  /// Verifies the signed response and returns its signature proof.
  ///
  /// Throws an [AuthSamlXmlDsigVerificationException] for malformed,
  /// unsupported, or cryptographically invalid input.
  @override
  AuthSamlSignatureProof verify(AuthSamlVerificationInput input) {
    try {
      return _verify(input);
    } catch (_) {
      throw const AuthSamlXmlDsigVerificationException();
    }
  }

  AuthSamlSignatureProof _verify(AuthSamlVerificationInput input) {
    final xmlBytes = utf8.encode(input.xml);
    if (xmlBytes.isEmpty || xmlBytes.length > limits.maxDecodedXmlBytes) {
      throw const FormatException();
    }
    if (input.xml.contains('<!DOCTYPE') || input.xml.contains('<!ENTITY')) {
      throw const FormatException();
    }

    final document = XmlDocument.parse(input.xml);
    _enforceBounds(document);
    final xmlVersion = document.declaration?.version;
    if (document.children.any((node) => node is XmlDoctype) ||
        (xmlVersion != null && xmlVersion != '1.0')) {
      throw const FormatException();
    }

    final elements = <XmlElement>[
      document.rootElement,
      ...document.rootElement.descendantElements,
    ];
    final responses = elements
        .where(
          (element) => _hasName(element, 'Response', _samlProtocolNamespace),
        )
        .toList(growable: false);
    final assertions = elements
        .where(
          (element) => _hasName(element, 'Assertion', _samlAssertionNamespace),
        )
        .toList(growable: false);
    if (responses.length != 1 ||
        !identical(responses.single, document.rootElement) ||
        assertions.length != 1) {
      throw const FormatException();
    }
    final ids = _indexIds(elements);
    final response = _requireTarget(
      ids,
      input.responseId,
      localName: 'Response',
      namespace: _samlProtocolNamespace,
    );
    final assertion = _requireTarget(
      ids,
      input.assertionId,
      localName: 'Assertion',
      namespace: _samlAssertionNamespace,
    );
    if (!_isDescendantOf(assertion, response)) throw const FormatException();

    final signatures = elements
        .where((element) => _hasName(element, 'Signature', _xmlDsigNamespace))
        .toList(growable: false);
    if (signatures.isEmpty || signatures.length > policy.maxSignatures) {
      throw const FormatException();
    }
    if (elements.any(
      (element) =>
          element.name.local == 'Signature' &&
          element.name.namespaceUri != _xmlDsigNamespace,
    )) {
      throw const FormatException();
    }

    final pinnedCertificate = _pinnedCertificate(input.connection);
    String? signedResponseId;
    String? signedAssertionId;
    AuthSamlXmlDsigSignatureAlgorithm? reportedSignature;
    AuthSamlXmlDsigDigestAlgorithm? reportedDigest;

    for (final signature in signatures) {
      final result = _verifySignature(
        signature,
        response: response,
        assertion: assertion,
        pinnedCertificate: pinnedCertificate,
      );
      if (result.targetId == input.responseId) {
        if (signedResponseId != null) throw const FormatException();
        signedResponseId = result.targetId;
      } else if (result.targetId == input.assertionId) {
        if (signedAssertionId != null) throw const FormatException();
        signedAssertionId = result.targetId;
      } else {
        throw const FormatException();
      }
      reportedSignature ??= result.signatureAlgorithm;
      reportedDigest ??= result.digestAlgorithm;
      if (reportedSignature != result.signatureAlgorithm ||
          reportedDigest != result.digestAlgorithm) {
        throw const FormatException();
      }
    }

    if (signedResponseId == null && signedAssertionId == null) {
      throw const FormatException();
    }
    return AuthSamlSignatureProof(
      signedResponseId: signedResponseId,
      signedAssertionId: signedAssertionId,
      signatureAlgorithm: reportedSignature!.uri,
      digestAlgorithm: reportedDigest!.uri,
      canonicalizationAlgorithm: exclusiveCanonicalizationAlgorithm,
    );
  }

  _VerifiedSignature _verifySignature(
    XmlElement signature, {
    required XmlElement response,
    required XmlElement assertion,
    required _PinnedCertificate pinnedCertificate,
  }) {
    final target = signature.parent;
    if (target is! XmlElement ||
        (!identical(target, response) && !identical(target, assertion))) {
      throw const FormatException();
    }

    _requireOnlyElementChildren(signature, const {
      'SignedInfo',
      'SignatureValue',
      'KeyInfo',
    });
    final signedInfo = _singleChild(signature, 'SignedInfo');
    final signatureValueElement = _singleChild(signature, 'SignatureValue');
    final keyInfos = _children(signature, 'KeyInfo');
    if (keyInfos.length > 1) throw const FormatException();
    if (keyInfos.isNotEmpty) {
      _verifyEmbeddedCertificate(keyInfos.single, pinnedCertificate);
    }

    _requireOnlyElementChildren(signedInfo, const {
      'CanonicalizationMethod',
      'SignatureMethod',
      'Reference',
    });
    final canonicalization = _singleChild(signedInfo, 'CanonicalizationMethod');
    if (canonicalization.getAttribute('Algorithm') !=
            exclusiveCanonicalizationAlgorithm ||
        !_isEmptyElement(canonicalization)) {
      throw const FormatException();
    }

    final signatureMethod = _singleChild(signedInfo, 'SignatureMethod');
    if (!_isEmptyElement(signatureMethod)) {
      throw const FormatException();
    }
    final signatureAlgorithm = _signatureAlgorithm(
      signatureMethod.getAttribute('Algorithm'),
    );

    final references = _children(signedInfo, 'Reference');
    if (references.length != 1) throw const FormatException();
    final reference = references.single;
    final targetId = target.getAttribute('ID');
    if (targetId == null || reference.getAttribute('URI') != '#$targetId') {
      throw const FormatException();
    }
    _verifyReference(reference, target, signature);

    final canonicalSignedInfo = canonicalizeSubtree(signedInfo);
    _requireTextOnly(signatureValueElement);
    final signatureBytes = _decodeBase64(
      signatureValueElement.innerText,
      maximumBytes: 1024,
    );
    if (!_verifyCryptographicSignature(
      pinnedCertificate.certificate.publicKey,
      signatureAlgorithm,
      canonicalSignedInfo,
      signatureBytes,
    )) {
      throw const FormatException();
    }

    final digestMethod = _singleChild(reference, 'DigestMethod');
    return _VerifiedSignature(
      targetId: targetId,
      signatureAlgorithm: signatureAlgorithm,
      digestAlgorithm: _digestAlgorithm(digestMethod.getAttribute('Algorithm')),
    );
  }

  void _verifyReference(
    XmlElement reference,
    XmlElement target,
    XmlElement signature,
  ) {
    _requireOnlyElementChildren(reference, const {
      'Transforms',
      'DigestMethod',
      'DigestValue',
    });
    final transforms = _singleChild(reference, 'Transforms');
    _requireOnlyElementChildren(transforms, const {'Transform'});
    final transformElements = _children(transforms, 'Transform');
    if (transformElements.length != 2 ||
        transformElements[0].getAttribute('Algorithm') !=
            envelopedSignatureTransform ||
        transformElements[1].getAttribute('Algorithm') !=
            exclusiveCanonicalizationAlgorithm ||
        transformElements.any((transform) => !_isEmptyElement(transform))) {
      throw const FormatException();
    }

    final digestMethod = _singleChild(reference, 'DigestMethod');
    if (!_isEmptyElement(digestMethod)) {
      throw const FormatException();
    }
    final digestAlgorithm = _digestAlgorithm(
      digestMethod.getAttribute('Algorithm'),
    );
    final digestValue = _singleChild(reference, 'DigestValue');
    _requireTextOnly(digestValue);
    final expected = _decodeBase64(
      digestValue.innerText,
      maximumBytes: digestAlgorithm.byteLength,
    );
    if (expected.length != digestAlgorithm.byteLength) {
      throw const FormatException();
    }

    final canonicalTarget = canonicalizeSubtree(target, omit: {signature});
    final actual = switch (digestAlgorithm) {
      AuthSamlXmlDsigDigestAlgorithm.sha256 =>
        crypto.sha256.convert(canonicalTarget).bytes,
      AuthSamlXmlDsigDigestAlgorithm.sha384 =>
        crypto.sha384.convert(canonicalTarget).bytes,
      AuthSamlXmlDsigDigestAlgorithm.sha512 =>
        crypto.sha512.convert(canonicalTarget).bytes,
    };
    if (!_constantTimeEquals(actual, expected)) throw const FormatException();
  }

  _PinnedCertificate _pinnedCertificate(AuthSamlConnection connection) {
    final parsed = x509.parsePem(connection.idpSigningCertificate).toList();
    if (parsed.length != 1 || parsed.single is! x509.X509Certificate) {
      throw const FormatException();
    }
    final certificate = parsed.single as x509.X509Certificate;
    final key = certificate.publicKey;
    if (key is keys.RsaPublicKey) {
      if (key.modulus.bitLength < 2048 ||
          key.modulus.bitLength > 8192 ||
          key.exponent < BigInt.from(3) ||
          key.exponent.isEven ||
          key.exponent.bitLength > 64) {
        throw const FormatException();
      }
    } else {
      throw const FormatException();
    }
    final matches = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
    ).allMatches(connection.idpSigningCertificate).toList(growable: false);
    if (matches.length != 1) throw const FormatException();
    final outside = connection.idpSigningCertificate
        .replaceFirst(matches.single.group(0)!, '')
        .trim();
    if (outside.isNotEmpty) throw const FormatException();
    final der = _decodeBase64(
      matches.single.group(1)!,
      maximumBytes: 24 * 1024,
    );
    return _PinnedCertificate(certificate: certificate, der: der);
  }

  void _verifyEmbeddedCertificate(
    XmlElement keyInfo,
    _PinnedCertificate pinned,
  ) {
    _requireOnlyElementChildren(keyInfo, const {'X509Data'});
    final data = _singleChild(keyInfo, 'X509Data');
    _requireOnlyElementChildren(data, const {'X509Certificate'});
    final embedded = _singleChild(data, 'X509Certificate');
    _requireTextOnly(embedded);
    final embeddedDer = _decodeBase64(
      embedded.innerText,
      maximumBytes: 24 * 1024,
    );
    if (!_constantTimeEquals(embeddedDer, pinned.der)) {
      throw const FormatException();
    }
  }

  bool _verifyCryptographicSignature(
    keys.PublicKey publicKey,
    AuthSamlXmlDsigSignatureAlgorithm algorithm,
    Uint8List message,
    Uint8List signature,
  ) {
    try {
      if (publicKey is! keys.RsaPublicKey) return false;
      final modulusBytes = (publicKey.modulus.bitLength + 7) ~/ 8;
      if (signature.length != modulusBytes) return false;

      final verifierAlgorithm = switch (algorithm) {
        AuthSamlXmlDsigSignatureAlgorithm.rsaSha256 =>
          keys.algorithms.signing.rsa.sha256,
        AuthSamlXmlDsigSignatureAlgorithm.rsaSha384 =>
          keys.algorithms.signing.rsa.sha384,
        AuthSamlXmlDsigSignatureAlgorithm.rsaSha512 =>
          keys.algorithms.signing.rsa.sha512,
      };
      return publicKey
          .createVerifier(verifierAlgorithm)
          .verify(message, keys.Signature(signature));
    } catch (_) {
      return false;
    }
  }

  AuthSamlXmlDsigSignatureAlgorithm _signatureAlgorithm(String? uri) {
    for (final algorithm in policy.signatureAlgorithms) {
      if (algorithm.uri == uri) return algorithm;
    }
    throw const FormatException();
  }

  AuthSamlXmlDsigDigestAlgorithm _digestAlgorithm(String? uri) {
    for (final algorithm in policy.digestAlgorithms) {
      if (algorithm.uri == uri) return algorithm;
    }
    throw const FormatException();
  }

  Map<String, XmlElement> _indexIds(List<XmlElement> elements) {
    final result = <String, XmlElement>{};
    final idPattern = RegExp(r'^[_A-Za-z][A-Za-z0-9._:-]{0,255}$');
    for (final element in elements) {
      final present = <String>[
        for (final name in const ['ID', 'Id', 'id'])
          ?element.getAttribute(name),
      ];
      if (present.length > 1) throw const FormatException();
      if (present.isEmpty) continue;
      final id = present.single;
      if (!idPattern.hasMatch(id) || result.containsKey(id)) {
        throw const FormatException();
      }
      result[id] = element;
    }
    return result;
  }

  XmlElement _requireTarget(
    Map<String, XmlElement> ids,
    String id, {
    required String localName,
    required String namespace,
  }) {
    final target = ids[id];
    if (target == null ||
        target.getAttribute('ID') != id ||
        !_hasName(target, localName, namespace)) {
      throw const FormatException();
    }
    return target;
  }

  void _enforceBounds(XmlDocument document) {
    var nodes = 0;
    var attributes = 0;
    var textBytes = 0;
    void visit(XmlNode node, int depth) {
      nodes += 1;
      if (nodes > limits.maxNodes || depth > limits.maxDepth) {
        throw const FormatException();
      }
      if (node is XmlElement) {
        attributes += node.attributes.length;
        if (attributes > limits.maxAttributes) throw const FormatException();
      }
      if (node is XmlText || node is XmlCDATA) {
        textBytes += utf8.encode(node.value ?? '').length;
        if (textBytes > limits.maxTextBytes) throw const FormatException();
      }
      for (final child in node.children) {
        visit(child, depth + 1);
      }
    }

    visit(document, 0);
  }
}

final class _VerifiedSignature {
  const _VerifiedSignature({
    required this.targetId,
    required this.signatureAlgorithm,
    required this.digestAlgorithm,
  });

  final String targetId;
  final AuthSamlXmlDsigSignatureAlgorithm signatureAlgorithm;
  final AuthSamlXmlDsigDigestAlgorithm digestAlgorithm;
}

final class _PinnedCertificate {
  const _PinnedCertificate({required this.certificate, required this.der});

  final x509.X509Certificate certificate;
  final Uint8List der;
}

bool _hasName(XmlElement element, String local, String namespace) =>
    element.name.local == local && element.name.namespaceUri == namespace;

List<XmlElement> _children(XmlElement parent, String local) => parent
    .childElements
    .where((element) => _hasName(element, local, _xmlDsigNamespace))
    .toList(growable: false);

XmlElement _singleChild(XmlElement parent, String local) {
  final children = _children(parent, local);
  if (children.length != 1) throw const FormatException();
  return children.single;
}

void _requireOnlyElementChildren(XmlElement parent, Set<String> allowed) {
  for (final node in parent.children) {
    if (node is XmlText && node.value.trim().isEmpty) continue;
    if (node is! XmlElement ||
        node.name.namespaceUri != _xmlDsigNamespace ||
        !allowed.contains(node.name.local)) {
      throw const FormatException();
    }
  }
}

bool _isEmptyElement(XmlElement element) => element.children.every(
  (node) => node is XmlText && node.value.trim().isEmpty,
);

void _requireTextOnly(XmlElement element) {
  if (element.children.isEmpty ||
      element.children.any((node) => node is! XmlText)) {
    throw const FormatException();
  }
}

bool _isDescendantOf(XmlElement child, XmlElement ancestor) {
  XmlNode? current = child.parent;
  while (current != null) {
    if (identical(current, ancestor)) return true;
    current = current.parent;
  }
  return false;
}

Uint8List _decodeBase64(String value, {required int maximumBytes}) {
  final compact = value.replaceAll(RegExp(r'\s'), '');
  if (compact.isEmpty || compact.length > ((maximumBytes + 2) ~/ 3) * 4) {
    throw const FormatException();
  }
  final decoded = base64.decode(compact);
  if (decoded.length > maximumBytes) throw const FormatException();
  return Uint8List.fromList(decoded);
}

bool _constantTimeEquals(List<int> first, List<int> second) {
  var difference = first.length ^ second.length;
  final length = first.length > second.length ? first.length : second.length;
  for (var index = 0; index < length; index += 1) {
    final left = index < first.length ? first[index] : 0;
    final right = index < second.length ? second[index] : 0;
    difference |= left ^ right;
  }
  return difference == 0;
}
