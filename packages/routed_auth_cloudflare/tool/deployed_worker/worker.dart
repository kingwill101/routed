import 'dart:convert';

import 'package:routed_auth/testing.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';

import '../deployed_worker_auth_protocol.dart';

const _tokenBinding = 'ROUTED_AUTH_CONFORMANCE_TOKEN';
const _maximumControlBodyBytes = 1024;

/// Creates the opt-in control engine used by the deployed conformance Worker.
///
/// The engine calls only deterministic, in-memory Routed auth fixtures. It
/// does not use Cloudflare control-plane APIs or mutate account resources.
Engine createDeployedWorkerAuthConformanceEngine() {
  final engine = Engine(providers: Engine.defaultProviders);
  engine.get('/__routed_auth_conformance/health', (context) async {
    if (!_isAuthorized(context)) {
      return context.json(<String, Object?>{
        'error': 'unauthorized',
      }, statusCode: 401);
    }
    return context.json(<String, Object?>{
      'protocolVersion': deployedWorkerAuthProtocolVersion,
      'suites': <String>[
        for (final suite in DeployedWorkerAuthSuite.values) suite.id,
      ],
    });
  });
  engine.post('/__routed_auth_conformance/run', (context) async {
    if (!_isAuthorized(context)) {
      return context.json(<String, Object?>{
        'error': 'unauthorized',
      }, statusCode: 401);
    }
    if (context.contentLength > _maximumControlBodyBytes) {
      return context.json(<String, Object?>{
        'error': 'invalid_request',
      }, statusCode: 400);
    }

    Object? decoded;
    try {
      final body = await context.body();
      if (utf8.encode(body).length > _maximumControlBodyBytes) {
        return context.json(<String, Object?>{
          'error': 'invalid_request',
        }, statusCode: 400);
      }
      decoded = jsonDecode(body);
    } on FormatException {
      return context.json(<String, Object?>{
        'error': 'invalid_request',
      }, statusCode: 400);
    }
    if (decoded is! Map || decoded['suite'] is! String) {
      return context.json(<String, Object?>{
        'error': 'invalid_request',
      }, statusCode: 400);
    }

    DeployedWorkerAuthSuite suite;
    try {
      suite = DeployedWorkerAuthSuite.parse(decoded['suite'] as String);
    } on FormatException {
      return context.json(<String, Object?>{
        'error': 'unknown_suite',
      }, statusCode: 400);
    }

    final origin = _originOf(context.requestedUri);
    try {
      await runDeployedWorkerAuthSuite(suite, origin);
      return context.json(<String, Object?>{'suite': suite.id, 'passed': true});
    } on AuthRuntimeConformanceFailure catch (error) {
      return context.json(<String, Object?>{
        'suite': suite.id,
        'passed': false,
        'caseId': _safeIdentifier(error.caseId),
        'error': 'conformance_failed',
      });
    } catch (_) {
      return context.json(<String, Object?>{
        'suite': suite.id,
        'passed': false,
        'error': 'conformance_failed',
      });
    }
  });
  return engine;
}

bool _isAuthorized(EngineContext context) {
  try {
    final environment = cloudflareEnvironmentOf(context);
    if (environment == null) return false;
    final expected = cloudflareTextBinding(environment, _tokenBinding);
    if (!_validToken(expected)) return false;
    final presented = context.request.headers.value(
      deployedWorkerAuthTokenHeader,
    );
    if (presented == null || !_validToken(presented)) return false;
    return _constantTimeStringEquals(expected, presented);
  } catch (_) {
    return false;
  }
}

bool _validToken(String value) =>
    value.isNotEmpty &&
    value.length <= 4096 &&
    !value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

bool _constantTimeStringEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  final length = leftBytes.length > rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  var difference = leftBytes.length ^ rightBytes.length;
  for (var index = 0; index < length; index++) {
    final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
    final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}

Uri _originOf(Uri value) => Uri(
  scheme: value.scheme,
  host: value.host,
  port: value.hasPort ? value.port : null,
);

String _safeIdentifier(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
    return 'conformance_failed';
  }
  return value;
}

