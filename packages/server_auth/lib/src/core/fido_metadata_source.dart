part of 'fido_metadata.dart';

/// Resource bounds applied before any MDS payload is materialized.
final class FidoMetadataLimits {
  /// Creates resource limits for parsing an MDS blob.
  ///
  /// Each limit is checked before the corresponding value is materialized.
  const FidoMetadataLimits({
    this.maxBlobBytes = 32 * 1024 * 1024,
    this.maxJwtSegmentBytes = 24 * 1024 * 1024,
    this.maxCertificateBytes = 16 * 1024,
    this.maxCertificates = 8,
    this.maxEntries = 10000,
    this.maxStatusReportsPerEntry = 64,
    this.maxStatusStringBytes = 64,
    this.maxStringBytes = 4096,
    this.maxJsonDepth = 64,
    this.maxCertificateRootsPerStatement = 32,
    this.maxMetadataLifetime = const Duration(days: 366 * 5),
  });

  /// Maximum compact JWT size in bytes.
  final int maxBlobBytes;

  /// Maximum size of an individual JWT segment in bytes.
  final int maxJwtSegmentBytes;

  /// Maximum DER certificate size in bytes.
  final int maxCertificateBytes;

  /// Maximum number of certificates in a supplied chain or trust set.
  final int maxCertificates;

  /// Maximum number of metadata entries in a blob.
  final int maxEntries;

  /// Maximum status reports retained for one metadata entry.
  final int maxStatusReportsPerEntry;

  /// Maximum UTF-8 byte length of an individual status token.
  final int maxStatusStringBytes;

  /// Maximum UTF-8 byte length of bounded metadata strings.
  final int maxStringBytes;

  /// Maximum nesting depth accepted by the JSON duplicate scanner.
  final int maxJsonDepth;

  /// Maximum metadata roots retained in one statement.
  final int maxCertificateRootsPerStatement;

  /// Maximum lifetime allowed between metadata timestamps.
  final Duration maxMetadataLifetime;
}

/// The only cryptographic operation the package delegates to applications.
///
/// The callback MUST verify the JWS signature and the complete certificate
/// path, including validity and revocation, under `trustAnchors`. The loader
/// does not fetch `x5u`, perform network I/O, or treat parsed JSON as trusted
/// before this callback returns [FidoMetadataJwsVerificationResult.verified].
typedef FidoMetadataJwsVerifier =
    FutureOr<FidoMetadataJwsVerificationResult> Function(
      FidoMetadataJwsVerificationInput input,
    );

/// Immutable input to an application's offline MDS JWS verifier.
final class FidoMetadataJwsVerificationInput {
  FidoMetadataJwsVerificationInput._({
    required this.compact,
    required this.signingInput,
    required this.header,
    required List<int> payloadBytes,
    required List<int> signatureBytes,
    required List<List<int>> certificateChain,
    required List<List<int>> trustAnchors,
    required this.algorithm,
    required this.now,
  }) : payloadBytes = List<int>.unmodifiable(List<int>.from(payloadBytes)),
       signatureBytes = List<int>.unmodifiable(List<int>.from(signatureBytes)),
       certificateChain = List<List<int>>.unmodifiable(
         certificateChain
             .map(
               (certificate) =>
                   List<int>.unmodifiable(List<int>.from(certificate)),
             )
             .toList(growable: false),
       ),
       trustAnchors = List<List<int>>.unmodifiable(
         trustAnchors
             .map(
               (certificate) =>
                   List<int>.unmodifiable(List<int>.from(certificate)),
             )
             .toList(growable: false),
       );

  /// Original compact JWS supplied to the loader.
  final String compact;

  /// ASCII signing input covered by the JWS signature.
  final String signingInput;

  /// Decoded protected JWS header.
  final Map<String, dynamic> header;

  /// UTF-8 bytes of the decoded payload.
  final List<int> payloadBytes;

  /// Decoded JWS signature bytes.
  final List<int> signatureBytes;

  /// DER certificates supplied by the JWS `x5c` header.
  final List<List<int>> certificateChain;

  /// DER trust anchors configured by the caller.
  final List<List<int>> trustAnchors;

  /// JWS algorithm named by the protected header.
  final String algorithm;

  /// Time at which the caller requested verification.
  final DateTime now;
}

/// Result of the application-supplied MDS JWS verifier.
final class FidoMetadataJwsVerificationResult {
  /// Creates a result indicating that signature and path verification passed.
  const FidoMetadataJwsVerificationResult.verified() : isVerified = true;

