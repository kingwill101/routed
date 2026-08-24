part of 'fido_metadata.dart';

/// Input to an optional verifier for an attestation path whose metadata root
/// is omitted from the client-supplied WebAuthn certificate path.
final class FidoMetadataAttestationPathVerificationInput {
  FidoMetadataAttestationPathVerificationInput._({
    required this.attestation,
    required this.entry,
  });

  /// Attestation whose certificate path requires application verification.
  final WebAuthnAttestationMetadata attestation;

  /// Metadata entry whose roots should be used for path verification.
  final FidoMetadataEntry entry;
}

/// Verifies a WebAuthn certificate path to one of the MDS metadata roots.
///
/// The built-in path check accepts an exact final-certificate/root match. An
/// application that supports omitted roots can provide this callback and must
/// perform complete RFC 5280 path validation itself.
typedef FidoMetadataAttestationPathVerifier =
    FutureOr<bool> Function(FidoMetadataAttestationPathVerificationInput input);

/// Maps verified WebAuthn attestation provenance to an authenticated MDS entry.
final class FidoMetadataWebAuthnTrustEvaluator {
  /// Creates an evaluator for an authenticated metadata [blob].
  ///
  /// [updateAvailable] controls the decision for a certified authenticator
  /// that has an update available but is still at the metadata version. The
  /// [uncertified] decision applies to uncertified and self-asserted statuses.
  /// When supplied, [verifyAttestationPath] may validate paths whose metadata
  /// root is not present in the attestation's supplied certificate path.
  FidoMetadataWebAuthnTrustEvaluator({
    required this.blob,
    this.updateAvailable = WebAuthnAttestationTrustDecision.downgrade,
    this.uncertified = WebAuthnAttestationTrustDecision.reject,
    this.verifyAttestationPath,
  });

  /// Authenticated metadata blob used for lookups.
  final FidoMetadataBlob blob;

  /// Decision applied to certified authenticators with an available update.
  final WebAuthnAttestationTrustDecision updateAvailable;

  /// Decision applied to uncertified or self-asserted authenticators.
  final WebAuthnAttestationTrustDecision uncertified;

  /// Optional application-owned certificate path verifier.
  final FidoMetadataAttestationPathVerifier? verifyAttestationPath;

  /// Evaluates and preserves typed provenance without exposing parser errors.
  Future<FidoMetadataEvaluation> evaluate(
    WebAuthnAttestationMetadata attestation,
  ) async {
    _FidoMetadataEntryMatch? match;
    try {
      match = _findEntry(attestation);
    } catch (_) {
      return FidoMetadataEvaluation._(
        decision: WebAuthnAttestationTrustDecision.reject,
        reason: FidoMetadataEvaluationReason.certificatePathUntrusted,
      );
    }
    if (match == null) {
      return FidoMetadataEvaluation._(
        decision: WebAuthnAttestationTrustDecision.reject,
        reason: FidoMetadataEvaluationReason.noMatchingEntry,
      );
    }
    final entry = match.entry;
    if (attestation.certificateTrustPath.isEmpty ||
        entry.metadataStatement.attestationRootCertificates.isEmpty) {
      return FidoMetadataEvaluation._(
        decision: WebAuthnAttestationTrustDecision.reject,
        reason: FidoMetadataEvaluationReason.certificatePathUntrusted,
      );
    }
    final pathTrusted = _pathEndsAtMetadataRoot(attestation, entry);
    if (!pathTrusted) {
      if (verifyAttestationPath == null) {
        return FidoMetadataEvaluation._(
          decision: WebAuthnAttestationTrustDecision.reject,
          reason: FidoMetadataEvaluationReason.certificatePathUntrusted,
        );
      }
      try {
        if (!await verifyAttestationPath!(
          FidoMetadataAttestationPathVerificationInput._(
            attestation: attestation,
            entry: entry,
          ),
        )) {
          return FidoMetadataEvaluation._(
            decision: WebAuthnAttestationTrustDecision.reject,
            reason: FidoMetadataEvaluationReason.certificatePathUntrusted,
          );
        }
      } catch (_) {
        return FidoMetadataEvaluation._(
          decision: WebAuthnAttestationTrustDecision.reject,
          reason: FidoMetadataEvaluationReason.certificatePathUntrusted,
        );
      }
    }

    // MDS defines the final StatusReport as the authenticator's current
    // status. Historical security reports must not override a later update,
    // while an unknown current status must fail closed.
    final report = entry.statusReports.last;
    final provenance = FidoMetadataProvenance._(
      blobNumber: blob.number,
      attestationAaguid: attestation.aaguid,
      entryAaguid: entry.aaguid,
      matchKind: match.kind,
      status: report,
      metadataRootFingerprints: entry
          .metadataStatement
          .attestationRootCertificates
          .map((certificate) => certificate.sha256Fingerprint)
          .toList(growable: false),
    );
    final statusDecision = _decisionForReport(report, entry);
    final reason = statusDecision == WebAuthnAttestationTrustDecision.accept
        ? FidoMetadataEvaluationReason.accepted
        : statusDecision == WebAuthnAttestationTrustDecision.downgrade
        ? FidoMetadataEvaluationReason.downgraded
        : report.status == FidoMetadataAuthenticatorStatus.unknown
        ? FidoMetadataEvaluationReason.statusUnavailable
        : report.status == FidoMetadataAuthenticatorStatus.updateAvailable &&
              (report.authenticatorVersion == null ||
                  report.authenticatorVersion !=
                      entry.metadataStatement.authenticatorVersion)
        ? FidoMetadataEvaluationReason.updateVersionMismatch
        : FidoMetadataEvaluationReason.statusRejected;
    return FidoMetadataEvaluation._(
      decision: statusDecision,
      reason: reason,
      provenance: provenance,
    );
  }

