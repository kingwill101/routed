import '../core/saml_models.dart';

final class AuthSamlVerifierConformanceVector {
  const AuthSamlVerifierConformanceVector({
    required this.valid,
    required this.hostile,
  });

  /// A real, cryptographically valid response for the pinned test IdP.
  final AuthSamlVerificationInput valid;

  /// Modified, wrapping, duplicate-ID, reference-substitution, and algorithm
  /// confusion documents that the verifier must reject.
  final Map<String, AuthSamlVerificationInput> hostile;
}

final class AuthSamlVerifierConformanceFailure implements Exception {
  const AuthSamlVerifierConformanceFailure(this.caseId, this.cause);
  final String caseId;
  final Object cause;

  @override
  String toString() => 'AuthSamlVerifierConformanceFailure($caseId): $cause';
}

/// Framework-neutral conformance runner for application XMLDSig verifiers.
///
/// Applications must build vectors with signatures produced by their real IdP
/// or a standards-compliant signing implementation. Synthetic proof-only test
/// doubles do not establish production SAML interoperability.
final class AuthSamlVerifierConformanceSuite {
  const AuthSamlVerifierConformanceSuite({
    required this.verifier,
    required this.vector,
  });

  final AuthSamlAssertionVerifier verifier;
  final AuthSamlVerifierConformanceVector vector;

  Future<void> run() async {
    final valid = vector.valid;
    final proof = await verifier.verify(valid);
    if ((proof.signedResponseId != valid.responseId &&
            proof.signedAssertionId != valid.assertionId) ||
        (proof.signedResponseId != null &&
            proof.signedResponseId != valid.responseId) ||
        (proof.signedAssertionId != null &&
            proof.signedAssertionId != valid.assertionId)) {
      throw const AuthSamlVerifierConformanceFailure(
        'valid.exact-reference-binding',
        'Verifier did not bind the expected consumed element.',
      );
    }
    for (final entry in vector.hostile.entries) {
      try {
        await verifier.verify(entry.value);
      } catch (_) {
        continue;
      }
      throw AuthSamlVerifierConformanceFailure(
        'hostile.${entry.key}',
        'Verifier accepted a hostile XMLDSig vector.',
      );
    }
  }
}
