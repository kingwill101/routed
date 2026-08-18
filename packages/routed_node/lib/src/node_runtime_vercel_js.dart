part of 'node_runtime_js.dart';

/// Installs callbacks for a Vercel-captured Node server entrypoint.
void defineVercelNodeHandlers(Engine engine) {
  keepNodeEventLoopAlive();
  Future<Engine>? engineFuture;
  Future<Engine> getEngine() =>
      engineFuture ??= engine.initialize().then((_) => engine);
  final requestHandler = ((JSAny req, JSAny res) {
    final dispatch = _dispatchVercelNodeRequest(
      getEngine,
      req as JSObject,
      res as JSObject,
    );
    return dispatch.toJS;
  }).toJS;
  globalContext.setProperty(
    '__routed_vercel_node_request__'.toJS,
    requestHandler,
  );

  final upgradeHandler = ((JSAny req, JSAny socket, JSAny head) {
    final upgrade = getEngine().then((engine) {
      _dispatchVercelNodeUpgrade(
        engine,
        req as JSObject,
        socket as JSObject,
        head,
      );
    });
    return upgrade.toJS;
  }).toJS;
  globalContext.setProperty(
    '__routed_vercel_node_upgrade__'.toJS,
    upgradeHandler,
  );
  defineVercelWebSocketHandler(getEngine);
}

/// Installs lazy callbacks for a Vercel-captured Node server.
void defineVercelNodeHandlersAsync(Future<Engine> Function() factory) {
  keepNodeEventLoopAlive();
  Future<Engine>? engineFuture;
  Future<Engine> getEngine() => engineFuture ??= factory();

  final requestHandler = ((JSAny req, JSAny res) {
    return _dispatchVercelNodeRequest(
      getEngine,
      req as JSObject,
      res as JSObject,
    ).toJS;
  }).toJS;
  final upgradeHandler = ((JSAny req, JSAny socket, JSAny head) {
    return _dispatchVercelNodeUpgradeAsync(
      getEngine,
      req as JSObject,
      socket as JSObject,
      head,
    ).toJS;
  }).toJS;
  globalContext.setProperty(
    '__routed_vercel_node_request__'.toJS,
    requestHandler,
  );
  globalContext.setProperty(
    '__routed_vercel_node_upgrade__'.toJS,
    upgradeHandler,
  );
  defineVercelWebSocketHandler(getEngine);
}

Future<void> _dispatchVercelNodeRequest(
  Future<Engine> Function() getEngine,
  JSObject req,
  JSObject res,
) async {
  final incoming = _JsIncoming(_NodeIncomingMessage._(req));
  final outgoing = _JsOutgoing(_NodeServerResponse._(res));
  try {
    final engine = await getEngine();
    final hostContext = RoutedNodeContext(
      info: const RoutedNodeRuntimeInfo(
        runtime: RoutedNodeRuntime.vercel,
        capabilities: vercelNodeCapabilities,
      ),
      extension: VercelNodeRuntimeExtension(request: req, response: res),
    );
    await dispatchNodeExchange(
      engine,
      incoming,
      outgoing,
      baseUri: Uri(scheme: 'https', host: 'localhost'),
      hostContext: hostContext,
    );
  } catch (_) {
    if (!outgoing.finished) {
      outgoing.writeHead(500, {'Content-Type': 'text/plain'});
      outgoing.end('Internal Server Error'.codeUnits);
    }
  }
}

Future<void> _dispatchVercelNodeUpgradeAsync(
  Future<Engine> Function() getEngine,
  JSObject req,
  JSObject socket,
  JSAny head,
) async {
  final engine = await getEngine();
  _dispatchVercelNodeUpgrade(engine, req, socket, head);
}

void _dispatchVercelNodeUpgrade(
  Engine engine,
  JSObject req,
  JSObject socket,
  JSAny head,
) {
  final incoming = _JsIncoming(_NodeIncomingMessage._(req));
  final nodeSocket = _JsWebSocketSocket(
    _NodeSocket._(socket),
    head: _chunkToBytes(head),
  );
  final rawHeaders = incoming.rawHeaders;
  final isUpgrade =
      _header(rawHeaders, 'upgrade')?.toLowerCase() == 'websocket';
  final connection =
      _header(
        rawHeaders,
        'connection',
      )?.toLowerCase().split(',').map((v) => v.trim()).contains('upgrade') ??
      false;
  final key = _header(rawHeaders, 'sec-websocket-key');
  final version = _header(rawHeaders, 'sec-websocket-version');
  if (!isUpgrade || !connection || key == null || version != '13') {
    nodeSocket.end(
      Uint8List.fromList(
        utf8.encode(
          'HTTP/1.1 400 Bad Request\\r\\nConnection: close\\r\\n\\r\\n',
        ),
      ),
    );
    return;
  }
  final protocol = _header(rawHeaders, 'sec-websocket-protocol')
      ?.split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .firstOrNull;
  final response = NodeWebSocketUpgradeResponse(
    socket: nodeSocket,
    key: key,
    protocol: protocol,
  );
  final hostContext = RoutedNodeContext(
    info: const RoutedNodeRuntimeInfo(
      runtime: RoutedNodeRuntime.vercel,
      capabilities: vercelNodeCapabilities,
    ),
    extension: VercelNodeRuntimeExtension(request: req, response: socket),
  );
  final adapter = NodeRequestAdapter(
    incoming,
    baseUri: Uri(scheme: 'https', host: 'localhost'),
    hostContext: hostContext,
    isWebSocketUpgrade: true,
    acceptWebSocket: () async {
      await nodeSocket.write(response.handshake);
      return NodeRoutedWebSocket(socket: nodeSocket);
    },
    upgradeResponse: () => response,
  );
  unawaited(dispatchNodeWebSocket(engine, adapter, nodeSocket));
}
