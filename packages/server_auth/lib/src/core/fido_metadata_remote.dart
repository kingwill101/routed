part of 'fido_metadata.dart';

/// Supplies the current time to metadata download and trust verification.
typedef FidoMetadataClock = DateTime Function();

/// Outcome required from an application-owned certificate revocation check.
enum FidoMetadataCertificateRevocationStatus { good, revoked, unknown }

/// Checks one verified certificate against application-owned revocation data.
///
/// The verifier calls this once for every non-anchor certificate in the
/// validated path. A result other than
/// [FidoMetadataCertificateRevocationStatus.good] rejects the metadata blob.
typedef FidoMetadataCertificateRevocationChecker =
    FutureOr<FidoMetadataCertificateRevocationStatus> Function(
      FidoMetadataCertificateRevocationInput input,
    );

/// Public certificate information supplied to a revocation checker.
final class FidoMetadataVerifiedCertificate {
  FidoMetadataVerifiedCertificate._(_FidoPkixCertificate certificate)
    : derBytes = List<int>.unmodifiable(certificate.derBytes),
      sha256Fingerprint = certificate.sha256Fingerprint,
      serialNumber = certificate.serialNumber,
      notBefore = certificate.notBefore,
      notAfter = certificate.notAfter,
      isCertificateAuthority = certificate.isCertificateAuthority,
      extendedKeyUsages = List<String>.unmodifiable(
        certificate.extendedKeyUsages,
      );

  /// Exact DER encoding of the certificate.
  final List<int> derBytes;

  /// Lowercase hexadecimal SHA-256 fingerprint of [derBytes].
  final String sha256Fingerprint;

  /// Positive X.509 certificate serial number.
  final BigInt serialNumber;
  final DateTime notBefore;
  final DateTime notAfter;
  final bool isCertificateAuthority;

  /// Extended-key-usage object identifiers, when the extension is present.
  final List<String> extendedKeyUsages;
}

/// One certificate and its issuer after local path and signature validation.
final class FidoMetadataCertificateRevocationInput {
  FidoMetadataCertificateRevocationInput._({
    required this.certificate,
    required this.issuer,
    required this.now,
  });

  final FidoMetadataVerifiedCertificate certificate;
  final FidoMetadataVerifiedCertificate issuer;
  final DateTime now;
}

/// Pinned trust and revocation dependencies for the built-in MDS verifier.
final class FidoMetadataPkixTrust {
  FidoMetadataPkixTrust({
    required Iterable<List<int>> trustAnchors,
    required this.checkRevocation,
    this.limits = const FidoMetadataLimits(),
  }) : _trustAnchors = _copyBoundedCertificates(
         trustAnchors,
         limits.maxCertificates,
         limits.maxCertificateBytes,
       );

  final FidoMetadataCertificateRevocationChecker checkRevocation;
  final FidoMetadataLimits limits;
  final List<List<int>> _trustAnchors;

  /// Immutable DER trust anchors used by both the loader and path verifier.
  List<List<int>> get trustAnchors => _trustAnchors;
}

/// Built-in ES256/RS256 JWS verifier with a strict, pinned PKIX path.
///
/// Certificate signatures, validity, names, CA constraints, key usage, path
/// length, the JWS signature, and exact trust-anchor termination are checked
/// locally. Revocation remains application-owned because servers commonly use
/// different CRL caches, proxies, and compliance stores; [FidoMetadataPkixTrust]
/// makes that decision explicit and fail-closed.
final class FidoMetadataJwsPkixVerifier {
  const FidoMetadataJwsPkixVerifier({required this.trust});

  final FidoMetadataPkixTrust trust;

  /// Verifies an input produced by [FidoMetadataBlobLoader].
  Future<FidoMetadataJwsVerificationResult> verify(
    FidoMetadataJwsVerificationInput input,
  ) async {
    try {
      if (!_sameCertificateSets(input.trustAnchors, trust._trustAnchors)) {
        return const FidoMetadataJwsVerificationResult.rejected();
      }
      final now = _safeNow(input.now);
      final supplied = input.certificateChain;
      if (supplied.isEmpty || supplied.length > trust.limits.maxCertificates) {
        return const FidoMetadataJwsVerificationResult.rejected();
      }
      final chain = supplied
          .map(
            (bytes) => _FidoPkixCertificate.parse(
              bytes,
              maximumBytes: trust.limits.maxCertificateBytes,
            ),
          )
          .toList(growable: true);
      if (chain.map((item) => item.sha256Fingerprint).toSet().length !=
          chain.length) {
        return const FidoMetadataJwsVerificationResult.rejected();
      }

      final anchor = await _completeAndVerifyPath(
        chain,
        anchors: trust._trustAnchors,
        maximumCertificates: trust.limits.maxCertificates,
        maximumBytes: trust.limits.maxCertificateBytes,
        now: now,
      );
      if (anchor == null) {
        return const FidoMetadataJwsVerificationResult.rejected();
      }

      for (var index = 0; index < chain.length - 1; index++) {
        final status = await trust.checkRevocation(
          FidoMetadataCertificateRevocationInput._(
            certificate: FidoMetadataVerifiedCertificate._(chain[index]),
            issuer: FidoMetadataVerifiedCertificate._(chain[index + 1]),
            now: now,
          ),
        );
        if (status != FidoMetadataCertificateRevocationStatus.good) {
          return const FidoMetadataJwsVerificationResult.rejected();
        }
      }

      final leaf = chain.first;
      final directlyPinned =
          chain.length == 1 &&
          leaf.sha256Fingerprint == anchor.sha256Fingerprint;
      if ((leaf.isCertificateAuthority && !directlyPinned) ||
          (leaf.keyUsagePresent && !leaf.digitalSignature) ||
          !_allowsMetadataSigning(leaf.extendedKeyUsages)) {
        return const FidoMetadataJwsVerificationResult.rejected();
      }
      final verified = switch (input.algorithm) {
        'ES256' => _verifyEs256Jws(
          leaf.publicKey,
          utf8.encode(input.signingInput),
          input.signatureBytes,
        ),
        'RS256' => _verifyRs256Jws(
          leaf.publicKey,
          utf8.encode(input.signingInput),
          input.signatureBytes,
        ),
        _ => false,
      };
      return verified
          ? const FidoMetadataJwsVerificationResult.verified()
          : const FidoMetadataJwsVerificationResult.rejected();
    } catch (_) {
      return const FidoMetadataJwsVerificationResult.rejected();
    }
  }
}

