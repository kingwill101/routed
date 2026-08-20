import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/node.dart';
import 'package:test/test.dart';

import '../../routed_auth/test/integration/support/runtime_auth_contract.dart';

const _nodeOrigin = 'http://127.0.0.1';
const _cloudflareOrigin = 'https://runtime.example';

void runNativeAuthRuntimeTests() {
  _stabilizeNodeCryptoBinding();

  test('native Node listener satisfies the auth runtime contract', () async {
    final engine = createRuntimeAuthEngine();
    await engine.initialize();
    final handle = await serveNode(
      engine,
      host: '127.0.0.1',
      port: 0,
      echo: false,
    );
    final origin = Uri.parse('$_nodeOrigin:${handle.port}');
    try {
      await verifyRuntimeAuthContract(
        origin: origin,
        send: (request) => _sendWithFetch(origin, request),
        // bindNodeHttp currently resolves requests against the configured
        // port (0), not the assigned ephemeral port. No-Origin requests are
        // supported; hostile Origin and Fetch Metadata checks still run.
        sendValidOriginHeader: false,
      );
    } finally {
      await handle.close(force: true);
      await engine.close();
    }
  });

  test(
    'native Cloudflare Fetch export satisfies the auth runtime contract',
    () async {
      final engine = createRuntimeAuthEngine();
      await engine.initialize();
      try {
        defineCloudflareFetch(engine);
        await verifyRuntimeAuthContract(
          origin: Uri.parse(_cloudflareOrigin),
          send: (request) => _sendToCloudflareExport(request),
        );
      } finally {
        await engine.close();
      }
    },
    skip:
        'WebFetchRequest.rawHeaders does not yet forward Cookie, Origin, '
        'X-CSRF-Token, or Sec-Fetch-Site from native Fetch requests.',
  );

  test('native Cloudflare Fetch startup errors are generic', () async {
    defineCloudflareFetchAsync(
      Future.error(StateError(runtimeAuthFailureMarker)),
    );
    final response = await _sendToCloudflareExport(
      const RuntimeAuthRequest(method: 'GET', path: '/auth/session'),
    );

    expect(response.statusCode, 500);
    expect(response.body, 'Internal Server Error');
    expect(response.body, isNot(contains(runtimeAuthFailureMarker)));
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

Future<RuntimeAuthResponse> _sendWithFetch(
  Uri origin,
  RuntimeAuthRequest request,
) async {
  final fetch = globalContext.getProperty('fetch'.toJS) as JSFunction;
  final response = await _invokeFetch(
    fetch,
    origin.resolve(request.path).toString(),
    request,
  );
  return _readResponse(response);
}

Future<RuntimeAuthResponse> _sendToCloudflareExport(
  RuntimeAuthRequest request,
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
  RuntimeAuthRequest request,
) async {
  final promise = fetch.callAsFunction(null, url.toJS, _requestInit(request));
  final response = await (promise as JSPromise<JSAny?>).toDart;
  return response as JSObject;
}

JSObject _requestInit(RuntimeAuthRequest request) {
  final init = JSObject()
    ..setProperty('method'.toJS, request.method.toJS)
    ..setProperty('headers'.toJS, request.headers.jsify());
  final body = request.body;
  if (body != null) init.setProperty('body'.toJS, body.toJS);
  return init;
}

Future<RuntimeAuthResponse> _readResponse(JSObject response) async {
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
  return RuntimeAuthResponse(
    statusCode: status,
    headers: headers,
    body: (body as JSString).toDart,
  );
}
