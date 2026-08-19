import 'dart:convert';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';
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

/// SQLite-backed Durable Object used by the live Cloudflare binding smoke test.
final class Counter extends CloudflareDurableObject {
  Counter(super.state, super.env) {
    state.storage.sql?.exec('''
      CREATE TABLE IF NOT EXISTS counter (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        value INTEGER NOT NULL
      )
    ''');
    state.storage.sql?.exec(
      'INSERT OR IGNORE INTO counter (id, value) VALUES (1, 0)',
    );
  }

  @override
  Future<CloudflareResponse> fetch(CloudflareRequest request) async {
    final sql = state.storage.sql;
    if (sql == null) {
      return CloudflareResponse.text(
        'SQLite Durable Object storage is unavailable.',
        status: 500,
      );
    }

    final current =
        (sql.exec('SELECT value FROM counter WHERE id = 1').one()['value']
                as num?)
            ?.toInt() ??
        0;
    final next = current + 1;
    sql.exec('UPDATE counter SET value = ? WHERE id = 1', [next]);
    return CloudflareResponse.json({'ok': true, 'value': next});
  }
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
/// - `GET  /bindings/d1` live D1 binding check
/// - `GET  /bindings/durable-object` live Durable Object check
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

  engine.get('/bindings/d1', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    if (environment == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final result = await environment
        .d1('DB')
        .prepare('INSERT INTO routed_live_checks (marker) VALUES (?)')
        .bind(['cloudflare'])
        .run<Object?>();
    final row = await environment
        .d1('DB')
        .prepare('SELECT COUNT(*) AS count FROM routed_live_checks')
        .first<Map<String, Object?>>();
    return ctx.json({
      'ok': result.success,
      'rowsWritten': result.meta?.rowsWritten,
      'count': row?['count'],
    });
  });

  engine.get('/bindings/durable-object', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    final request = cloudflareRequestOf(ctx);
    if (environment == null || request == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final response = await environment
        .durableObjectNamespace('COUNTER')
        .getByName('live')
        .fetch(request);
    ctx.response.statusCode = response.status;
    for (final entry in response.headers.entries) {
      ctx.response.setHeader(entry.key, entry.value);
    }
    final body = response.body;
    if (body is Uint8List) {
      ctx.response.writeBytes(body);
    } else {
      ctx.response.write(body ?? '');
    }
    return ctx.response;
  });

  engine.get('/bindings/request', (ctx) {
    final request = cloudflareRequestOf(ctx);
    if (request == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    const exposedCfKeys = {
      'colo',
      'country',
      'city',
      'continent',
      'httpProtocol',
      'tlsVersion',
    };
    return ctx.json({
      'ok': request.url.isNotEmpty,
      'method': request.method,
      'cf': Map<String, Object?>.fromEntries(
        request.cf.entries.where((entry) => exposedCfKeys.contains(entry.key)),
      ),
    });
  });

  engine.get('/bindings/cache', (ctx) async {
    final request = cloudflareRequestOf(ctx);
    if (request == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final key = createCloudflareRequest('${request.url}?routed-live-cache=1');
    final cache = await cloudflareCache(name: 'routed-live-smoke');
    await cache.put(key, CloudflareResponse.text('cache-ok'));
    final cached = await cache.match(key);
    final deleted = await cache.delete(key);
    return ctx.json({'ok': cached?.text() == 'cache-ok', 'deleted': deleted});
  });

  engine.get('/bindings/r2', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    final request = cloudflareRequestOf(ctx);
    if (environment == null || request == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final requestedKey = Uri.parse(request.url).queryParameters['key'];
    final key = requestedKey == null || requestedKey.isEmpty
        ? 'routed-live/default.txt'
        : requestedKey;
    final bucket = environment.r2('FILES');
    await bucket.put(
      key,
      'routed-r2-ok',
      options: const CloudflareR2PutOptions(
        httpMetadata: {'content-type': 'text/plain'},
        customMetadata: {'source': 'routed-live-smoke'},
      ),
    );
    final head = await bucket.head(key);
    final object = await bucket.get(key);
    final listed = await bucket.list(
      options: CloudflareR2ListOptions(prefix: 'routed-live/'),
    );
    await bucket.delete(key);
    return ctx.json({
      'ok': await object?.readAsString() == 'routed-r2-ok',
      'headKey': head?.key,
      'listed': listed.objects.any((item) => item.key == key),
      'customMetadata': object?.customMetadata,
    });
  });

  engine.get('/bindings/queue', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    if (environment == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final send = await environment.queue('EVENTS').send({
      'marker': 'routed-queue-ok',
    }, contentType: CloudflareQueueContentType.json);
    final metrics = await environment.queue('EVENTS').metrics();
    return ctx.json({
      'ok': true,
      'hasSendMetrics': send.metrics != null,
      'backlogCount': metrics.backlogCount,
    });
  });

  engine.get('/bindings/service', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    final request = cloudflareRequestOf(ctx);
    if (environment == null || request == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final service = environment.service('PROFILE_API');
    CloudflareResponse? fetchResponse;
    try {
      fetchResponse = await service.fetch(request);
    } catch (_) {}

    num? sum;
    String? greeting;
    num? constant;
    try {
      sum = await service.call<num>('add', [2, 3]);
      constant = await service.call<num>('constant');
      greeting = await service.call<String>('greet', ['Ada']);
    } catch (_) {}
    return ctx.json({
      'ok':
          fetchResponse?.text() == 'service-fetch-ok' &&
          sum == 5 &&
          constant == 5 &&
          greeting == 'hello Ada',
      'fetchOk': fetchResponse?.text() == 'service-fetch-ok',
      'rpc': sum,
      'constant': constant,
      'greeting': greeting,
    });
  });

  engine.get('/bindings/secrets-store', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    if (environment == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final value = await environment.secretsStore('SMOKE_SECRET').get();
    return ctx.json({
      'ok': value == 'routed-secrets-store-ok',
      'present': value != null,
    });
  });

  engine.get('/bindings/workflow', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    if (environment == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final workflow = environment.workflow('SMOKE_WORKFLOW');
    final instance = await workflow.create(
      options: const CloudflareWorkflowCreateOptions(
        params: {'marker': 'routed-workflow-ok'},
      ),
    );
    final status = await instance.status();
    final fetchedStatus = await (await workflow.get(instance.id)).status();
    return ctx.json({
      'ok': instance.id.isNotEmpty,
      'id': instance.id,
      'status': status.status,
      'fetchedStatus': fetchedStatus.status,
    });
  });

  engine.get('/bindings/container', (ctx) async {
    final environment = cloudflareEnvironmentOf(ctx);
    final request = cloudflareRequestOf(ctx);
    if (environment == null || request == null) {
      return ctx.json({
        'error': 'cloudflare_bindings_unavailable',
      }, statusCode: 500);
    }

    final response = await environment
        .container('APP')
        .get('routed-live')
        .fetch(request);
    return ctx.json({
      'ok': response.text() == 'container-fetch-ok',
      'status': response.status,
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