/// A bounded, single-hop HTTP GET request used by the MDS downloader.
final class FidoMetadataHttpRequest {
  FidoMetadataHttpRequest._({
    required this.uri,
    required Map<String, String> headers,
    required this.timeout,
    required this.maxResponseBytes,
    required this.maxResponseHeaderBytes,
  }) : headers = Map<String, String>.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
  final Duration timeout;
  final int maxResponseBytes;
  final int maxResponseHeaderBytes;
}

/// A bounded response returned by [FidoMetadataHttpTransport].
final class FidoMetadataHttpResponse {
  FidoMetadataHttpResponse({
    required this.statusCode,
    required Iterable<int> bodyBytes,
    Map<String, String> headers = const <String, String>{},
  }) : bodyBytes = _copyHttpResponseBody(bodyBytes),
       headers = _copyHttpResponseHeaders(headers);

  final int statusCode;
  final List<int> bodyBytes;
  final Map<String, String> headers;
}

List<int> _copyHttpResponseBody(Iterable<int> bodyBytes) {
  final copied = List<int>.from(bodyBytes);
  if (copied.any((byte) => byte < 0 || byte > 0xff)) {
    throw const FidoMetadataException();
  }
  return List<int>.unmodifiable(copied);
}

Map<String, String> _copyHttpResponseHeaders(Map<String, String> headers) {
  final copied = <String, String>{};
  for (final entry in headers.entries) {
    final name = entry.key.toLowerCase();
    if (copied.containsKey(name)) throw const FidoMetadataException();
    copied[name] = entry.value;
  }
  return Map<String, String>.unmodifiable(copied);
}

/// Injectable one-hop transport for deterministic tests and custom runtimes.
abstract interface class FidoMetadataHttpTransport {
  /// Uses `package:http` without following redirects automatically.
  factory FidoMetadataHttpTransport.packageHttp({http.Client? client}) =
      _PackageHttpFidoMetadataTransport;

  Future<FidoMetadataHttpResponse> get(FidoMetadataHttpRequest request);

  /// Releases resources owned by this transport.
  void close();
}

/// Security and resource bounds for remote MDS refreshes.
final class FidoMetadataDownloadPolicy {
  const FidoMetadataDownloadPolicy({
    this.maxRedirects = 3,
    this.perRequestTimeout = const Duration(seconds: 15),
    this.totalRefreshTimeout = const Duration(seconds: 30),
    this.maxResponseBytes = 32 * 1024 * 1024,
    this.maxResponseHeaderBytes = 16 * 1024,
    this.maxBlobAge = const Duration(days: 45),
    this.maxCachedAge = const Duration(days: 45),
    this.clockSkew = const Duration(minutes: 5),
  });

  /// Maximum number of same-origin HTTPS redirects followed per refresh.
  final int maxRedirects;

  /// One absolute budget for connect, headers, and the complete body of a hop.
  final Duration perRequestTimeout;

  /// Non-resetting budget for all hops, verification, and revocation checks.
  final Duration totalRefreshTimeout;
  final int maxResponseBytes;
  final int maxResponseHeaderBytes;

  /// Maximum age of a signed `iat` claim when one is present.
  final Duration maxBlobAge;

  /// Maximum local verification age accepted after an HTTP 304 response.
  final Duration maxCachedAge;
  final Duration clockSkew;
}

/// Result of a remote metadata refresh.
final class FidoMetadataRefreshResult {
  const FidoMetadataRefreshResult._({
    required this.blob,
    required this.wasDownloaded,
    required String cacheBinding,
    this.etag,
  }) : _cacheBinding = cacheBinding;

  final FidoMetadataBlob blob;
  final bool wasDownloaded;
  final String? etag;
  final String _cacheBinding;
}

/// Opt-in downloader for authenticated FIDO Metadata Service blobs.
///
/// The downloader streams one bounded response at a time, validates every
/// redirect itself, and composes [FidoMetadataJwsPkixVerifier] with the
/// existing offline [FidoMetadataBlobLoader]. No network access occurs until
/// [refresh] is called.
final class FidoMetadataDownloader {
  FidoMetadataDownloader({
    required this.trust,
    FidoMetadataHttpTransport? httpTransport,
    FidoMetadataClock? clock,
    Uri? source,
    this.policy = const FidoMetadataDownloadPolicy(),
  }) : source = source ?? officialSource,
       _clock = clock ?? _systemFidoMetadataClock,
       _transport = httpTransport ?? FidoMetadataHttpTransport.packageHttp(),
       _ownsTransport = httpTransport == null,
       _cacheBinding = _metadataCacheBinding(
         source ?? officialSource,
         trust._trustAnchors,
       ) {
    _validateDownloadPolicy(policy);
    _validateSource(this.source);
    if (policy.maxResponseBytes > trust.limits.maxBlobBytes) {
      throw ArgumentError.value(
        policy.maxResponseBytes,
        'policy.maxResponseBytes',
        'must not exceed FidoMetadataLimits.maxBlobBytes',
      );
    }
  }

