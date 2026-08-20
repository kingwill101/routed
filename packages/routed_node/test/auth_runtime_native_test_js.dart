import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_auth/testing.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/node.dart';
import 'package:test/test.dart';

const _nodeOrigin = 'http://127.0.0.1';
const _cloudflareOrigin = 'https://runtime.example';

void runNativeAuthRuntimeTests() {
  _stabilizeNodeCryptoBinding();

  test('native Node listener satisfies the auth runtime contract', () async {
    final engine = createAuthRuntimeConformanceEngine();
    await engine.initialize();
    final handle = await serveNode(
      engine,
      host: '127.0.0.1',
      port: 0,
      echo: false,
    );
    final origin = Uri.parse('$_nodeOrigin:${handle.port}');
    try {
      await verifyAuthRuntimeConformance(
        origin: origin,
        send: (request) => _sendWithFetch(origin, request),
      );
    } finally {
      await handle.close(force: true);
      await engine.close();
    }
  });

  test('native Node listener satisfies the auth plugin contract', () async {
    final engine = createAuthPluginRuntimeConformanceEngine();
    final engineWithoutTwoFactor = createAuthPluginRuntimeConformanceEngine(
      includeTwoFactor: false,
    );
    await engine.initialize();
    await engineWithoutTwoFactor.initialize();
    final handle = await serveNode(
      engine,
      host: '127.0.0.1',
      port: 0,
      echo: false,
    );
    final handleWithoutTwoFactor = await serveNode(
      engineWithoutTwoFactor,
      host: '127.0.0.1',
      port: 0,
      echo: false,
    );
    final origin = Uri.parse('$_nodeOrigin:${handle.port}');
    final originWithoutTwoFactor = Uri.parse(
      '$_nodeOrigin:${handleWithoutTwoFactor.port}',
    );
    try {
      await verifyAuthPluginRuntimeConformance(
        origin: origin,
        send: (request) => _sendWithFetch(origin, request),
        sendWithoutTwoFactor: (request) =>
            _sendWithFetch(originWithoutTwoFactor, request),
      );
    } finally {
      await handle.close(force: true);
      await handleWithoutTwoFactor.close(force: true);
      await engine.close();
      await engineWithoutTwoFactor.close();
    }
  });

  test(
    'native Cloudflare Fetch export satisfies the auth runtime contract',
    () async {
      final engine = createAuthRuntimeConformanceEngine();
      await engine.initialize();
      try {
        defineCloudflareFetch(engine);
        await verifyAuthRuntimeConformance(
          origin: Uri.parse(_cloudflareOrigin),
          send: (request) => _sendToCloudflareExport(request),
        );
      } finally {
        await engine.close();
      }
    },
  );

  test(
    'native Cloudflare Fetch export satisfies the auth plugin contract',
    () async {
      final engine = createAuthPluginRuntimeConformanceEngine();
      final engineWithoutTwoFactor = createAuthPluginRuntimeConformanceEngine(
        includeTwoFactor: false,
      );
      await engine.initialize();
      await engineWithoutTwoFactor.initialize();
      try {
        await verifyAuthPluginRuntimeConformance(
          origin: Uri.parse(_cloudflareOrigin),
          send: (request) {
            defineCloudflareFetch(engine);
            return _sendToCloudflareExport(request);
          },
          sendWithoutTwoFactor: (request) {
            defineCloudflareFetch(engineWithoutTwoFactor);
            return _sendToCloudflareExport(request);
          },
        );
      } finally {
        await engine.close();
        await engineWithoutTwoFactor.close();
      }
    },
  );

  test('native Cloudflare Fetch startup errors are generic', () async {
    defineCloudflareFetchAsync(
      Future.error(StateError(authRuntimeConformanceFailureMarker)),
    );
    final response = await _sendToCloudflareExport(
      const AuthRuntimeConformanceRequest(method: 'GET', path: '/auth/session'),
    );

    expect(response.statusCode, 500);
    expect(response.body, 'Internal Server Error');
    expect(response.body, isNot(contains(authRuntimeConformanceFailureMarker)));
  });
}

void _stabilizeNodeCryptoBinding() {
  // Node 24 exposes `crypto` through a receiver-sensitive global getter.
  // dart2js reads it as an unbound property while creating Random.secure().
  // Replace the getter with its current value for this test process only.
  final evaluate = globalContext.getProperty('eval'.toJS) as JSFunction;
  evaluate.callAsFunction(
    null,
    '''Object.defineProperty(globalThis, 'crypto', {
      value: globalThis.crypto,
      configurable: true,
      writable: true
    })'''
        .toJS,
  );
}

Future<AuthRuntimeConformanceResponse> _sendWithFetch(
  Uri origin,
  AuthRuntimeConformanceRequest request,
) async {
  final fetch = globalContext.getProperty('fetch'.toJS) as JSFunction;
  final response = await _invokeFetch(
    fetch,
    origin.resolve(request.path).toString(),
    request,
  );
  return _readResponse(response);
}

Future<AuthRuntimeConformanceResponse> _sendToCloudflareExport(
  AuthRuntimeConformanceRequest request,
) async {
  final handler =
      globalContext.getProperty('__routed_fetch__'.toJS) as JSFunction;
  final requestConstructor =
      globalContext.getProperty('Request'.toJS) as JSFunction;
  final nativeRequest = requestConstructor.callAsConstructorVarArgs<JSObject>([
    '$_cloudflareOrigin${request.path}'.toJS,
    _requestInit(request),
  ]);
  final promise = handler.callAsFunction(null, nativeRequest);
  final response = await (promise as JSPromise<JSAny?>).toDart;
  return _readResponse(response as JSObject);
}

Future<JSObject> _invokeFetch(
  JSFunction fetch,
  String url,
  AuthRuntimeConformanceRequest request,
) async {
  final promise = fetch.callAsFunction(null, url.toJS, _requestInit(request));
  final response = await (promise as JSPromise<JSAny?>).toDart;
  return response as JSObject;
}

JSObject _requestInit(AuthRuntimeConformanceRequest request) {
  final init = JSObject()
    ..setProperty('method'.toJS, request.method.toJS)
    ..setProperty('headers'.toJS, request.headers.jsify());
  final body = request.body;
  if (body != null) init.setProperty('body'.toJS, body.toJS);
  return init;
}

Future<AuthRuntimeConformanceResponse> _readResponse(JSObject response) async {
  final status = (response.getProperty('status'.toJS) as JSNumber).toDartInt;
  final headersObject = response.getProperty('headers'.toJS) as JSObject;
  final headers = <String, List<String>>{};
  for (final name in const <String>['content-type', 'set-cookie']) {
    final value = headersObject.callMethodVarArgs<JSAny?>('get'.toJS, [
      name.toJS,
    ]);
    if (value != null && value.isA<JSString>()) {
      headers[name] = <String>[(value as JSString).toDart];
    }
  }
  final bodyPromise = response.callMethod<JSAny?>('text'.toJS);
  final body = await (bodyPromise as JSPromise<JSAny?>).toDart;
  return AuthRuntimeConformanceResponse(
    statusCode: status,
    headers: headers,
    body: (body as JSString).toDart,
  );
}