  /// Creates a result indicating that verification failed.
  const FidoMetadataJwsVerificationResult.rejected() : isVerified = false;

  /// Whether the application verifier accepted the JWS.
  final bool isVerified;
}

/// Generic public failure for malformed or untrusted metadata.
final class FidoMetadataException implements Exception {
  /// Creates the package's deliberately generic metadata failure.
  const FidoMetadataException();

  @override
  String toString() => 'FidoMetadataException(invalid metadata)';
}

/// Parses a caller-supplied compact MDS3 JWT after an explicit JWS check.
final class FidoMetadataBlobLoader {
  /// Creates a loader that authenticates blobs against [trustAnchors].
  ///
  /// [verifyJws] remains responsible for the cryptographic JWS and certificate
  /// path decision. The loader applies parsing, resource, freshness, and blob
  /// ordering checks around that callback.
  FidoMetadataBlobLoader({
    required Iterable<List<int>> trustAnchors,
    required this.verifyJws,
    this.limits = const FidoMetadataLimits(),
    this.nextUpdatePolicy = FidoMetadataNextUpdatePolicy.advisory,
  }) : _trustAnchors = _copyBoundedCertificates(
         trustAnchors,
         limits.maxCertificates,
         limits.maxCertificateBytes,
       );

  /// Callback used to authenticate each decoded JWS.
  final FidoMetadataJwsVerifier verifyJws;

  /// Resource bounds applied while parsing a blob.
  final FidoMetadataLimits limits;

  /// Policy used when an authenticated blob contains `nextUpdate`.
  final FidoMetadataNextUpdatePolicy nextUpdatePolicy;
  final List<List<int>> _trustAnchors;

  /// Loads a downloaded compact blob. No network or cache lookup occurs.
  Future<FidoMetadataBlob> load(
    String compact, {
    required DateTime now,
    int? previousBlobNumber,
    Duration clockSkew = Duration.zero,
  }) async {
    try {
      return await _load(
        compact,
        now: now,
        previousBlobNumber: previousBlobNumber,
        clockSkew: clockSkew,
      );
    } on FidoMetadataException {
      rethrow;
    } catch (_) {
      throw const FidoMetadataException();
    }
  }