  /// The well-known public FIDO Metadata Service endpoint.
  static final Uri officialSource = Uri.parse('https://mds.fidoalliance.org/');

  final FidoMetadataPkixTrust trust;
  final Uri source;
  final FidoMetadataDownloadPolicy policy;
  final FidoMetadataClock _clock;
  final FidoMetadataHttpTransport _transport;
  final bool _ownsTransport;
  final String _cacheBinding;

  /// Downloads and verifies a newer blob, or reuses a fresh cached blob after
  /// an authenticated HTTP 304 response.
  Future<FidoMetadataRefreshResult> refresh({
    FidoMetadataRefreshResult? previous,
  }) async {
    try {
      return await _refresh(
        previous: previous,
      ).timeout(policy.totalRefreshTimeout);
    } on FidoMetadataException {
      rethrow;
    } catch (_) {
      throw const FidoMetadataException();
    }
  }

  Future<FidoMetadataRefreshResult> _refresh({
    required FidoMetadataRefreshResult? previous,
  }) async {
    final now = _safeNow(_clock());
    if (previous != null && previous._cacheBinding != _cacheBinding) {
      throw const FidoMetadataException();
    }
    final previousBlob = previous?.blob;
    final conditionalEtag = _boundedEtag(previous?.etag);
    var current = previous == null
        ? source
        : source.replace(
            queryParameters: <String, String>{
              ...source.queryParameters,
              'localCopySerial': previousBlob!.number.toString(),
            },
          );
    final origin = _origin(source);
    var redirects = 0;
    while (true) {
      _validateSource(current);
      if (_origin(current) != origin) {
        throw const FidoMetadataException();
      }
      final response = await _transport
          .get(
            FidoMetadataHttpRequest._(
              uri: current,
              headers: <String, String>{
                'accept': 'application/jwt, application/octet-stream',
                'accept-encoding': 'identity',
                'if-none-match': ?conditionalEtag,
              },
              timeout: policy.perRequestTimeout,
              maxResponseBytes: policy.maxResponseBytes,
              maxResponseHeaderBytes: policy.maxResponseHeaderBytes,
            ),
          )
          .timeout(policy.perRequestTimeout);
      _validateResponseBounds(response, policy);

      if (_redirectStatusCodes.contains(response.statusCode)) {
        if (redirects++ == policy.maxRedirects ||
            response.bodyBytes.isNotEmpty) {
          throw const FidoMetadataException();
        }
        final location = response.headers['location'];
        if (location == null || location.isEmpty || location.length > 2048) {
          throw const FidoMetadataException();
        }
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode == 304) {
        if (previousBlob == null ||
            conditionalEtag == null ||
            response.bodyBytes.isNotEmpty) {
          throw const FidoMetadataException();
        }
        final responseEtag = _boundedEtag(response.headers['etag']);
        if (responseEtag != null && responseEtag != conditionalEtag) {
          throw const FidoMetadataException();
        }
        _requireFreshCachedBlob(previousBlob, now, policy);
        return FidoMetadataRefreshResult._(
          blob: previousBlob,
          wasDownloaded: false,
          cacheBinding: _cacheBinding,
          etag: responseEtag ?? conditionalEtag,
        );
      }
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw const FidoMetadataException();
      }
      _validateContentType(response.headers['content-type']);
      final compact = utf8.decode(response.bodyBytes, allowMalformed: false);
      final verifier = FidoMetadataJwsPkixVerifier(trust: trust);
      final blob =
          await FidoMetadataBlobLoader(
            trustAnchors: trust._trustAnchors,
            verifyJws: verifier.verify,
            limits: trust.limits,
            nextUpdatePolicy:
                FidoMetadataNextUpdatePolicy.requireFreshWhenPresent,
          ).load(
            compact,
            now: now,
            previousBlobNumber: previousBlob?.number,
            clockSkew: policy.clockSkew,
          );
      _requireFreshDownloadedBlob(blob, now, policy);
      return FidoMetadataRefreshResult._(
        blob: blob,
        wasDownloaded: true,
        cacheBinding: _cacheBinding,
        etag: _boundedEtag(response.headers['etag']),
      );
    }
  }

  /// Closes the default transport. Injected transports remain caller-owned.
  void close() {
    if (_ownsTransport) _transport.close();
  }
}

String _metadataCacheBinding(Uri source, List<List<int>> trustAnchors) => crypto
    .sha256
    .convert(
      utf8.encode(
        jsonEncode(<Object>[
          source.toString(),
          ...trustAnchors.map(
            (anchor) => crypto.sha256.convert(anchor).toString(),
          ),
        ]),
      ),
    )
    .toString();