/// Runs one deterministic suite without contacting Cloudflare services.
Future<void> runDeployedWorkerAuthSuite(
  DeployedWorkerAuthSuite suite,
  Uri origin,
) {
  return switch (suite) {
    DeployedWorkerAuthSuite.session => _runSession(origin),
    DeployedWorkerAuthSuite.jwt => _runExternalProviders(
      origin,
      sessionStrategy: AuthSessionStrategy.jwt,
    ),
    DeployedWorkerAuthSuite.plugins => _runPlugins(origin),
    DeployedWorkerAuthSuite.externalProviders => _runExternalProviders(
      origin,
      sessionStrategy: AuthSessionStrategy.session,
    ),
    DeployedWorkerAuthSuite.webAuthn => _runWebAuthn(origin),
  };
}

Future<void> _runSession(Uri origin) async {
  final engine = createAuthRuntimeConformanceEngine();
  await engine.initialize();
  try {
    await verifyAuthRuntimeConformance(
      origin: origin,
      send: (request) => _dispatch(engine, origin, request),
    );
  } finally {
    await engine.close();
  }
}

Future<void> _runPlugins(Uri origin) async {
  final engine = createAuthPluginRuntimeConformanceEngine();
  final engineWithoutTwoFactor = createAuthPluginRuntimeConformanceEngine(
    includeTwoFactor: false,
  );
  await engine.initialize();
  await engineWithoutTwoFactor.initialize();
  try {
    await verifyAuthPluginRuntimeConformance(
      origin: origin,
      send: (request) => _dispatch(engine, origin, request),
      sendWithoutTwoFactor: (request) =>
          _dispatch(engineWithoutTwoFactor, origin, request),
    );
  } finally {
    await engine.close();
    await engineWithoutTwoFactor.close();
  }
}

Future<void> _runExternalProviders(
  Uri origin, {
  required AuthSessionStrategy sessionStrategy,
}) async {
  final engine = createAuthExternalProviderRuntimeConformanceEngine(
    sessionStrategy: sessionStrategy,
  );
  await engine.initialize();
  try {
    await verifyAuthExternalProviderRuntimeConformance(
      origin: origin,
      send: (request) => _dispatch(engine, origin, request),
      expectJwt: sessionStrategy == AuthSessionStrategy.jwt,
    );
  } finally {
    await engine.close();
  }
}

Future<void> _runWebAuthn(Uri origin) async {
  final engine = createAuthPluginRuntimeConformanceEngine();
  await engine.initialize();
  try {
    await verifyAuthWebAuthnPluginRuntimeConformance(
      origin: origin,
      send: (request) => _dispatch(engine, origin, request),
    );
  } finally {
    await engine.close();
  }
}

Future<AuthRuntimeConformanceResponse> _dispatch(
  Engine engine,
  Uri origin,
  AuthRuntimeConformanceRequest request,
) async {
  final response = await dispatchFetchExchange(
    engine,
    _HarnessFetchRequest(origin, request),
    runtime: const RoutedNodeRuntimeInfo(
      runtime: RoutedNodeRuntime.cloudflare,
      capabilities: cloudflareCapabilities,
    ),
  );
  return AuthRuntimeConformanceResponse(
    statusCode: response.statusCode,
    headers: response.headers,
    body: await utf8.decodeStream(response.body),
  );
}

final class _HarnessFetchRequest implements FetchRequestView {
  const _HarnessFetchRequest(this.origin, this.request);

  final Uri origin;
  final AuthRuntimeConformanceRequest request;

  @override
  String get method => request.method;

  @override
  String get url => origin.resolve(request.path).toString();

  @override
  Map<String, Object?> get rawHeaders => request.headers;

  @override
  Stream<List<int>> get body => request.body == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(request.body!));

  @override
  String get remoteAddress => '127.0.0.1';

  @override
  RoutedNodeContext? get hostContext => null;
}

void main() {
  defineCloudflareFetchFactoryAsync(() async {
    final engine = createDeployedWorkerAuthConformanceEngine();
    return engine;
  });
}
