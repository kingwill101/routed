import 'package:server_auth/src/core/saml_models.dart';

/// Valid and hostile signed documents used by a SAML verifier suite.
final class AuthSamlVerifierConformanceVector {
  /// Creates a valid vector and hostile documents for an
  /// [AuthSamlAssertionVerifier].
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

/// Describes a failed SAML verifier conformance case.
final class AuthSamlVerifierConformanceFailure implements Exception {
  /// Creates a failure for [caseId] caused by [cause].
  const AuthSamlVerifierConformanceFailure(this.caseId, this.cause);

  /// Stable identifier of the failed case.
  final String caseId;

  /// Error raised by the verifier or the failed expectation.
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
  /// Creates a suite for [verifier] and its signed test [vector].
  const AuthSamlVerifierConformanceSuite({
    required this.verifier,
    required this.vector,
  });

  /// SAML assertion verifier under test.
  final AuthSamlAssertionVerifier verifier;

  /// Valid and hostile documents used by [run].
  final AuthSamlVerifierConformanceVector vector;

  /// Verifies the valid binding and rejection of every hostile document.
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
