part of 'fido_metadata.dart';

/// The status values currently defined by FIDO Metadata Service 3.1.1.
enum FidoMetadataAuthenticatorStatus {
  /// The authenticator has not completed FIDO certification.
  notFidoCertified,

  /// The authenticator is FIDO certified.
  fidoCertified,

  /// The authenticator permits bypassing user verification.
  userVerificationBypass,

  /// The authenticator's attestation key has been compromised.
  attestationKeyCompromise,

  /// The authenticator's user key has been compromised remotely.
  userKeyRemoteCompromise,

  /// The authenticator's user key has been compromised physically.
  userKeyPhysicalCompromise,

  /// An update is available for the authenticator.
  updateAvailable,

  /// The authenticator has been retired.
  retired,

  /// The authenticator has been revoked.
  revoked,

  /// The authenticator's self-asserted status was submitted.
  selfAssertionSubmitted,

  /// The authenticator is FIDO Certified Level 1.
  fidoCertifiedL1,

  /// The authenticator is FIDO Certified Level 1 Plus.
  fidoCertifiedL1Plus,

  /// The authenticator is FIDO Certified Level 2.
  fidoCertifiedL2,

  /// The authenticator is FIDO Certified Level 2 Plus.
  fidoCertifiedL2Plus,

  /// The authenticator is FIDO Certified Level 3.
  fidoCertifiedL3,

  /// The authenticator is FIDO Certified Level 3 Plus.
  fidoCertifiedL3Plus,

  /// The authenticator is FIPS 140 certified at Level 1.
  fips140CertifiedL1,

  /// The authenticator is FIPS 140 certified at Level 2.
  fips140CertifiedL2,

  /// The authenticator is FIPS 140 certified at Level 3.
  fips140CertifiedL3,

  /// The authenticator is FIPS 140 certified at Level 4.
  fips140CertifiedL4,

  /// The status token was not recognized by this version of the package.
  unknown,
}

/// How a WebAuthn attestation was matched to an MDS entry.
enum FidoMetadataMatchKind {
  /// The authenticator's AAGUID matched the metadata entry.
  aaguid,

  /// An attestation-certificate key identifier matched the metadata entry.
  attestationCertificateKeyIdentifier,
}

/// The reason attached to a typed metadata evaluation.
enum FidoMetadataEvaluationReason {
  /// The metadata entry and status allowed the attestation.
  accepted,

  /// The metadata entry allowed the attestation with reduced trust.
  downgraded,

  /// No metadata entry matched the attestation.
  noMatchingEntry,

  /// The attestation certificate path could not be trusted to a metadata root.
  certificatePathUntrusted,

  /// The metadata status rejected the authenticator.
  statusRejected,

  /// The metadata status was unknown or unavailable.
  statusUnavailable,

  /// The authenticator version did not satisfy an update requirement.
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
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
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

  /// Date on which this status became effective, when supplied by MDS.
  final DateTime? effectiveDate;

  /// Authenticator firmware version associated with the report, when supplied.
  final int? authenticatorVersion;

  /// SHA-256 fingerprint of the affected certificate, when supplied.
  final String? certificateSha256Fingerprint;

  /// SHA-256 fingerprint of the affected batch certificate, when supplied.
  final String? batchCertificateSha256Fingerprint;

  /// Reference URL supplied with the status report, when available.
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

  /// Metadata statement schema number.
  final int schema;

  /// Human-readable authenticator description.
  final String description;

  /// Authenticator firmware version described by the statement.
  final int authenticatorVersion;

  /// Protocol family used by the authenticator.
  final String protocolFamily;

  /// Authenticator AAGUID, when the statement identifies one.
  final String? aaguid;

  /// Authenticator AAID, when the statement identifies one.
  final String? aaid;

  /// Key identifiers for attestation certificates recognized by the statement.
  final List<String> attestationCertificateKeyIdentifiers;

  /// Root certificates trusted for authenticator attestation.
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

  /// Authenticator AAGUID used to select this entry, when present.
  final String? aaguid;

  /// Authenticator AAID used to select this entry, when present.
  final String? aaid;

  /// Attestation-certificate key identifiers used to select this entry.
  final List<String> attestationCertificateKeyIdentifiers;

  /// Metadata statement describing the authenticator.
  final FidoMetadataStatement metadataStatement;

  /// Status reports ordered as supplied by the authenticated MDS blob.
  final List<FidoMetadataStatusReport> statusReports;

  /// Date of the most recent status change in the entry.
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

  /// Monotonically increasing MDS blob number.
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

  /// JWS algorithm used to authenticate this blob.
  final String algorithm;

  /// Metadata entries contained in the authenticated blob.
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

  /// MDS blob number that supplied the matched entry.
  final int blobNumber;

  /// AAGUID presented by the attestation.
  final String attestationAaguid;

  /// AAGUID on the matched entry, when present.
  final String? entryAaguid;

  /// Mechanism used to find the matched entry.
  final FidoMetadataMatchKind matchKind;

  /// Current status report used for the trust decision.
  final FidoMetadataStatusReport status;

  /// SHA-256 fingerprints of the metadata roots used by the entry.
  final List<String> metadataRootFingerprints;
}

/// Typed result returned by [FidoMetadataWebAuthnTrustEvaluator].
final class FidoMetadataEvaluation {
  FidoMetadataEvaluation._({
    required this.decision,
    required this.reason,
    this.provenance,
  });

  /// Trust decision returned to the WebAuthn verifier.
  final WebAuthnAttestationTrustDecision decision;

  /// Structured reason for [decision].
  final FidoMetadataEvaluationReason reason;

  /// Matched metadata provenance, or `null` when no trusted match exists.
  final FidoMetadataProvenance? provenance;
}