  Future<FidoMetadataBlob> _load(
    String compact, {
    required DateTime now,
    required int? previousBlobNumber,
    required Duration clockSkew,
  }) async {
    if (compact.isEmpty || compact.length > limits.maxBlobBytes) {
      throw const FidoMetadataException();
    }
    if (previousBlobNumber != null && previousBlobNumber < 0) {
      throw const FidoMetadataException();
    }
    if (clockSkew.isNegative || clockSkew > const Duration(days: 1)) {
      throw const FidoMetadataException();
    }
    final nowUtc = _safeNow(now);
    if (!compact.codeUnits.every(_isAscii)) {
      throw const FidoMetadataException();
    }
    final segments = compact.split('.');
    if (segments.length != 3 || segments.any((segment) => segment.isEmpty)) {
      throw const FidoMetadataException();
    }
    if (segments.any((segment) => segment.length > limits.maxJwtSegmentBytes)) {
      throw const FidoMetadataException();
    }

    final headerText = _decodeBase64UrlJson(segments[0]);
    final payloadText = _decodeBase64UrlJson(segments[1]);
    final signatureBytes = _decodeBase64Url(segments[2]);
    if (signatureBytes.isEmpty) throw const FidoMetadataException();
    _scanJson(headerText, limits.maxJsonDepth);
    _scanJson(payloadText, limits.maxJsonDepth);
    final headerValue = jsonDecode(headerText);
    final payloadValue = jsonDecode(payloadText);
    if (headerValue is! Map || payloadValue is! Map) {
      throw const FidoMetadataException();
    }
    final header = Map<String, dynamic>.from(headerValue);
    final payload = Map<String, dynamic>.from(payloadValue);
    final algorithm = _parseAlgorithm(header['alg']);
    if (header.containsKey('typ') && header['typ'] != 'JWT') {
      throw const FidoMetadataException();
    }
    if (header.keys.any(
      const <String>{'x5u', 'jku', 'jwk', 'b64', 'crit', 'zip'}.contains,
    )) {
      // Remote keys, embedded keys, detached payloads, critical extensions,
      // and compression all alter JWS processing. This offline MDS profile
      // accepts only the compact, base64url-encoded form verified against the
      // caller's configured anchors.
      throw const FidoMetadataException();
    }
    final issuedAt = header.containsKey('iat')
        ? _parseIssuedAt(header['iat'], nowUtc, clockSkew)
        : null;
    final parsedCertificateChain = _parseX5c(header['x5c']);
    final certificateChain = parsedCertificateChain.isEmpty
        ? _trustAnchors
        : parsedCertificateChain;
    final payloadBytes = utf8.encode(payloadText);
    final input = FidoMetadataJwsVerificationInput._(
      compact: compact,
      signingInput: '${segments[0]}.${segments[1]}',
      header: Map<String, dynamic>.unmodifiable(header),
      payloadBytes: payloadBytes,
      signatureBytes: signatureBytes,
      certificateChain: certificateChain,
      trustAnchors: _trustAnchors,
      algorithm: algorithm,
      now: nowUtc,
    );
    final verification = await verifyJws(input);
    if (!verification.isVerified) throw const FidoMetadataException();

    final number = _parseBlobNumber(payload['no']);
    if (previousBlobNumber != null && number <= previousBlobNumber) {
      throw const FidoMetadataException();
    }
    final nextUpdate = payload.containsKey('nextUpdate')
        ? _parseIsoDate(payload['nextUpdate'])
        : null;
    _requiredBoundedString(
      payload['legalHeader'],
      maximum: limits.maxStringBytes,
    );
    if (nextUpdate != null) {
      final freshnessStart = issuedAt ?? nowUtc;
      if (issuedAt != null && !nextUpdate.isAfter(issuedAt)) {
        throw const FidoMetadataException();
      }
      if (nextUpdate.difference(freshnessStart) > limits.maxMetadataLifetime) {
        throw const FidoMetadataException();
      }
      if (nextUpdatePolicy ==
              FidoMetadataNextUpdatePolicy.requireFreshWhenPresent &&
          !nextUpdate.isAfter(nowUtc.subtract(clockSkew))) {
        throw const FidoMetadataException();
      }
    }
    final entriesValue = payload['entries'];
    if (entriesValue is! List || entriesValue.length > limits.maxEntries) {
      throw const FidoMetadataException();
    }
    final entries = <FidoMetadataEntry>[];
    final seenAaguids = <String>{};
    final seenAaids = <String>{};
    final seenKeyIdentifiers = <String>{};
    for (final value in entriesValue) {
      if (value is! Map) throw const FidoMetadataException();
      final entry = _parseEntry(
        Map<String, dynamic>.from(value),
        now: nowUtc,
        clockSkew: clockSkew,
        seenAaguids: seenAaguids,
        seenAaids: seenAaids,
        seenKeyIdentifiers: seenKeyIdentifiers,
      );
      entries.add(entry);
    }
    return FidoMetadataBlob._(
      number: number,
      verifiedAt: nowUtc,
      issuedAt: issuedAt,
      nextUpdate: nextUpdate,
      algorithm: algorithm,
      entries: entries,
    );
  }

