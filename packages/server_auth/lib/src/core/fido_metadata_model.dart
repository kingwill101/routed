part of 'fido_metadata.dart';

/// The status values currently defined by FIDO Metadata Service 3.1.1.
enum FidoMetadataAuthenticatorStatus {
  notFidoCertified,
  fidoCertified,
  userVerificationBypass,
  attestationKeyCompromise,
  userKeyRemoteCompromise,
  userKeyPhysicalCompromise,
  updateAvailable,
  retired,
  revoked,
  selfAssertionSubmitted,
  fidoCertifiedL1,
  fidoCertifiedL1Plus,
  fidoCertifiedL2,
  fidoCertifiedL2Plus,
  fidoCertifiedL3,
  fidoCertifiedL3Plus,
  fips140CertifiedL1,
  fips140CertifiedL2,
  fips140CertifiedL3,
  fips140CertifiedL4,
  unknown,
}

/// How a WebAuthn attestation was matched to an MDS entry.
enum FidoMetadataMatchKind { aaguid, attestationCertificateKeyIdentifier }

/// The reason attached to a typed metadata evaluation.
enum FidoMetadataEvaluationReason {
  accepted,
  downgraded,
  noMatchingEntry,
  certificatePathUntrusted,
  statusRejected,
  statusUnavailable,
  updateVersionMismatch,
}

/// How the deprecated MDS `nextUpdate` field affects blob acceptance.
enum FidoMetadataNextUpdatePolicy {
  /// Parse and bound the field when present, but do not require it or reject a
  /// cryptographically valid blob solely because the advisory date elapsed.
  advisory,

  /// Reject a present `nextUpdate` value after it has elapsed.
  ///
  /// A missing value is still accepted for forward compatibility with the
  /// field's planned removal from MDS.
  requireFreshWhenPresent,
}

/// Normalizes the two AAGUID spellings found in deployed MDS data.
///
/// The returned value is lowercase and uses the canonical 8-4-4-4-12 UUID
/// spelling. An all-zero AAGUID is valid input but is not a useful model
/// identifier for a metadata lookup.
String normalizeFidoAaguid(String value) {
  final compactPattern = RegExp(r'^[0-9a-fA-F]{32}$');
  final dashedPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  if (!compactPattern.hasMatch(value) && !dashedPattern.hasMatch(value)) {
    throw const FormatException('Invalid FIDO metadata');
  }
  final compact = value.replaceAll('-', '').toLowerCase();
  return '${compact.substring(0, 8)}-'
      '${compact.substring(8, 12)}-'
      '${compact.substring(12, 16)}-'
      '${compact.substring(16, 20)}-'
      '${compact.substring(20)}';
}

/// Returns whether [aaguid] is the WebAuthn all-zero placeholder.
bool isZeroFidoAaguid(String aaguid) =>
    normalizeFidoAaguid(aaguid) == '00000000-0000-0000-0000-000000000000';

/// A certificate trust anchor from a metadata statement.
final class FidoMetadataCertificate {
  FidoMetadataCertificate._(List<int> derBytes)
    : derBytes = List<int>.unmodifiable(List<int>.from(derBytes)),
      sha256Fingerprint = crypto.sha256.convert(derBytes).toString();

  /// Immutable DER-encoded PKIX certificate bytes.
  final List<int> derBytes;

  /// Lowercase hexadecimal SHA-256 fingerprint of [derBytes].
  final String sha256Fingerprint;
}

/// One status report attached to a metadata entry.
final class FidoMetadataStatusReport {
  FidoMetadataStatusReport._({
    required this.status,
    required this.rawStatus,
    this.effectiveDate,
    this.authenticatorVersion,
    this.certificateSha256Fingerprint,
    this.batchCertificateSha256Fingerprint,
    this.url,
  });

  /// Parsed status, or [FidoMetadataAuthenticatorStatus.unknown].
  final FidoMetadataAuthenticatorStatus status;

  /// Original status token, retained so unknown future values remain
  /// distinguishable without exposing parser diagnostics.
  final String rawStatus;

  final DateTime? effectiveDate;
  final int? authenticatorVersion;
  final String? certificateSha256Fingerprint;
  final String? batchCertificateSha256Fingerprint;
  final Uri? url;
}

