import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../deployed_worker_auth_protocol.dart';

export '../deployed_worker_auth_protocol.dart';

/// Validated inputs for one explicitly enabled deployed Worker run.
final class DeployedWorkerAuthConformanceConfig {
  DeployedWorkerAuthConformanceConfig({
    required Uri workerOrigin,
    required String token,
    this.timeout = const Duration(seconds: 45),
    List<DeployedWorkerAuthSuite> suites = DeployedWorkerAuthSuite.values,
  }) : workerOrigin = validateDeployedWorkerOrigin(workerOrigin),
       token = validateDeployedWorkerToken(token),
       suites = List<DeployedWorkerAuthSuite>.unmodifiable(suites) {
    if (timeout < const Duration(seconds: 1) ||
        timeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'must be between 1 second and 5 minutes',
      );
    }
    if (this.suites.isEmpty) {
      throw ArgumentError.value(suites, 'suites', 'must not be empty');
    }
    if (this.suites.toSet().length != this.suites.length) {
      throw ArgumentError.value(
        suites,
        'suites',
        'must not contain duplicates',
      );
    }
  }

  final Uri workerOrigin;
  final String token;
  final Duration timeout;
  final List<DeployedWorkerAuthSuite> suites;
}

Uri validateDeployedWorkerOrigin(Uri value) {
  if (value.scheme != 'https' ||
      value.host.isEmpty ||
      value.hasPort && value.port != 443 ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw ArgumentError.value(
      '<redacted>',
      'workerOrigin',
      'must be an HTTPS origin without credentials, a custom port, path, '
          'query, or fragment',
    );
  }
  return value.replace(path: '/');
}

/// Parses and validates an HTTPS Worker origin without exposing credentials.
Uri parseDeployedWorkerOrigin(String value) {
  if (value.isEmpty ||
      value.length > 2048 ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw ArgumentError.value(
      '<redacted>',
      'workerOrigin',
      'must be a non-empty HTTPS origin without controls',
    );
  }
  final parsed = Uri.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(
      '<redacted>',
      'workerOrigin',
      'must be a valid HTTPS origin',
    );
  }
  return validateDeployedWorkerOrigin(parsed);
}

String validateDeployedWorkerToken(String value) {
  if (value.isEmpty ||
      value.length > 4096 ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw ArgumentError.value(
      '<redacted>',
      'token',
      'must be non-empty, at most 4096 characters, and contain no controls',
    );
  }
  return value;
}

final class DeployedWorkerAuthSuiteResult {
  const DeployedWorkerAuthSuiteResult({
    required this.suite,
    required this.passed,
    this.caseId,
    this.errorCode,
  });

  final DeployedWorkerAuthSuite suite;
  final bool passed;
  final String? caseId;
  final String? errorCode;
}

final class DeployedWorkerAuthConformanceReport {
  const DeployedWorkerAuthConformanceReport(this.results);

  final List<DeployedWorkerAuthSuiteResult> results;
  bool get passed => results.every((result) => result.passed);
}

abstract interface class DeployedWorkerAuthConformanceRunner {
  Future<DeployedWorkerAuthConformanceReport> run();

  void close();
}

typedef DeployedWorkerHttpClientFactory = HttpClient Function();