  FidoMetadataEntry _parseEntry(
    Map<String, dynamic> value, {
    required DateTime now,
    required Duration clockSkew,
    required Set<String> seenAaguids,
    required Set<String> seenAaids,
    required Set<String> seenKeyIdentifiers,
  }) {
    final statementValue = value['metadataStatement'];
    final statusValue = value['statusReports'];
    if (statementValue is! Map || statusValue is! List) {
      throw const FidoMetadataException();
    }
    final statement = Map<String, dynamic>.from(statementValue);
    final entryAaguid = _optionalAaguid(value['aaguid']);
    final statementAaguid = _optionalAaguid(statement['aaguid']);
    if (entryAaguid != null &&
        statementAaguid != null &&
        entryAaguid != statementAaguid) {
      throw const FidoMetadataException();
    }
    final aaguid = entryAaguid ?? statementAaguid;
    if (aaguid != null && !seenAaguids.add(aaguid)) {
      throw const FidoMetadataException();
    }
    final entryKeys = _parseKeyIdentifiers(
      value['attestationCertificateKeyIdentifiers'],
    );
    final statementKeys = _parseKeyIdentifiers(
      statement['attestationCertificateKeyIdentifiers'],
    );
    final keys = <String>{...entryKeys, ...statementKeys}.toList();
    for (final key in keys) {
      if (!seenKeyIdentifiers.add(key)) throw const FidoMetadataException();
    }
    final aaid = _optionalAaid(value['aaid']);
    final statementAaid = _optionalAaid(statement['aaid']);
    if (aaid != null && statementAaid != null && aaid != statementAaid) {
      throw const FidoMetadataException();
    }
    final effectiveAaid = aaid ?? statementAaid;
    if (effectiveAaid != null && !seenAaids.add(effectiveAaid)) {
      throw const FidoMetadataException();
    }
    if (aaguid == null && effectiveAaid == null && keys.isEmpty) {
      throw const FidoMetadataException();
    }

    final schema = _requiredUnsigned(statement['schema'], maximum: 3);
    if (schema != 3) throw const FidoMetadataException();
    final description = _requiredBoundedString(
      statement['description'],
      maximum: 200,
    );
    final authenticatorVersion = _requiredUnsigned(
      statement['authenticatorVersion'],
      maximum: 0xffffffff,
    );
    final protocolFamily = _requiredBoundedString(
      statement['protocolFamily'],
      maximum: 16,
    );
    _requiredBoundedString(
      statement['legalHeader'],
      maximum: limits.maxStringBytes,
    );
    if (!const <String>{'uaf', 'u2f', 'fido2'}.contains(protocolFamily)) {
      throw const FidoMetadataException();
    }
    if (protocolFamily == 'fido2' && aaguid == null) {
      throw const FidoMetadataException();
    }
    if (protocolFamily == 'uaf' && effectiveAaid == null) {
      throw const FidoMetadataException();
    }
    final roots = _parseMetadataRoots(statement['attestationRootCertificates']);
    final reports = <FidoMetadataStatusReport>[];
    if (statusValue.isEmpty ||
        statusValue.length > limits.maxStatusReportsPerEntry) {
      throw const FidoMetadataException();
    }
    for (final reportValue in statusValue) {
      if (reportValue is! Map) throw const FidoMetadataException();
      reports.add(
        _parseStatusReport(
          Map<String, dynamic>.from(reportValue),
          now: now,
          clockSkew: clockSkew,
        ),
      );
    }
    final statusChange = _parseIsoDate(value['timeOfLastStatusChange']);
    if (statusChange.isAfter(now.add(clockSkew))) {
      throw const FidoMetadataException();
    }
    for (final report in reports) {
      if (report.effectiveDate != null &&
          report.effectiveDate!.isAfter(statusChange)) {
        throw const FidoMetadataException();
      }
    }
    return FidoMetadataEntry._(
      aaguid: aaguid,
      aaid: effectiveAaid,
      attestationCertificateKeyIdentifiers: keys,
      metadataStatement: FidoMetadataStatement._(
        schema: schema,
        description: description,
        authenticatorVersion: authenticatorVersion,
        protocolFamily: protocolFamily,
        aaguid: aaguid,
        aaid: effectiveAaid,
        attestationCertificateKeyIdentifiers: statementKeys,
        attestationRootCertificates: roots,
      ),
      statusReports: reports,
      timeOfLastStatusChange: statusChange,
    );
  }

  FidoMetadataStatusReport _parseStatusReport(
    Map<String, dynamic> value, {
    required DateTime now,
    required Duration clockSkew,
  }) {
    final rawStatus = value['status'];
    if (rawStatus is! String ||
        rawStatus.isEmpty ||
        utf8.encode(rawStatus).length > limits.maxStatusStringBytes) {
      throw const FidoMetadataException();
    }
    final effectiveDate = value.containsKey('effectiveDate')
        ? _parseIsoDate(value['effectiveDate'])
        : null;
    if (effectiveDate != null && effectiveDate.isAfter(now.add(clockSkew))) {
      throw const FidoMetadataException();
    }
    final version = value.containsKey('authenticatorVersion')
        ? _requiredUnsigned(value['authenticatorVersion'], maximum: 0xffffffff)
        : null;
    final certificateFingerprint = _parseStatusCertificate(
      value['certificate'],
    );
    final batchFingerprint = _parseStatusCertificate(value['batchCertificate']);
    final url = value.containsKey('url') ? _parseHttpsUrl(value['url']) : null;
    return FidoMetadataStatusReport._(
      status: _statusFromWire(rawStatus),
      rawStatus: rawStatus,
      effectiveDate: effectiveDate,
      authenticatorVersion: version,
      certificateSha256Fingerprint: certificateFingerprint,
      batchCertificateSha256Fingerprint: batchFingerprint,
      url: url,
    );
  }