final class _PackageHttpFidoMetadataTransport
    implements FidoMetadataHttpTransport {
  _PackageHttpFidoMetadataTransport({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<FidoMetadataHttpResponse> get(FidoMetadataHttpRequest request) async {
    return _get(request).timeout(request.timeout);
  }

  Future<FidoMetadataHttpResponse> _get(FidoMetadataHttpRequest request) async {
    final outgoing = http.Request('GET', request.uri)
      ..followRedirects = false
      ..headers.addAll(request.headers);
    final response = await _client.send(outgoing);
    var responseHeaderBytes = 0;
    for (final entry in response.headers.entries) {
      responseHeaderBytes +=
          utf8.encode(entry.key).length + utf8.encode(entry.value).length;
      if (responseHeaderBytes > request.maxResponseHeaderBytes) {
        throw const FidoMetadataException();
      }
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > request.maxResponseBytes) {
        throw const FidoMetadataException();
      }
      bytes.add(chunk);
    }
    return FidoMetadataHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: bytes.takeBytes(),
      headers: response.headers,
    );
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

const _redirectStatusCodes = <int>{301, 302, 303, 307, 308};

DateTime _systemFidoMetadataClock() => DateTime.now().toUtc();

void _validateDownloadPolicy(FidoMetadataDownloadPolicy value) {
  if (value.maxRedirects < 0 ||
      value.maxRedirects > 10 ||
      value.perRequestTimeout <= Duration.zero ||
      value.perRequestTimeout > const Duration(minutes: 2) ||
      value.totalRefreshTimeout <= Duration.zero ||
      value.totalRefreshTimeout > const Duration(minutes: 5) ||
      value.maxResponseBytes < 1024 ||
      value.maxResponseBytes > 64 * 1024 * 1024 ||
      value.maxResponseHeaderBytes < 256 ||
      value.maxResponseHeaderBytes > 64 * 1024 ||
      value.maxBlobAge <= Duration.zero ||
      value.maxBlobAge > const Duration(days: 366) ||
      value.maxCachedAge <= Duration.zero ||
      value.maxCachedAge > const Duration(days: 366) ||
      value.clockSkew.isNegative ||
      value.clockSkew > const Duration(days: 1)) {
    throw ArgumentError.value(value, 'policy', 'contains unsafe bounds');
  }
}

void _validateSource(Uri value) {
  if (!value.hasScheme ||
      value.scheme != 'https' ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.fragment.isNotEmpty ||
      value.toString().length > 2048) {
    throw ArgumentError('source must be a bounded HTTPS URL');
  }
}

String _origin(Uri value) {
  final defaultPort = value.scheme == 'https' ? 443 : 80;
  return '${value.scheme.toLowerCase()}://${value.host.toLowerCase()}:'
      '${value.hasPort ? value.port : defaultPort}';
}

void _validateResponseBounds(
  FidoMetadataHttpResponse response,
  FidoMetadataDownloadPolicy policy,
) {
  if (response.statusCode < 100 ||
      response.statusCode > 599 ||
      response.bodyBytes.length > policy.maxResponseBytes) {
    throw const FidoMetadataException();
  }
  var headerBytes = 0;
  for (final entry in response.headers.entries) {
    if (entry.key.isEmpty ||
        !_httpHeaderToken.hasMatch(entry.key) ||
        entry.value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw const FidoMetadataException();
    }
    headerBytes +=
        utf8.encode(entry.key).length + utf8.encode(entry.value).length;
    if (headerBytes > policy.maxResponseHeaderBytes) {
      throw const FidoMetadataException();
    }
  }
  final contentLength = response.headers['content-length'];
  if (contentLength != null) {
    final parsed = int.tryParse(contentLength);
    if (parsed == null ||
        parsed < 0 ||
        parsed > policy.maxResponseBytes ||
        parsed != response.bodyBytes.length) {
      throw const FidoMetadataException();
    }
  }
}

final _httpHeaderToken = RegExp(r"^[!#$%&'*+.^_`|~0-9a-z-]+$");

void _validateContentType(String? value) {
  if (value == null) return;
  final mediaType = value.split(';').first.trim().toLowerCase();
  if (!const <String>{
    'application/jwt',
    'application/octet-stream',
    'text/plain',
  }.contains(mediaType)) {
    throw const FidoMetadataException();
  }
}

String? _boundedEtag(String? value) {
  if (value == null) return null;
  if (value.isEmpty ||
      value.length > 256 ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw const FidoMetadataException();
  }
  return value;
}

void _requireFreshDownloadedBlob(
  FidoMetadataBlob blob,
  DateTime now,
  FidoMetadataDownloadPolicy policy,
) {
  final issuedAt = blob.issuedAt;
  if (issuedAt == null && blob.nextUpdate == null) {
    throw const FidoMetadataException();
  }
  if (issuedAt != null &&
      now.difference(issuedAt) > policy.maxBlobAge + policy.clockSkew) {
    throw const FidoMetadataException();
  }
}

void _requireFreshCachedBlob(
  FidoMetadataBlob blob,
  DateTime now,
  FidoMetadataDownloadPolicy policy,
) {
  if (blob.verifiedAt.isAfter(now.add(policy.clockSkew))) {
    throw const FidoMetadataException();
  }
  if (now.difference(blob.verifiedAt) >
      policy.maxCachedAge + policy.clockSkew) {
    throw const FidoMetadataException();
  }
  if (blob.nextUpdate != null &&
      !blob.nextUpdate!.isAfter(now.subtract(policy.clockSkew))) {
    throw const FidoMetadataException();
  }
  _requireFreshDownloadedBlob(blob, now, policy);
}

bool _sameCertificateSets(List<List<int>> left, List<List<int>> right) {
  if (left.length != right.length) return false;
  final leftFingerprints = left
      .map((item) => crypto.sha256.convert(item).toString())
      .toSet();
  final rightFingerprints = right
      .map((item) => crypto.sha256.convert(item).toString())
      .toSet();
  return leftFingerprints.length == left.length &&
      rightFingerprints.length == right.length &&
      leftFingerprints.containsAll(rightFingerprints);
}

Future<_FidoPkixCertificate?> _completeAndVerifyPath(
  List<_FidoPkixCertificate> chain, {
  required List<List<int>> anchors,
  required int maximumCertificates,
  required int maximumBytes,
  required DateTime now,
}) async {
  for (final certificate in chain) {
    if (now.isBefore(certificate.notBefore) ||
        now.isAfter(certificate.notAfter)) {
      return null;
    }
  }
  final parsedAnchors = anchors
      .map(
        (bytes) =>
            _FidoPkixCertificate.parse(bytes, maximumBytes: maximumBytes),
      )
      .toList(growable: false);
  _FidoPkixCertificate? anchor;
  final last = chain.last;
  for (final candidate in parsedAnchors) {
    if (now.isBefore(candidate.notBefore) ||
        now.isAfter(candidate.notAfter) ||
        !candidate.isCertificateAuthority ||
        (candidate.keyUsagePresent && !candidate.keyCertSign)) {
      continue;
    }
    if (candidate.sha256Fingerprint == last.sha256Fingerprint) {
      anchor = candidate;
      break;
    }
    if (_fidoBytesEqual(last.issuerDer, candidate.subjectDer) &&
        await _verifyCertificateSignature(last, candidate.publicKey)) {
      if (chain.length == maximumCertificates) return null;
      anchor = candidate;
      chain.add(candidate);
      break;
    }
  }
  if (anchor == null) return null;

  for (var index = 0; index < chain.length - 1; index++) {
    final certificate = chain[index];
    final issuer = chain[index + 1];
    if (!_fidoBytesEqual(certificate.issuerDer, issuer.subjectDer) ||
        !issuer.isCertificateAuthority ||
        (index + 1 < chain.length - 1 && !issuer.basicConstraintsCritical) ||
        (issuer.keyUsagePresent && !issuer.keyCertSign) ||
        (index + 1 < chain.length - 1 &&
            !_allowsMetadataSigning(issuer.extendedKeyUsages)) ||
        !await _verifyCertificateSignature(certificate, issuer.publicKey)) {
      return null;
    }
    var caCertificatesBelowIssuer = 0;
    for (var below = 1; below <= index; below++) {
      final candidate = chain[below];
      if (candidate.isCertificateAuthority &&
          !_fidoBytesEqual(candidate.subjectDer, candidate.issuerDer)) {
        caCertificatesBelowIssuer++;
      }
    }
    if (issuer.pathLengthConstraint != null &&
        caCertificatesBelowIssuer > issuer.pathLengthConstraint!) {
      return null;
    }
  }
  return anchor;
}

final class _FidoPkixCertificate {
  _FidoPkixCertificate({
    required this.derBytes,
    required this.tbsBytes,
    required this.signature,
    required this.signatureAlgorithm,
    required this.serialNumber,
    required this.issuerDer,
    required this.subjectDer,
    required this.notBefore,
    required this.notAfter,
    required this.publicKey,
    required this.isCertificateAuthority,
    required this.basicConstraintsCritical,
    required this.pathLengthConstraint,
    required this.keyUsagePresent,
    required this.digitalSignature,
    required this.keyCertSign,
    required this.extendedKeyUsages,
  }) : sha256Fingerprint = crypto.sha256.convert(derBytes).toString();

  factory _FidoPkixCertificate.parse(
    List<int> bytes, {
    required int maximumBytes,
  }) {
    _validateCertificate(bytes, maximumBytes: maximumBytes);
    final der = Uint8List.fromList(bytes);
    final parser = ASN1Parser(der);
    final certificate = parser.nextObject() as ASN1Sequence;
    if (parser.hasNext() || !_fidoBytesEqual(certificate.encode(), der)) {
      throw const FormatException();
    }
    final certificateElements = certificate.elements!;
    final tbs = certificateElements[0] as ASN1Sequence;
    final outerAlgorithm = certificateElements[1] as ASN1Sequence;
    final signatureValue = certificateElements[2] as ASN1BitString;
    final elements = tbs.elements!;
    if (elements.isEmpty || elements.first.tag != 0xa0) {
      throw const FormatException();
    }
    final versionParser = ASN1Parser(elements.first.valueBytes);
    final version = versionParser.nextObject();
    if (versionParser.hasNext() ||
        version is! ASN1Integer ||
        version.integer != BigInt.two) {
      throw const FormatException();
    }
    const offset = 1;
    if (elements.length < offset + 6 ||
        elements[offset] is! ASN1Integer ||
        elements[offset + 1] is! ASN1Sequence ||
        elements[offset + 2] is! ASN1Sequence ||
        elements[offset + 3] is! ASN1Sequence ||
        elements[offset + 4] is! ASN1Sequence ||
        elements[offset + 5] is! ASN1Sequence ||
        signatureValue.unusedbits != 0 ||
        signatureValue.stringValues == null) {
      throw const FormatException();
    }
    final serial = (elements[offset] as ASN1Integer).integer;
    if (serial == null || serial <= BigInt.zero || serial.bitLength > 160) {
      throw const FormatException();
    }
    final innerAlgorithm = elements[offset + 1] as ASN1Sequence;
    if (!_fidoBytesEqual(innerAlgorithm.encode(), outerAlgorithm.encode())) {
      throw const FormatException();
    }
    final algorithm = _parseCertificateSignatureAlgorithm(outerAlgorithm);
    final issuer = elements[offset + 2] as ASN1Sequence;
    final subject = elements[offset + 4] as ASN1Sequence;
    if (issuer.elements == null ||
        issuer.elements!.isEmpty ||
        subject.elements == null ||
        subject.elements!.isEmpty) {
      throw const FormatException();
    }
    final validity = _parseCertificateValidity(
      elements[offset + 3] as ASN1Sequence,
    );
    final publicKey = _parseCertificatePublicKey(
      elements[offset + 5] as ASN1Sequence,
    );
    var isCa = false;
    var basicConstraintsCritical = false;
    int? pathLength;
    var keyUsagePresent = false;
    var digitalSignature = false;
    var keyCertSign = false;
    var extendedKeyUsages = const <String>[];
    final seenExtensions = <String>{};
    var sawExtensions = false;
    for (final optional in elements.skip(offset + 6)) {
      if (optional.tag != 0xa3 || sawExtensions) {
        throw const FormatException();
      }
      sawExtensions = true;
      final extensionParser = ASN1Parser(optional.valueBytes);
      final extensionSequence = extensionParser.nextObject();
      if (extensionParser.hasNext() || extensionSequence is! ASN1Sequence) {
        throw const FormatException();
      }
      for (final rawExtension
          in extensionSequence.elements ?? const <ASN1Object>[]) {
        if (rawExtension is! ASN1Sequence) throw const FormatException();
        final extension = rawExtension.elements;
        if (extension == null ||
            extension.length < 2 ||
            extension.length > 3 ||
            extension.first is! ASN1ObjectIdentifier ||
            extension.last is! ASN1OctetString) {
          throw const FormatException();
        }
        final oid =
            (extension.first as ASN1ObjectIdentifier).objectIdentifierAsString;
        if (oid == null || !seenExtensions.add(oid)) {
          throw const FormatException();
        }
        final critical = extension.length == 3;
        if (critical &&
            (extension[1] is! ASN1Boolean ||
                (extension[1] as ASN1Boolean).boolValue != true)) {
          throw const FormatException();
        }
        final valueBytes = (extension.last as ASN1OctetString).octets;
        if (valueBytes == null) throw const FormatException();
        if (oid == '2.5.29.19') {
          basicConstraintsCritical = critical;
          final constraintsParser = ASN1Parser(valueBytes);
          final constraints = constraintsParser.nextObject();
          if (constraintsParser.hasNext() || constraints is! ASN1Sequence) {
            throw const FormatException();
          }
          final values = constraints.elements ?? const <ASN1Object>[];
          var valueIndex = 0;
          if (values.isNotEmpty && values.first is ASN1Boolean) {
            isCa = (values.first as ASN1Boolean).boolValue == true;
            valueIndex++;
          }
          if (valueIndex < values.length) {
            final path = values[valueIndex];
            if (path is! ASN1Integer ||
                path.integer == null ||
                path.integer! < BigInt.zero ||
                path.integer!.bitLength > 31) {
              throw const FormatException();
            }
            pathLength = path.integer!.toInt();
            valueIndex++;
          }
          if (valueIndex != values.length || (!isCa && pathLength != null)) {
            throw const FormatException();
          }
        } else if (oid == '2.5.29.15') {
          final usageParser = ASN1Parser(valueBytes);
          final usage = usageParser.nextObject();
          if (usageParser.hasNext() ||
              usage is! ASN1BitString ||
              usage.stringValues == null ||
              usage.stringValues!.isEmpty ||
              usage.unusedbits == null ||
              usage.unusedbits! < 0 ||
              usage.unusedbits! > 7 ||
              (usage.stringValues!.last & ((1 << usage.unusedbits!) - 1)) !=
                  0) {
            throw const FormatException();
          }
          keyUsagePresent = true;
          digitalSignature = usage.stringValues!.first & 0x80 != 0;
          keyCertSign = usage.stringValues!.first & 0x04 != 0;
        } else if (oid == '2.5.29.37') {
          final usagesParser = ASN1Parser(valueBytes);
          final usages = usagesParser.nextObject();
          if (usagesParser.hasNext() ||
              usages is! ASN1Sequence ||
              usages.elements == null ||
              usages.elements!.isEmpty) {
            throw const FormatException();
          }
          final parsedUsages = <String>{};
          for (final usage in usages.elements!) {
            if (usage is! ASN1ObjectIdentifier) {
              throw const FormatException();
            }
            final identifier = usage.objectIdentifierAsString;
            if (identifier == null || !parsedUsages.add(identifier)) {
              throw const FormatException();
            }
          }
          extendedKeyUsages = List<String>.unmodifiable(parsedUsages);
        } else if (critical) {
          throw const FormatException();
        }
      }
    }
    return _FidoPkixCertificate(
      derBytes: der,
      tbsBytes: Uint8List.fromList(tbs.encode()),
      signature: Uint8List.fromList(signatureValue.stringValues!),
      signatureAlgorithm: algorithm,
      serialNumber: serial,
      issuerDer: Uint8List.fromList(issuer.encode()),
      subjectDer: Uint8List.fromList(subject.encode()),
      notBefore: validity.$1,
      notAfter: validity.$2,
      publicKey: publicKey,
      isCertificateAuthority: isCa,
      basicConstraintsCritical: basicConstraintsCritical,
      pathLengthConstraint: pathLength,
      keyUsagePresent: keyUsagePresent,
      digitalSignature: digitalSignature,
      keyCertSign: keyCertSign,
      extendedKeyUsages: extendedKeyUsages,
    );
  }

  final Uint8List derBytes;
  final Uint8List tbsBytes;
  final Uint8List signature;
  final _FidoSignatureAlgorithm signatureAlgorithm;
  final String sha256Fingerprint;
  final BigInt serialNumber;
  final Uint8List issuerDer;
  final Uint8List subjectDer;
  final DateTime notBefore;
  final DateTime notAfter;
  final _FidoPublicKey publicKey;
  final bool isCertificateAuthority;
  final bool basicConstraintsCritical;
  final int? pathLengthConstraint;
  final bool keyUsagePresent;
  final bool digitalSignature;
  final bool keyCertSign;
  final List<String> extendedKeyUsages;
}

const _metadataSigningExtendedKeyUsages = <String>{
  // anyExtendedKeyUsage
  '2.5.29.37.0',
  // serverAuth and clientAuth are present on the current official MDS signer.
  '1.3.6.1.5.5.7.3.1',
  '1.3.6.1.5.5.7.3.2',
  // codeSigning is the conventional signed-object purpose.
  '1.3.6.1.5.5.7.3.3',
};

bool _allowsMetadataSigning(List<String> usages) =>
    usages.isEmpty || usages.any(_metadataSigningExtendedKeyUsages.contains);

enum _FidoSignatureAlgorithm { es256, rsaSha256, rsaSha384, rsaSha512 }

_FidoSignatureAlgorithm _parseCertificateSignatureAlgorithm(
  ASN1Sequence value,
) {
  final elements = value.elements;
  if (elements == null ||
      elements.isEmpty ||
      elements.length > 2 ||
      elements.first is! ASN1ObjectIdentifier) {
    throw const FormatException();
  }
  final oid = (elements.first as ASN1ObjectIdentifier).objectIdentifierAsString;
  return switch (oid) {
    '1.2.840.10045.4.3.2' when elements.length == 1 =>
      _FidoSignatureAlgorithm.es256,
    '1.2.840.113549.1.1.11'
        when elements.length == 1 || elements[1] is ASN1Null =>
      _FidoSignatureAlgorithm.rsaSha256,
    '1.2.840.113549.1.1.12'
        when elements.length == 1 || elements[1] is ASN1Null =>
      _FidoSignatureAlgorithm.rsaSha384,
    '1.2.840.113549.1.1.13'
        when elements.length == 1 || elements[1] is ASN1Null =>
      _FidoSignatureAlgorithm.rsaSha512,
    _ => throw const FormatException(),
  };
}

(DateTime, DateTime) _parseCertificateValidity(ASN1Sequence value) {
  final elements = value.elements;
  if (elements == null || elements.length != 2) {
    throw const FormatException();
  }
  DateTime? parse(ASN1Object item) => switch (item) {
    ASN1UtcTime() => item.time?.toUtc(),
    ASN1GeneralizedTime() => item.dateTimeValue?.toUtc(),
    _ => null,
  };
  final notBefore = parse(elements[0]);
  final notAfter = parse(elements[1]);
  if (notBefore == null || notAfter == null || !notAfter.isAfter(notBefore)) {
    throw const FormatException();
  }
  return (notBefore, notAfter);
}

final class _FidoPublicKey {
  const _FidoPublicKey.ec(this.x, this.y) : modulus = null, exponent = null;

  const _FidoPublicKey.rsa(this.modulus, this.exponent) : x = null, y = null;

  final Uint8List? x;
  final Uint8List? y;
  final Uint8List? modulus;
  final Uint8List? exponent;
}

_FidoPublicKey _parseCertificatePublicKey(ASN1Sequence value) {
  final elements = value.elements;
  if (elements == null ||
      elements.length != 2 ||
      elements.first is! ASN1Sequence ||
      elements[1] is! ASN1BitString) {
    throw const FormatException();
  }
  final algorithm = (elements.first as ASN1Sequence).elements;
  final bits = elements[1] as ASN1BitString;
  if (algorithm == null ||
      algorithm.isEmpty ||
      algorithm.first is! ASN1ObjectIdentifier ||
      bits.unusedbits != 0 ||
      bits.stringValues == null) {
    throw const FormatException();
  }
  final oid =
      (algorithm.first as ASN1ObjectIdentifier).objectIdentifierAsString;
  final keyBytes = bits.stringValues!;
  if (oid == '1.2.840.10045.2.1') {
    if (algorithm.length != 2 ||
        algorithm[1] is! ASN1ObjectIdentifier ||
        (algorithm[1] as ASN1ObjectIdentifier).objectIdentifierAsString !=
            '1.2.840.10045.3.1.7' ||
        keyBytes.length != 65 ||
        keyBytes.first != 0x04) {
      throw const FormatException();
    }
    return _FidoPublicKey.ec(
      Uint8List.fromList(keyBytes.sublist(1, 33)),
      Uint8List.fromList(keyBytes.sublist(33)),
    );
  }
  if (oid == '1.2.840.113549.1.1.1') {
    if (algorithm.length > 2 ||
        (algorithm.length == 2 && algorithm[1] is! ASN1Null)) {
      throw const FormatException();
    }
    final parser = ASN1Parser(Uint8List.fromList(keyBytes));
    final sequence = parser.nextObject();
    if (parser.hasNext() ||
        sequence is! ASN1Sequence ||
        sequence.elements?.length != 2 ||
        sequence.elements![0] is! ASN1Integer ||
        sequence.elements![1] is! ASN1Integer) {
      throw const FormatException();
    }
    final modulus = (sequence.elements![0] as ASN1Integer).integer;
    final exponent = (sequence.elements![1] as ASN1Integer).integer;
    if (modulus == null ||
        exponent == null ||
        modulus.bitLength < 2048 ||
        modulus.bitLength > 8192 ||
        exponent < BigInt.from(3) ||
        exponent.isEven ||
        exponent.bitLength > 64) {
      throw const FormatException();
    }
    return _FidoPublicKey.rsa(
      _unsignedBigIntBytes(modulus),
      _unsignedBigIntBytes(exponent),
    );
  }
  throw const FormatException();
}

Future<bool> _verifyCertificateSignature(
  _FidoPkixCertificate certificate,
  _FidoPublicKey issuer,
) async {
  return switch (certificate.signatureAlgorithm) {
    _FidoSignatureAlgorithm.es256 => _verifyEs256Der(
      issuer,
      certificate.tbsBytes,
      certificate.signature,
      pc.SHA256Digest(),
    ),
    _FidoSignatureAlgorithm.rsaSha256 => _verifyRsa(
      issuer,
      certificate.tbsBytes,
      certificate.signature,
      pc.SHA256Digest(),
      '0609608648016503040201',
    ),
    _FidoSignatureAlgorithm.rsaSha384 => _verifyRsa(
      issuer,
      certificate.tbsBytes,
      certificate.signature,
      pc.SHA384Digest(),
      '0609608648016503040202',
    ),
    _FidoSignatureAlgorithm.rsaSha512 => _verifyRsa(
      issuer,
      certificate.tbsBytes,
      certificate.signature,
      pc.SHA512Digest(),
      '0609608648016503040203',
    ),
  };
}

bool _verifyEs256Jws(
  _FidoPublicKey key,
  List<int> message,
  List<int> signature,
) {
  if (signature.length != 64) return false;
  final parameters = pc.ECDomainParameters('secp256r1');
  final r = _bytesToUnsignedBigInt(signature.sublist(0, 32));
  final s = _bytesToUnsignedBigInt(signature.sublist(32));
  if (r <= BigInt.zero ||
      s <= BigInt.zero ||
      r >= parameters.n ||
      s >= parameters.n) {
    return false;
  }
  return _verifyEcSignature(
    key,
    message,
    pc.ECSignature(r, s),
    pc.SHA256Digest(),
  );
}

bool _verifyEs256Der(
  _FidoPublicKey key,
  List<int> message,
  List<int> signature,
  pc.Digest digest,
) {
  try {
    final parser = ASN1Parser(Uint8List.fromList(signature));
    final sequence = parser.nextObject();
    if (parser.hasNext() ||
        sequence is! ASN1Sequence ||
        sequence.elements?.length != 2 ||
        sequence.elements![0] is! ASN1Integer ||
        sequence.elements![1] is! ASN1Integer) {
      return false;
    }
    final r = (sequence.elements![0] as ASN1Integer).integer;
    final s = (sequence.elements![1] as ASN1Integer).integer;
    if (r == null || s == null) return false;
    return _verifyEcSignature(key, message, pc.ECSignature(r, s), digest);
  } catch (_) {
    return false;
  }
}

bool _verifyEcSignature(
  _FidoPublicKey key,
  List<int> message,
  pc.ECSignature signature,
  pc.Digest digest,
) {
  try {
    final x = key.x;
    final y = key.y;
    if (x == null || y == null) return false;
    final parameters = pc.ECDomainParameters('secp256r1');
    if (signature.r <= BigInt.zero ||
        signature.s <= BigInt.zero ||
        signature.r >= parameters.n ||
        signature.s >= parameters.n) {
      return false;
    }
    final point = parameters.curve.decodePoint(<int>[0x04, ...x, ...y]);
    if (point == null || point.isInfinity) return false;
    final subgroupCheck = point * parameters.n;
    if (subgroupCheck == null || !subgroupCheck.isInfinity) return false;
    final verifier = pc.ECDSASigner(digest)
      ..init(
        false,
        pc.PublicKeyParameter<pc.ECPublicKey>(
          pc.ECPublicKey(point, parameters),
        ),
      );
    return verifier.verifySignature(Uint8List.fromList(message), signature);
  } catch (_) {
    return false;
  }
}

bool _verifyRs256Jws(
  _FidoPublicKey key,
  List<int> message,
  List<int> signature,
) => _verifyRsa(
  key,
  message,
  signature,
  pc.SHA256Digest(),
  '0609608648016503040201',
);

bool _verifyRsa(
  _FidoPublicKey key,
  List<int> message,
  List<int> signature,
  pc.Digest digest,
  String digestIdentifier,
) {
  try {
    final modulus = key.modulus;
    final exponent = key.exponent;
    if (modulus == null ||
        exponent == null ||
        signature.length != modulus.length) {
      return false;
    }
    final verifier = pc.RSASigner(digest, digestIdentifier)
      ..init(
        false,
        pc.PublicKeyParameter<pc.RSAPublicKey>(
          pc.RSAPublicKey(
            _bytesToUnsignedBigInt(modulus),
            _bytesToUnsignedBigInt(exponent),
          ),
        ),
      );
    return verifier.verifySignature(
      Uint8List.fromList(message),
      pc.RSASignature(Uint8List.fromList(signature)),
    );
  } catch (_) {
    return false;
  }
}

BigInt _bytesToUnsignedBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

Uint8List _unsignedBigIntBytes(BigInt value) {
  if (value <= BigInt.zero) throw const FormatException();
  final bytes = <int>[];
  var remaining = value;
  while (remaining > BigInt.zero) {
    bytes.add((remaining & BigInt.from(0xff)).toInt());
    remaining >>= 8;
  }
  return Uint8List.fromList(bytes.reversed.toList(growable: false));
}

bool _fidoBytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