  /// Adapter directly compatible with [WebAuthnAttestationTrustPolicy].
  Future<WebAuthnAttestationTrustDecision> call(
    WebAuthnAttestationMetadata attestation,
  ) async => (await evaluate(attestation)).decision;

  /// Creates a WebAuthn policy that retains the caller's choices for unproven
  /// `none` and self attestation while routing certificate attestations here.
  WebAuthnAttestationTrustPolicy asWebAuthnTrustPolicy({
    WebAuthnUnprovenAttestationDecision none =
        WebAuthnUnprovenAttestationDecision.accept,
    WebAuthnUnprovenAttestationDecision self =
        WebAuthnUnprovenAttestationDecision.accept,
  }) => WebAuthnAttestationTrustPolicy(
    none: none,
    self: self,
    certificate: WebAuthnAttestationTrustDecision.reject,
    evaluateCertificate: call,
  );

  WebAuthnAttestationTrustDecision _decisionForReport(
    FidoMetadataStatusReport report,
    FidoMetadataEntry entry,
  ) {
    switch (report.status) {
      case FidoMetadataAuthenticatorStatus.revoked:
      case FidoMetadataAuthenticatorStatus.userVerificationBypass:
      case FidoMetadataAuthenticatorStatus.attestationKeyCompromise:
      case FidoMetadataAuthenticatorStatus.userKeyRemoteCompromise:
      case FidoMetadataAuthenticatorStatus.userKeyPhysicalCompromise:
        return WebAuthnAttestationTrustDecision.reject;
      case FidoMetadataAuthenticatorStatus.updateAvailable:
        if (report.authenticatorVersion == null ||
            report.authenticatorVersion !=
                entry.metadataStatement.authenticatorVersion) {
          return WebAuthnAttestationTrustDecision.reject;
        }
        return updateAvailable;
      case FidoMetadataAuthenticatorStatus.notFidoCertified:
      case FidoMetadataAuthenticatorStatus.selfAssertionSubmitted:
        return uncertified;
      case FidoMetadataAuthenticatorStatus.retired:
        return WebAuthnAttestationTrustDecision.reject;
      case FidoMetadataAuthenticatorStatus.fidoCertified:
      case FidoMetadataAuthenticatorStatus.fidoCertifiedL1:
      case FidoMetadataAuthenticatorStatus.fidoCertifiedL1Plus:
      case FidoMetadataAuthenticatorStatus.fidoCertifiedL2:
      case FidoMetadataAuthenticatorStatus.fidoCertifiedL2Plus:
      case FidoMetadataAuthenticatorStatus.fidoCertifiedL3:
      case FidoMetadataAuthenticatorStatus.fidoCertifiedL3Plus:
      case FidoMetadataAuthenticatorStatus.fips140CertifiedL1:
      case FidoMetadataAuthenticatorStatus.fips140CertifiedL2:
      case FidoMetadataAuthenticatorStatus.fips140CertifiedL3:
      case FidoMetadataAuthenticatorStatus.fips140CertifiedL4:
        return WebAuthnAttestationTrustDecision.accept;
      case FidoMetadataAuthenticatorStatus.unknown:
        return WebAuthnAttestationTrustDecision.reject;
    }
  }

  bool _pathEndsAtMetadataRoot(
    WebAuthnAttestationMetadata attestation,
    FidoMetadataEntry entry,
  ) {
    final last = attestation.certificateTrustPath.last;
    return entry.metadataStatement.attestationRootCertificates.any(
      (root) => _constantTimeEqual(last.derBytes, root.derBytes),
    );
  }

  _FidoMetadataEntryMatch? _findEntry(WebAuthnAttestationMetadata attestation) {
    final normalizedAaguid = normalizeFidoAaguid(attestation.aaguid);
    if (!isZeroFidoAaguid(normalizedAaguid)) {
      for (final entry in blob.entries) {
        if (entry.aaguid == normalizedAaguid) {
          return _FidoMetadataEntryMatch(
            entry: entry,
            kind: FidoMetadataMatchKind.aaguid,
          );
        }
      }
    }
    if (attestation.certificateTrustPath.isEmpty) return null;
    final keyIdentifier = _certificateKeyIdentifier(
      attestation.certificateTrustPath.first.derBytes,
    );
    for (final entry in blob.entries) {
      if (entry.attestationCertificateKeyIdentifiers.contains(keyIdentifier)) {
        return _FidoMetadataEntryMatch(
          entry: entry,
          kind: FidoMetadataMatchKind.attestationCertificateKeyIdentifier,
        );
      }
    }
    return null;
  }

  bool _constantTimeEqual(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var result = 0;
    for (var index = 0; index < first.length; index++) {
      result |= first[index] ^ second[index];
    }
    return result == 0;
  }
}

final class _FidoMetadataEntryMatch {
  const _FidoMetadataEntryMatch({required this.entry, required this.kind});

  final FidoMetadataEntry entry;
  final FidoMetadataMatchKind kind;
}