  List<FidoMetadataCertificate> _parseMetadataRoots(Object? value) {
    if (value is! List ||
        value.isEmpty ||
        value.length > limits.maxCertificateRootsPerStatement) {
      throw const FidoMetadataException();
    }
    final roots = <FidoMetadataCertificate>[];
    final fingerprints = <String>{};
    for (final encoded in value) {
      final bytes = _decodeStandardBase64(encoded);
      _validateCertificate(bytes, maximumBytes: limits.maxCertificateBytes);
      final root = FidoMetadataCertificate._(bytes);
      if (!fingerprints.add(root.sha256Fingerprint)) {
        throw const FidoMetadataException();
      }
      roots.add(root);
    }
    return roots;
  }

  String? _parseStatusCertificate(Object? value) {
    if (value == null) return null;
    final bytes = _decodeStandardBase64(value);
    _validateCertificate(bytes, maximumBytes: limits.maxCertificateBytes);
    return crypto.sha256.convert(bytes).toString();
  }

  List<List<int>> _parseX5c(Object? value) {
    if (value == null) return const <List<int>>[];
    if (value is! List ||
        value.isEmpty ||
        value.length > limits.maxCertificates) {
      throw const FidoMetadataException();
    }
    final certificates = <List<int>>[];
    final fingerprints = <String>{};
    for (final encoded in value) {
      final bytes = _decodeStandardBase64(encoded);
      _validateCertificate(bytes, maximumBytes: limits.maxCertificateBytes);
      if (!fingerprints.add(crypto.sha256.convert(bytes).toString())) {
        throw const FidoMetadataException();
      }
      certificates.add(bytes);
    }
    return certificates;
  }

  String? _optionalAaguid(Object? value) {
    if (value == null) return null;
    if (value is! String || utf8.encode(value).length > limits.maxStringBytes) {
      throw const FidoMetadataException();
    }
    try {
      return normalizeFidoAaguid(value);
    } catch (_) {
      throw const FidoMetadataException();
    }
  }

  String? _optionalAaid(Object? value) {
    final aaid = _optionalBoundedString(value, limits.maxStringBytes);
    if (aaid == null) return null;
    if (!RegExp(r'^[0-9a-fA-F]{4}#[0-9a-fA-F]{4}$').hasMatch(aaid)) {
      throw const FidoMetadataException();
    }
    return aaid;
  }

  List<String> _parseKeyIdentifiers(Object? value) {
    if (value == null) return const <String>[];
    if (value is! List ||
        value.length > limits.maxCertificateRootsPerStatement) {
      throw const FidoMetadataException();
    }
    final keys = <String>{};
    for (final item in value) {
      if (item is! String ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(item) ||
          !keys.add(item)) {
        throw const FidoMetadataException();
      }
    }
    return keys.toList(growable: false);
  }

  String _requiredBoundedString(
    Object? value, {
    required int maximum,
    bool asciiOnly = false,
  }) {
    if (value is! String || value.isEmpty || value.length > maximum) {
      throw const FidoMetadataException();
    }
    if (utf8.encode(value).length > limits.maxStringBytes ||
        (asciiOnly && !value.codeUnits.every(_isAscii))) {
      throw const FidoMetadataException();
    }
    return value;
  }

  String? _optionalBoundedString(Object? value, int maximum) {
    if (value == null) return null;
    return _requiredBoundedString(value, maximum: maximum);
  }

  int _requiredUnsigned(Object? value, {required int maximum}) {
    if (value is! int || value < 0 || value > maximum) {
      throw const FidoMetadataException();
    }
    return value;
  }

  int _parseBlobNumber(Object? value) {
    final number = _requiredUnsigned(value, maximum: 9007199254740991);
    if (number == 0) throw const FidoMetadataException();
    return number;
  }
}

List<List<int>> _copyBoundedCertificates(
  Iterable<List<int>> values,
  int maximumCount,
  int maximumBytes,
) {
  final copied = <List<int>>[];
  final fingerprints = <String>{};
  for (final value in values) {
    if (copied.length >= maximumCount ||
        value.isEmpty ||
        value.length > maximumBytes) {
      throw ArgumentError('Invalid FIDO metadata trust anchors');
    }
    final bytes = List<int>.from(value);
    _validateCertificate(bytes, maximumBytes: maximumBytes);
    if (!fingerprints.add(crypto.sha256.convert(bytes).toString())) {
      throw ArgumentError('Invalid FIDO metadata trust anchors');
    }
    copied.add(List<int>.unmodifiable(bytes));
  }
  if (copied.isEmpty) {
    throw ArgumentError('Invalid FIDO metadata trust anchors');
  }
  return List<List<int>>.unmodifiable(copied);
}

