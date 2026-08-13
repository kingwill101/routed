import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_node/routed_node.dart';

/// In-memory item store for the sample API (demo only — not durable).
final class _EchoWebSocketHandler extends WebSocketHandler {
  @override
  Future<void> onOpen(WebSocketContext context) async {
    context.send('ready');
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    context.send('echo:$message');
  }

  @override
  Future<void> onClose(WebSocketContext context) async {}

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {}
}

final class ItemStore {
  ItemStore() {
    _items.addAll({
      '1': {'id': '1', 'name': 'alpha', 'qty': 3},
      '2': {'id': '2', 'name': 'beta', 'qty': 1},
    });
  }

  final Map<String, Map<String, Object?>> _items = {};
  int _seq = 2;

  List<Map<String, Object?>> list() =>
      _items.values.map((e) => Map<String, Object?>.from(e)).toList();

  Map<String, Object?>? get(String id) {
    final item = _items[id];
    return item == null ? null : Map<String, Object?>.from(item);
  }

  Map<String, Object?> create({required String name, int qty = 1}) {
    _seq += 1;
    final id = '$_seq';
    final item = <String, Object?>{'id': id, 'name': name, 'qty': qty};
    _items[id] = item;
    return Map<String, Object?>.from(item);
  }

  bool delete(String id) => _items.remove(id) != null;
}

/// Builds the sample [Engine] with a small JSON API.
///
/// Routes:
/// - `GET  /`              welcome
/// - `GET  /health`        liveness
/// - `GET  /api/items`     list items
/// - `GET  /api/items/:id` get one item
/// - `POST /api/items`     create (`{"name":"...","qty":1}`)
/// - `DELETE /api/items/:id`
/// - `GET  /stream` progressive response
/// - `POST /echo` request-body and header echo
Engine createSampleEngine({ItemStore? store}) {
  final items = store ?? ItemStore();
  final engine = Engine(providers: Engine.defaultProviders);
  engine.ws('/ws', _EchoWebSocketHandler());

  engine.get('/', (ctx) {
    return ctx.json({
      'service': 'routed_node_api_sample',
      'message': 'Routed sample API (Node host package)',
      'docs': {
        'health': 'GET /health',
        'list': 'GET /api/items',
        'get': 'GET /api/items/:id',
        'create': 'POST /api/items',
        'delete': 'DELETE /api/items/:id',
        'websocket': 'GET /ws',
      },
    });
  });

  engine.get('/health', (ctx) {
    final capabilities =
        routedNodeContextOf(ctx)?.info.capabilities ?? nodeCapabilities;
    return ctx.json({
      'ok': true,
      'runtime': 'routed_node',
      'capabilities': {
        'streaming': capabilities.streaming,
        'websocket': capabilities.webSocket,
      },
    });
  });

  engine.get('/capabilities', (ctx) {
    return ctx.json(
      {
        'node': nodeCapabilities,
        'bun': bunCapabilities,
        'deno': denoCapabilities,
        'cloudflare': cloudflareCapabilities,
        'vercel': vercelCapabilities,
        'netlify': netlifyCapabilities,
      }.map(
        (key, value) => MapEntry(key, {
          'streaming': value.streaming,
          'bufferedResponses': value.bufferedResponses,
          'webSocket': value.webSocket,
          'fileSystem': value.fileSystem,
          'backgroundWork': value.backgroundWork,
        }),
      ),
    );
  });

  engine.get('/stream', (ctx) async {
    ctx.response.setHeader('Content-Type', 'text/plain; charset=utf-8');
    ctx.response.write('routed:');
    await ctx.response.flush();
    ctx.response.write('stream');
    await ctx.response.close();
    return ctx.response;
  });

  engine.post('/echo', (ctx) async {
    final body = await ctx.request.body();
    return ctx.json({
      'body': body,
      'contentType': ctx.request.headers.contentType?.toString(),
      'trace': ctx.request.headers['x-trace'],
    });
  });

  engine.get('/api/items', (ctx) {
    return ctx.json({'items': items.list()});
  });

  engine.get('/api/items/{id}', (ctx) {
    final id = ctx.param('id')?.toString() ?? '';
    final item = items.get(id);
    if (item == null) {
      return ctx.json({'error': 'not_found', 'id': id}, statusCode: 404);
    }
    return ctx.json(item);
  });

  engine.post('/api/items', (ctx) async {
    final raw = await ctx.request.body();
    Map<String, Object?> body;
    try {
      final decoded = jsonDecode(raw.isEmpty ? '{}' : raw);
      if (decoded is! Map) {
        return ctx.json({'error': 'expected_object'}, statusCode: 400);
      }
      body = Map<String, Object?>.from(decoded);
    } catch (_) {
      return ctx.json({'error': 'invalid_json'}, statusCode: 400);
    }

    final name = body['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      return ctx.json({'error': 'name_required'}, statusCode: 422);
    }
    final qtyRaw = body['qty'];
    final qty = qtyRaw is int
        ? qtyRaw
        : int.tryParse(qtyRaw?.toString() ?? '') ?? 1;

    final created = items.create(name: name, qty: qty);
    return ctx.json(created, statusCode: 201);
  });

  engine.delete('/api/items/{id}', (ctx) {
    final id = ctx.param('id')?.toString() ?? '';
    if (!items.delete(id)) {
      return ctx.json({'error': 'not_found', 'id': id}, statusCode: 404);
    }
    return ctx.json({'deleted': true, 'id': id});
  });

  return engine;
}

/// CLI deployment contract shared by Cloudflare and Netlify.
Future<Engine> createEngine({bool initialize = true}) async {
  final engine = createSampleEngine();
  if (initialize) await engine.initialize();
  return engine;
}