/// Calls an already-deployed Worker. It never invokes Wrangler or a
/// Cloudflare control-plane API.
final class HttpDeployedWorkerAuthConformanceRunner
    implements DeployedWorkerAuthConformanceRunner {
  HttpDeployedWorkerAuthConformanceRunner(
    this.config, {
    DeployedWorkerHttpClientFactory? clientFactory,
  }) : _client = (clientFactory ?? HttpClient.new)() {
    _client.connectionTimeout = config.timeout;
  }

  static const int _maximumResponseBytes = 256 * 1024;

  final DeployedWorkerAuthConformanceConfig config;
  final HttpClient _client;

  @override
  Future<DeployedWorkerAuthConformanceReport> run() async {
    final health = await _request('GET', '/__routed_auth_conformance/health');
    _validateHealth(health);

    final results = <DeployedWorkerAuthSuiteResult>[];
    for (final suite in config.suites) {
      try {
        final response = await _request(
          'POST',
          '/__routed_auth_conformance/run',
          body: jsonEncode(<String, Object?>{'suite': suite.id}),
        );
        final responseSuite = response.body['suite'];
        if (response.statusCode != HttpStatus.ok || responseSuite != suite.id) {
          results.add(
            DeployedWorkerAuthSuiteResult(
              suite: suite,
              passed: false,
              errorCode: 'invalid_worker_response',
            ),
          );
          continue;
        }
        final passed = response.body['passed'] == true;
        results.add(
          DeployedWorkerAuthSuiteResult(
            suite: suite,
            passed: passed,
            caseId: _optionalSafeIdentifier(response.body['caseId']),
            errorCode: passed
                ? null
                : _optionalSafeIdentifier(response.body['error']) ??
                      'conformance_failed',
          ),
        );
      } on DeployedWorkerAuthRequestFailure catch (error) {
        results.add(
          DeployedWorkerAuthSuiteResult(
            suite: suite,
            passed: false,
            errorCode: error.code,
          ),
        );
      }
    }
    return DeployedWorkerAuthConformanceReport(
      List<DeployedWorkerAuthSuiteResult>.unmodifiable(results),
    );
  }

  void _validateHealth(_WorkerResponse response) {
    if (response.statusCode != HttpStatus.ok ||
        response.body['protocolVersion'] != deployedWorkerAuthProtocolVersion) {
      throw const DeployedWorkerAuthRequestFailure('worker_protocol_mismatch');
    }
    final advertised = response.body['suites'];
    if (advertised is! List ||
        config.suites.any((suite) => !advertised.contains(suite.id))) {
      throw const DeployedWorkerAuthRequestFailure('worker_suite_unavailable');
    }
  }

  Future<_WorkerResponse> _request(
    String method,
    String path, {
    String? body,
  }) async {
    try {
      final request = await _client
          .openUrl(method, config.workerOrigin.resolve(path))
          .timeout(config.timeout);
      // Each suite creates and closes an isolated in-memory auth runtime on
      // the Worker. Do not let a keep-alive connection carry protocol state
      // from one suite into the next, especially across Cloudflare's HTTP/2
      // edge proxy.
      request
        ..persistentConnection = false
        ..followRedirects = false
        ..headers.set(deployedWorkerAuthTokenHeader, config.token)
        ..headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(body));
      }
      final response = await request.close().timeout(config.timeout);
      final bytes = await _readBounded(response).timeout(config.timeout);
      Map<String, Object?> decoded;
      try {
        final value = jsonDecode(utf8.decode(bytes));
        decoded = value is Map
            ? value.map((key, value) => MapEntry('$key', value))
            : const <String, Object?>{};
      } on FormatException {
        decoded = const <String, Object?>{};
      }
      return _WorkerResponse(response.statusCode, decoded);
    } on DeployedWorkerAuthRequestFailure {
      rethrow;
    } on TimeoutException {
      throw const DeployedWorkerAuthRequestFailure('worker_timeout');
    } on SocketException {
      throw const DeployedWorkerAuthRequestFailure('worker_unreachable');
    } on HttpException {
      throw const DeployedWorkerAuthRequestFailure('worker_http_failure');
    } on TlsException {
      throw const DeployedWorkerAuthRequestFailure('worker_tls_failure');
    } on FormatException {
      throw const DeployedWorkerAuthRequestFailure('worker_response_invalid');
    }
  }

  Future<Uint8List> _readBounded(HttpClientResponse response) async {
    if (response.contentLength > _maximumResponseBytes) {
      throw const DeployedWorkerAuthRequestFailure('worker_response_too_large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > _maximumResponseBytes) {
        throw const DeployedWorkerAuthRequestFailure(
          'worker_response_too_large',
        );
      }
    }
    return bytes.takeBytes();
  }

  @override
  void close() => _client.close(force: true);
}

final class DeployedWorkerAuthRequestFailure implements Exception {
  const DeployedWorkerAuthRequestFailure(this.code);

  final String code;

  @override
  String toString() => 'DeployedWorkerAuthRequestFailure($code)';
}

final class _WorkerResponse {
  const _WorkerResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

String? _optionalSafeIdentifier(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 128 ||
      !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
    return null;
  }
  return value;
}