String _decodeBase64UrlJson(String value) {
  final bytes = _decodeBase64Url(value);
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } catch (_) {
    throw const FidoMetadataException();
  }
}

List<int> _decodeBase64Url(String value) {
  if (value.contains('=') || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FidoMetadataException();
  }
  if (value.length % 4 == 1) throw const FidoMetadataException();
  try {
    final padded = '$value${'=' * ((4 - value.length % 4) % 4)}';
    return base64Url.decode(padded);
  } catch (_) {
    throw const FidoMetadataException();
  }
}

List<int> _decodeStandardBase64(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(value)) {
    throw const FidoMetadataException();
  }
  try {
    final bytes = base64.decode(value);
    if (base64.encode(bytes) != value) throw const FormatException();
    return bytes;
  } catch (_) {
    throw const FidoMetadataException();
  }
}

void _validateCertificate(List<int> bytes, {int maximumBytes = 16 * 1024}) {
  if (bytes.isEmpty || bytes.length > maximumBytes || bytes.first != 0x30) {
    throw const FidoMetadataException();
  }
  try {
    final parser = ASN1Parser(Uint8List.fromList(bytes));
    final object = parser.nextObject();
    if (parser.hasNext() || object is! ASN1Sequence) {
      throw const FormatException();
    }
    final elements = object.elements;
    if (elements == null || elements.length != 3) throw const FormatException();
    if (elements[0] is! ASN1Sequence ||
        elements[1] is! ASN1Sequence ||
        elements[2] is! ASN1BitString ||
        (elements[2] as ASN1BitString).unusedbits != 0) {
      throw const FormatException();
    }
    final tbs = elements[0] as ASN1Sequence;
    final tbsElements = tbs.elements;
    if (tbsElements == null || tbsElements.length < 6) {
      throw const FormatException();
    }
  } catch (_) {
    throw const FidoMetadataException();
  }
}

DateTime _safeNow(DateTime value) {
  final utc = value.toUtc();
  if (utc.year < 1970 || utc.year > 9999) throw const FidoMetadataException();
  return utc;
}

DateTime _parseIssuedAt(Object? value, DateTime now, Duration clockSkew) {
  if (value is! int || value < 0 || value > 253402300799) {
    throw const FidoMetadataException();
  }
  try {
    final issued = DateTime.fromMillisecondsSinceEpoch(
      value * 1000,
      isUtc: true,
    );
    if (issued.isAfter(now.add(clockSkew))) throw const FidoMetadataException();
    return issued;
  } catch (_) {
    throw const FidoMetadataException();
  }
}

DateTime _parseIsoDate(Object? value) {
  if (value is! String || value.isEmpty || value.length > 40) {
    throw const FidoMetadataException();
  }
  final dateOnly = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$');
  final dateTime = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T'
    r'([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?'
    r'(Z|[+-][0-9]{2}:[0-9]{2})$',
  );
  if (!dateOnly.hasMatch(value) && !dateTime.hasMatch(value)) {
    throw const FidoMetadataException();
  }
  try {
    final dateMatch =
        (dateOnly.firstMatch(value) ?? dateTime.firstMatch(value))!;
    final year = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw const FidoMetadataException();
    }
    final localDate = DateTime.utc(year, month, day);
    if (localDate.year != year ||
        localDate.month != month ||
        localDate.day != day) {
      throw const FidoMetadataException();
    }
    if (dateTime.hasMatch(value)) {
      final hour = int.parse(dateMatch.group(4)!);
      final minute = int.parse(dateMatch.group(5)!);
      final second = int.parse(dateMatch.group(6)!);
      if (hour > 23 || minute > 59 || second > 59) {
        throw const FidoMetadataException();
      }
      final zone = dateMatch.group(8)!;
      if (zone != 'Z') {
        final offsetHour = int.parse(zone.substring(1, 3));
        final offsetMinute = int.parse(zone.substring(4, 6));
        if (offsetHour > 23 || offsetMinute > 59) {
          throw const FidoMetadataException();
        }
      }
    }
    final parsed = dateOnly.hasMatch(value)
        ? localDate
        : DateTime.parse(value).toUtc();
    if (parsed.year < 1970 || parsed.year > 9999) {
      throw const FidoMetadataException();
    }
    if (dateOnly.hasMatch(value) &&
        (parsed.year != year || parsed.month != month || parsed.day != day)) {
      throw const FidoMetadataException();
    }
    return parsed;
  } catch (_) {
    throw const FidoMetadataException();
  }
}