/// The metadata statement fields used by WebAuthn trust evaluation.
final class FidoMetadataStatement {
  FidoMetadataStatement._({
    required this.schema,
    required this.description,
    required this.authenticatorVersion,
    required this.protocolFamily,
    required this.aaguid,
    required this.aaid,
    required List<String> attestationCertificateKeyIdentifiers,
    required List<FidoMetadataCertificate> attestationRootCertificates,
  }) : attestationCertificateKeyIdentifiers = List<String>.unmodifiable(
         List<String>.from(attestationCertificateKeyIdentifiers),
       ),
       attestationRootCertificates = List<FidoMetadataCertificate>.unmodifiable(
         List<FidoMetadataCertificate>.from(attestationRootCertificates),
       );

  final int schema;
  final String description;
  final int authenticatorVersion;
  final String protocolFamily;
  final String? aaguid;
  final String? aaid;
  final List<String> attestationCertificateKeyIdentifiers;
  final List<FidoMetadataCertificate> attestationRootCertificates;
}

/// One `MetadataBLOBPayloadEntry` from an authenticated MDS blob.
final class FidoMetadataEntry {
  FidoMetadataEntry._({
    required this.aaguid,
    required this.aaid,
    required List<String> attestationCertificateKeyIdentifiers,
    required this.metadataStatement,
    required List<FidoMetadataStatusReport> statusReports,
    required this.timeOfLastStatusChange,
  }) : attestationCertificateKeyIdentifiers = List<String>.unmodifiable(
         List<String>.from(attestationCertificateKeyIdentifiers),
       ),
       statusReports = List<FidoMetadataStatusReport>.unmodifiable(
         List<FidoMetadataStatusReport>.from(statusReports),
       );

  final String? aaguid;
  final String? aaid;
  final List<String> attestationCertificateKeyIdentifiers;
  final FidoMetadataStatement metadataStatement;
  final List<FidoMetadataStatusReport> statusReports;
  final DateTime timeOfLastStatusChange;
}

/// A verified and time-valid MDS3 compact JWT payload.
final class FidoMetadataBlob {
  FidoMetadataBlob._({
    required this.number,
    required this.verifiedAt,
    required this.issuedAt,
    required this.nextUpdate,
    required this.algorithm,
    required List<FidoMetadataEntry> entries,
  }) : entries = List<FidoMetadataEntry>.unmodifiable(
         List<FidoMetadataEntry>.from(entries),
       );

  final int number;

  /// Caller-supplied time at which this blob was cryptographically verified.
  final DateTime verifiedAt;

  /// Optional JWT `iat` claim when a metadata source supplies one.
  ///
  /// MDS 3.1.1 declares this claim, but live official blobs may omit it.
  /// Relying parties must therefore use [verifiedAt] and their refresh policy
  /// rather than inventing issuance provenance.
  final DateTime? issuedAt;

  /// Deprecated advisory update date, absent in future-compatible blobs.
  final DateTime? nextUpdate;
  final String algorithm;
  final List<FidoMetadataEntry> entries;
}

/// Safe provenance for a WebAuthn metadata decision.
final class FidoMetadataProvenance {
  FidoMetadataProvenance._({
    required this.blobNumber,
    required this.attestationAaguid,
    required this.entryAaguid,
    required this.matchKind,
    required this.status,
    required List<String> metadataRootFingerprints,
  }) : metadataRootFingerprints = List<String>.unmodifiable(
         List<String>.from(metadataRootFingerprints),
       );

  final int blobNumber;
  final String attestationAaguid;
  final String? entryAaguid;
  final FidoMetadataMatchKind matchKind;
  final FidoMetadataStatusReport status;
  final List<String> metadataRootFingerprints;
}

/// Typed result returned by [FidoMetadataWebAuthnTrustEvaluator].
final class FidoMetadataEvaluation {
  FidoMetadataEvaluation._({
    required this.decision,
    required this.reason,
    this.provenance,
  });

  final WebAuthnAttestationTrustDecision decision;
  final FidoMetadataEvaluationReason reason;
  final FidoMetadataProvenance? provenance;
}