Uri _parseHttpsUrl(Object? value) {
  if (value is! String || value.length > 2048) {
    throw const FidoMetadataException();
  }
  try {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException();
    }
    return uri;
  } catch (_) {
    throw const FidoMetadataException();
  }
}

FidoMetadataAuthenticatorStatus _statusFromWire(
  String value,
) => switch (value) {
  'NOT_FIDO_CERTIFIED' => FidoMetadataAuthenticatorStatus.notFidoCertified,
  'FIDO_CERTIFIED' => FidoMetadataAuthenticatorStatus.fidoCertified,
  'USER_VERIFICATION_BYPASS' =>
    FidoMetadataAuthenticatorStatus.userVerificationBypass,
  'ATTESTATION_KEY_COMPROMISE' =>
    FidoMetadataAuthenticatorStatus.attestationKeyCompromise,
  'USER_KEY_REMOTE_COMPROMISE' =>
    FidoMetadataAuthenticatorStatus.userKeyRemoteCompromise,
  'USER_KEY_PHYSICAL_COMPROMISE' =>
    FidoMetadataAuthenticatorStatus.userKeyPhysicalCompromise,
  'UPDATE_AVAILABLE' => FidoMetadataAuthenticatorStatus.updateAvailable,
  'RETIRED' => FidoMetadataAuthenticatorStatus.retired,
  'REVOKED' => FidoMetadataAuthenticatorStatus.revoked,
  'SELF_ASSERTION_SUBMITTED' =>
    FidoMetadataAuthenticatorStatus.selfAssertionSubmitted,
  'FIDO_CERTIFIED_L1' => FidoMetadataAuthenticatorStatus.fidoCertifiedL1,
  'FIDO_CERTIFIED_L1plus' =>
    FidoMetadataAuthenticatorStatus.fidoCertifiedL1Plus,
  'FIDO_CERTIFIED_L2' => FidoMetadataAuthenticatorStatus.fidoCertifiedL2,
  'FIDO_CERTIFIED_L2plus' =>
    FidoMetadataAuthenticatorStatus.fidoCertifiedL2Plus,
  'FIDO_CERTIFIED_L3' => FidoMetadataAuthenticatorStatus.fidoCertifiedL3,
  'FIDO_CERTIFIED_L3plus' =>
    FidoMetadataAuthenticatorStatus.fidoCertifiedL3Plus,
  'FIPS140_CERTIFIED_L1' => FidoMetadataAuthenticatorStatus.fips140CertifiedL1,
  'FIPS140_CERTIFIED_L2' => FidoMetadataAuthenticatorStatus.fips140CertifiedL2,
  'FIPS140_CERTIFIED_L3' => FidoMetadataAuthenticatorStatus.fips140CertifiedL3,
  'FIPS140_CERTIFIED_L4' => FidoMetadataAuthenticatorStatus.fips140CertifiedL4,
  _ => FidoMetadataAuthenticatorStatus.unknown,
};

String _parseAlgorithm(Object? value) {
  if (value is! String) throw const FidoMetadataException();
  return switch (value) {
    // These are the asymmetric algorithms implemented by the package's
    // existing crypto stack and accepted for this explicit verifier boundary.
    'ES256' || 'RS256' => value,
    _ => throw const FidoMetadataException(),
  };
}

bool _isAscii(int value) => value >= 0x20 && value <= 0x7e;

void _scanJson(String source, int maximumDepth) {
  try {
    final scanner = _JsonDuplicateScanner(source, maximumDepth);
    scanner.scan();
  } catch (_) {
    throw const FidoMetadataException();
  }
}

final class _JsonDuplicateScanner {
  _JsonDuplicateScanner(this.source, this.maximumDepth);

  final String source;
  final int maximumDepth;
  var index = 0;

  void scan() {
    _value(0);
    _whitespace();
    if (index != source.length) throw const FormatException();
  }

  void _value(int depth) {
    if (depth > maximumDepth || index >= source.length) {
      throw const FormatException();
    }
    switch (source.codeUnitAt(index)) {
      case 0x7b:
        _object(depth + 1);
      case 0x5b:
        _array(depth + 1);
      case 0x22:
        _string();
      case 0x74:
        _literal('true');
      case 0x66:
        _literal('false');
      case 0x6e:
        _literal('null');
      default:
        _number();
    }
  }

  void _object(int depth) {
    index++;
    final keys = <String>{};
    _whitespace();
    if (_take(0x7d)) return;
    while (true) {
      _whitespace();
      if (index >= source.length || source.codeUnitAt(index) != 0x22) {
        throw const FormatException();
      }
      final key = _string();
      if (!keys.add(key)) throw const FormatException();
      _whitespace();
      if (!_take(0x3a)) throw const FormatException();
      _value(depth);
      _whitespace();
      if (_take(0x7d)) return;
      if (!_take(0x2c)) throw const FormatException();
    }
  }

  void _array(int depth) {
    index++;
    _whitespace();
    if (_take(0x5d)) return;
    while (true) {
      _value(depth);
      _whitespace();
      if (_take(0x5d)) return;
      if (!_take(0x2c)) throw const FormatException();
    }
  }

  String _string() {
    final start = index;
    index++;
    while (index < source.length) {
      final code = source.codeUnitAt(index++);
      if (code == 0x22) {
        final decoded = jsonDecode(source.substring(start, index));
        if (decoded is! String) throw const FormatException();
        return decoded;
      }
      if (code < 0x20) throw const FormatException();
      if (code == 0x5c) {
        if (index >= source.length) throw const FormatException();
        final escape = source.codeUnitAt(index++);
        if (const <int>[
          0x22,
          0x5c,
          0x2f,
          0x62,
          0x66,
          0x6e,
          0x72,
          0x74,
        ].contains(escape)) {
          continue;
        }
        if (escape == 0x75) {
          if (index + 4 > source.length ||
              !RegExp(
                r'^[0-9A-Fa-f]{4}$',
              ).hasMatch(source.substring(index, index + 4))) {
            throw const FormatException();
          }
          index += 4;
          continue;
        }
        throw const FormatException();
      }
    }
    throw const FormatException();
  }

  void _literal(String literal) {
    if (!source.startsWith(literal, index)) throw const FormatException();
    index += literal.length;
  }

  void _number() {
    final start = index;
    if (_take(0x2d)) {}
    if (index >= source.length) throw const FormatException();
    if (source.codeUnitAt(index) == 0x30) {
      index++;
    } else {
      if (!_digit(source.codeUnitAt(index), nonZero: true)) {
        throw const FormatException();
      }
      while (index < source.length && _digit(source.codeUnitAt(index))) {
        index++;
      }
    }
    if (_take(0x2e)) {
      if (index >= source.length || !_digit(source.codeUnitAt(index))) {
        throw const FormatException();
      }
      while (index < source.length && _digit(source.codeUnitAt(index))) {
        index++;
      }
    }
    if (index < source.length &&
        (source.codeUnitAt(index) == 0x65 ||
            source.codeUnitAt(index) == 0x45)) {
      index++;
      if (index < source.length &&
          (source.codeUnitAt(index) == 0x2b ||
              source.codeUnitAt(index) == 0x2d)) {
        index++;
      }
      if (index >= source.length || !_digit(source.codeUnitAt(index))) {
        throw const FormatException();
      }
      while (index < source.length && _digit(source.codeUnitAt(index))) {
        index++;
      }
    }
    if (start == index) throw const FormatException();
  }

  bool _digit(int code, {bool nonZero = false}) =>
      code >= (nonZero ? 0x31 : 0x30) && code <= 0x39;

  void _whitespace() {
    while (index < source.length &&
        const <int>[
          0x20,
          0x09,
          0x0a,
          0x0d,
        ].contains(source.codeUnitAt(index))) {
      index++;
    }
  }

  bool _take(int code) {
    if (index < source.length && source.codeUnitAt(index) == code) {
      index++;
      return true;
    }
    return false;
  }
}

void _validateCertificateForKeyIdentifier(List<int> bytes) {
  _validateCertificate(bytes);
}

String _certificateKeyIdentifier(List<int> bytes) {
  _validateCertificateForKeyIdentifier(bytes);
  try {
    final parser = ASN1Parser(Uint8List.fromList(bytes));
    final certificate = parser.nextObject() as ASN1Sequence;
    final tbs = certificate.elements![0] as ASN1Sequence;
    final tbsElements = tbs.elements!;
    final offset = tbsElements.first.tag == 0xa0 ? 1 : 0;
    final spki = tbsElements[offset + 5] as ASN1Sequence;
    final key = spki.elements![1] as ASN1BitString;
    if (key.unusedbits != 0 || key.stringValues == null) {
      throw const FormatException();
    }
    return crypto.sha1.convert(key.stringValues!).toString();
  } catch (_) {
    throw const FidoMetadataException();
  }
}
