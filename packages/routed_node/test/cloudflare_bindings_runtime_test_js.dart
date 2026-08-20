@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/src/cloudflare/cloudflare_bindings_js.dart'
    as cloudflare_internal;
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

final sentWebSocketMessages = <Object>[];
final closedWebSockets = <String>[];
final acceptedWebSockets = <JSObject>[];
final durableObjectMessages = <Object>[];
final durableObjectCloses = <String>[];
final durableObjectErrors = <Object>[];
final queueBodies = <Object?>[];
final queueOptions = <Object?>[];
final queueBatchMessages = <Object?>[];
final workflowCalls = <String>[];
final containerCalls = <String>[];

JSObject _d1Result() {
  return JSObject()
    ..setProperty('success'.toJS, true.toJS)
    ..setProperty(
      'results'.toJS,
      <Map<String, Object?>>[
        <String, Object?>{'id': 42, 'email': 'user@example.test'},
      ].jsify(),
    )
    ..setProperty(
      'meta'.toJS,
      <String, Object?>{'rows_read': 1, 'rows_written': 1}.jsify(),
    );
}

JSObject _d1Database() {
  final statement = JSObject();
  statement.setProperty('bind'.toJS, ((JSAny? value) => statement).toJS);
  statement.setProperty(
    'first'.toJS,
    (() => Future<JSAny?>.value(
      <String, Object?>{'id': 42, 'email': 'user@example.test'}.jsify(),
    ).toJS).toJS,
  );
  statement.setProperty(
    'all'.toJS,
    (() => Future<JSAny?>.value(_d1Result()).toJS).toJS,
  );

  return JSObject()
    ..setProperty('prepare'.toJS, ((JSString query) => statement).toJS);
}

JSObject _durableObjectNamespace() {
  final id = JSObject()
    ..setProperty('name'.toJS, 'global'.toJS)
    ..setProperty('toString'.toJS, (() => 'global-id'.toJS).toJS)
    ..setProperty('equals'.toJS, ((JSAny? other) => true.toJS).toJS);
  final stub = JSObject()..setProperty('id'.toJS, id);

  return JSObject()
    ..setProperty('getByName'.toJS, ((JSString name) => stub).toJS);
}

web.ReadableStream _readableBody(String value) {
  final source = JSObject()
    ..setProperty(
      'start'.toJS,
      ((web.ReadableStreamDefaultController controller) {
        controller.enqueue(Uint8List.fromList(value.codeUnits).toJS);
        controller.close();
      }).toJS,
    );
  return web.ReadableStream(source);
}

JSObject _r2Object(String key, String body, {bool includeBody = true}) {
  final object = JSObject()
    ..setProperty('key'.toJS, key.toJS)
    ..setProperty('version'.toJS, 'version-1'.toJS)
    ..setProperty('size'.toJS, body.length.toJS)
    ..setProperty('etag'.toJS, 'etag-1'.toJS)
    ..setProperty('httpEtag'.toJS, '"etag-1"'.toJS)
    ..setProperty('uploaded'.toJS, '2026-08-18T12:00:00.000Z'.toJS)
    ..setProperty(
      'httpMetadata'.toJS,
      <String, Object?>{'contentType': 'text/plain'}.jsify(),
    )
    ..setProperty(
      'customMetadata'.toJS,
      <String, Object?>{'source': 'runtime-test'}.jsify(),
    )
    ..setProperty('checksums'.toJS, <String, Object?>{'md5': 'abc'}.jsify());
  if (includeBody) {
    object.setProperty('body'.toJS, _readableBody(body));
  }
  return object;
}

JSObject _r2Bucket() {
  return JSObject()
    ..setProperty(
      'head'.toJS,
      ((JSString key) => Future<JSAny?>.value(
        _r2Object(key.toDart, 'head', includeBody: false),
      ).toJS).toJS,
    )
    ..setProperty(
      'get'.toJS,
      ((JSString key) => Future<JSAny?>.value(
        _r2Object(key.toDart, 'stored-value'),
      ).toJS).toJS,
    )
    ..setProperty(
      'put'.toJS,
      ((JSString key, JSAny? value, JSAny? options) {
        return Future<JSAny?>.value(
          _r2Object(key.toDart, value?.dartify()?.toString() ?? ''),
        ).toJS;
      }).toJS,
    )
    ..setProperty(
      'delete'.toJS,
      ((JSAny keys) => Future<JSAny?>.value(null).toJS).toJS,
    )
    ..setProperty(
      'list'.toJS,
      ((JSAny? options) => Future<JSAny?>.value(
        JSObject()
          ..setProperty(
            'objects'.toJS,
            <JSObject>[
              _r2Object('documents/a.txt', 'a', includeBody: false),
            ].jsify(),
          )
          ..setProperty('truncated'.toJS, false.toJS)
          ..setProperty('cursor'.toJS, 'next-page'.toJS)
          ..setProperty(
            'delimitedPrefixes'.toJS,
            <String>['documents/'].jsify(),
          ),
      ).toJS).toJS,
    );
}

JSObject _queue() {
  return JSObject()
    ..setProperty(
      'send'.toJS,
      ((JSAny? body, JSAny? options) {
        queueBodies.add(body?.dartify());
        queueOptions.add(options?.dartify());
        return Future<JSAny?>.value(
          <String, Object?>{
            'metadata': <String, Object?>{
              'metrics': <String, Object?>{
                'backlog_count': 3,
                'backlog_bytes': 24,
              },
            },
          }.jsify(),
        ).toJS;
      }).toJS,
    )
    ..setProperty(
      'sendBatch'.toJS,
      ((JSAny messages, JSAny? options) {
        queueBatchMessages.add(messages.dartify());
        queueOptions.add(options?.dartify());
        return Future<JSAny?>.value(
          <String, Object?>{
            'metadata': <String, Object?>{
              'metrics': <String, Object?>{
                'backlogCount': 4,
                'backlogBytes': 32,
              },
            },
          }.jsify(),
        ).toJS;
      }).toJS,
    )
    ..setProperty(
      'metrics'.toJS,
      (() => Future<JSAny?>.value(
        <String, Object?>{
          'backlogCount': 5,
          'backlogBytes': 40,
          'oldestMessageTimestamp': '2026-08-18T12:00:00.000Z',
        }.jsify(),
      ).toJS).toJS,
    );
}

JSObject _serviceBinding() {
  return JSObject()
    ..setProperty(
      'fetch'.toJS,
      ((JSObject request) => Future<JSAny?>.value(
        web.Response(
          'from-service'.toJS,
          web.ResponseInit(
            status: 201,
            headers: <String, Object?>{'x-service': 'yes'}.jsify() as JSObject,
          ),
        ),
      ).toJS).toJS,
    )
    ..setProperty(
      'greet'.toJS,
      ((JSString name) => _thenable('hello ${name.toDart}'.toJS)).toJS,
    );
}

JSObject _thenable(JSAny value) {
  return JSObject()..setProperty(
    'then'.toJS,
    ((JSFunction onFulfilled, [JSFunction? _]) {
      onFulfilled.callAsFunction(null, value);
    }).toJS,
  );
}

JSObject _containerInstance() => JSObject()
  ..setProperty(
    'fetch'.toJS,
    ((JSObject request) => Future<JSAny?>.value(
      web.Response('from-container'.toJS, web.ResponseInit(status: 202)),
    ).toJS).toJS,
  );

JSObject _containerBinding() => JSObject()
  ..setProperty(
    'getByName'.toJS,
    ((JSString sessionId) {
      containerCalls.add('get:${sessionId.toDart}');
      return _containerInstance();
    }).toJS,
  );

JSObject _workflowInstance(String id) => JSObject()
  ..setProperty('id'.toJS, id.toJS)
  ..setProperty(
    'status'.toJS,
    (() => Future<JSAny?>.value(
      <String, Object?>{
        'status': 'complete',
        'output': <String, Object?>{'id': id},
        'rollback': <String, Object?>{'outcome': 'complete', 'error': null},
      }.jsify(),
    ).toJS).toJS,
  )
  ..setProperty(
    'pause'.toJS,
    (() {
      workflowCalls.add('pause:$id');
      return Future<JSAny?>.value(null).toJS;
    }).toJS,
  )
  ..setProperty(
    'resume'.toJS,
    (() {
      workflowCalls.add('resume:$id');
      return Future<JSAny?>.value(null).toJS;
    }).toJS,
  )
  ..setProperty(
    'restart'.toJS,
    ((JSAny? options) {
      workflowCalls.add('restart:$id:${options?.dartify()}');
      return Future<JSAny?>.value(null).toJS;
    }).toJS,
  )
  ..setProperty(
    'terminate'.toJS,
    ((JSAny? options) {
      workflowCalls.add('terminate:$id:${options?.dartify()}');
      return Future<JSAny?>.value(null).toJS;
    }).toJS,
  )
  ..setProperty(
    'sendEvent'.toJS,
    ((JSAny event) {
      workflowCalls.add('event:${event.dartify()}');
      return Future<JSAny?>.value(null).toJS;
    }).toJS,
  );

JSObject _workflowBinding() {
  final first = _workflowInstance('workflow-1');
  return JSObject()
    ..setProperty(
      'create'.toJS,
      (([JSAny? options]) {
        workflowCalls.add('create:${options?.dartify()}');
        return Future<JSAny?>.value(first).toJS;
      }).toJS,
    )
    ..setProperty(
      'createBatch'.toJS,
      ((JSAny options) {
        workflowCalls.add('batch:${options.dartify()}');
        return Future<JSAny?>.value(<JSObject>[first].jsify()).toJS;
      }).toJS,
    )
    ..setProperty(
      'get'.toJS,
      ((JSString id) {
        workflowCalls.add('get:${id.toDart}');
        return Future<JSAny?>.value(_workflowInstance(id.toDart)).toJS;
      }).toJS,
    );
}

JSObject _secretStore() => JSObject()
  ..setProperty(
    'get'.toJS,
    (() => Future<JSAny?>.value('secret-value'.toJS).toJS).toJS,
  );

JSObject _containerProcess() => JSObject()
  ..setProperty('pid'.toJS, 42.toJS)
  ..setProperty('exitCode'.toJS, Future<JSAny?>.value(0.toJS).toJS)
  ..setProperty(
    'output'.toJS,
    (() => Future<JSAny?>.value(
      JSObject()
        ..setProperty('stdout'.toJS, Uint8List.fromList([111, 107]).toJS)
        ..setProperty('stderr'.toJS, Uint8List(0).toJS)
        ..setProperty('exitCode'.toJS, 0.toJS),
    ).toJS).toJS,
  )
  ..setProperty(
    'kill'.toJS,
    (([JSAny? signal]) {
      containerCalls.add('kill:${signal?.dartify()}');
    }).toJS,
  );

JSObject _containerControl() => JSObject()
  ..setProperty('running'.toJS, true.toJS)
  ..setProperty(
    'start'.toJS,
    (([JSAny? options]) {
      containerCalls.add('start:${options?.dartify()}');
    }).toJS,
  )
  ..setProperty(
    'exec'.toJS,
    ((JSAny command, [JSAny? options]) {
      containerCalls.add('exec:${command.dartify()}:${options?.dartify()}');
      return Future<JSAny?>.value(_containerProcess()).toJS;
    }).toJS,
  )
  ..setProperty(
    'destroy'.toJS,
    (([JSAny? error]) {
      containerCalls.add('destroy:${error?.dartify()}');
      return Future<JSAny?>.value(null).toJS;
    }).toJS,
  )
  ..setProperty(
    'signal'.toJS,
    ((JSAny signal) {
      containerCalls.add('signal:${signal.dartify()}');
    }).toJS,
  )
  ..setProperty(
    'monitor'.toJS,
    (() {
      containerCalls.add('monitor');
      return Future<JSAny?>.value(null).toJS;
    }).toJS,
  )
  ..setProperty(
    'getTcpPort'.toJS,
    ((JSAny port) {
      containerCalls.add('port:${port.dartify()}');
      return JSObject()..setProperty(
        'fetch'.toJS,
        ((JSObject request) => Future<JSAny?>.value(
          web.Response('from-port'.toJS, web.ResponseInit(status: 203)),
        ).toJS).toJS,
      );
    }).toJS,
  );

JSObject _cache() {
  return JSObject()
    ..setProperty(
      'match'.toJS,
      ((JSObject request, [JSAny? options]) => Future<JSAny?>.value(
        web.Response(
          'cached-value'.toJS,
          web.ResponseInit(
            headers: <String, Object?>{'x-cache': 'hit'}.jsify() as JSObject,
          ),
        ),
      ).toJS).toJS,
    )
    ..setProperty(
      'put'.toJS,
      ((JSObject request, JSObject response) => Future<JSAny?>.value(
        null,
      ).toJS).toJS,
    )
    ..setProperty(
      'delete'.toJS,
      ((JSObject request, [JSAny? options]) => Future<JSAny?>.value(
        true.toJS,
      ).toJS).toJS,
    );
}

JSObject _webSocket() {
  Object? attachment;
  final socket = JSObject()
    ..setProperty('readyState'.toJS, 1.toJS)
    ..setProperty(
      'send'.toJS,
      ((JSAny value) {
        final dartValue = value.dartify();
        if (dartValue is String) sentWebSocketMessages.add(dartValue);
        if (dartValue is Uint8List) sentWebSocketMessages.add(dartValue);
      }).toJS,
    )
    ..setProperty(
      'close'.toJS,
      ((JSAny? code, JSAny? reason) {
        closedWebSockets.add(
          '${(code?.dartify() as num?)?.toInt() ?? 1000}:${reason?.dartify() ?? ''}',
        );
      }).toJS,
    )
    ..setProperty(
      'serializeAttachment'.toJS,
      ((JSAny? value) {
        attachment = value?.dartify();
      }).toJS,
    )
    ..setProperty(
      'deserializeAttachment'.toJS,
      (() => attachment?.jsify()).toJS,
    );
  return socket;
}

JSObject _durableObjectState(JSObject socket, {JSObject? container}) {
  final state = JSObject()
    ..setProperty('id'.toJS, JSObject())
    ..setProperty('storage'.toJS, JSObject())
    ..setProperty(
      'acceptWebSocket'.toJS,
      ((JSAny value, JSAny? tags) {
        acceptedWebSockets.add(value as JSObject);
      }).toJS,
    )
    ..setProperty('getWebSockets'.toJS, (() => <JSAny>[socket].jsify()).toJS)
    ..setProperty(
      'getTags'.toJS,
      ((JSAny value) => <String>['room'].jsify()).toJS,
    );
  if (container != null) state.setProperty('container'.toJS, container);
  return state;
}

void runCloudflareBindingsRuntimeTests() {
  test('reads text bindings through the public host-neutral helper', () {
    final environment = JSObject()
      ..setProperty('ROUTED_AUTH_TOKEN'.toJS, 'worker-secret'.toJS);
    final env = cloudflare_internal.cloudflareEnvironmentFromJavaScript(
      environment,
    );

    expect(cloudflareTextBinding(env, 'ROUTED_AUTH_TOKEN'), 'worker-secret');
  });

  test('request wrappers hide native Fetch request types', () async {
    final request = createCloudflareRequest(
      'https://example.test/items',
      method: 'POST',
      headers: const {'content-type': 'text/plain'},
      body: 'hello',
    );

    expect(request.method, 'POST');
    expect(request.url, 'https://example.test/items');
    expect(request.headers['content-type'], 'text/plain');
    expect(await request.text(), 'hello');
    expect(request.cf, isEmpty);
  });

  test('R2 buckets expose value bodies and object metadata', () async {
    final environment = JSObject()..setProperty('FILES'.toJS, _r2Bucket());
    final bucket = cloudflare_internal
        .cloudflareEnvironmentFromJavaScript(environment)
        .r2('FILES');

    final stored = await bucket.get('documents/a.txt');
    expect(stored?.key, 'documents/a.txt');
    expect(stored?.size, 12);
    expect(stored?.httpMetadata['contentType'], 'text/plain');
    expect(stored?.customMetadata['source'], 'runtime-test');
    expect(await stored?.readAsString(), 'stored-value');

    final listed = await bucket.list(
      options: const CloudflareR2ListOptions(prefix: 'documents/', limit: 10),
    );
    expect(listed.objects.single.key, 'documents/a.txt');
    expect(listed.cursor, 'next-page');
    expect(listed.delimitedPrefixes, ['documents/']);
    expect(listed.truncated, isFalse);

    final uploaded = await bucket.put(
      'documents/new.txt',
      'new-value',
      options: const CloudflareR2PutOptions(customMetadata: {'source': 'test'}),
    );
    expect(uploaded?.key, 'documents/new.txt');
    await bucket.delete(<String>['documents/new.txt']);
  });

  test('Queues convert messages, options, and metrics', () async {
    queueBodies.clear();
    queueOptions.clear();
    queueBatchMessages.clear();
    final environment = JSObject()..setProperty('EVENTS'.toJS, _queue());
    final queue = cloudflare_internal
        .cloudflareEnvironmentFromJavaScript(environment)
        .queue('EVENTS');

    final sendResult = await queue.send(
      <String, Object?>{'event': 'created'},
      contentType: CloudflareQueueContentType.json,
      delaySeconds: 30,
    );
    expect(sendResult.metrics?.backlogCount, 3);
    expect(queueBodies.single, {'event': 'created'});
    expect(queueOptions.first, {'contentType': 'json', 'delaySeconds': 30});

    final batchResult = await queue.sendBatch(const [
      CloudflareQueueMessage('one'),
      CloudflareQueueMessage(<String, Object?>{
        'id': 2,
      }, contentType: CloudflareQueueContentType.json),
    ], delaySeconds: 5);
    expect(batchResult.metrics?.backlogBytes, 32);
    expect(queueBatchMessages.single, [
      {'body': 'one'},
      {
        'body': {'id': 2},
        'contentType': 'json',
      },
    ]);

    final metrics = await queue.metrics();
    expect(metrics.backlogCount, 5);
    expect(metrics.backlogBytes, 40);
    expect(metrics.oldestMessageTimestamp, DateTime.utc(2026, 8, 18, 12));
  });

  test('service bindings and Cache API stay host-neutral', () async {
    final environment = JSObject()..setProperty('API'.toJS, _serviceBinding());
    final env = cloudflare_internal.cloudflareEnvironmentFromJavaScript(
      environment,
    );
    final request = createCloudflareRequest('https://example.test/service');
    final serviceResponse = await env.service('API').fetch(request);
    expect(serviceResponse.status, 201);
    expect(serviceResponse.headers['x-service'], 'yes');
    expect(serviceResponse.text(), 'from-service');
    expect(await env.worker('API').call<String>('greet', ['Ada']), 'hello Ada');

    final defaultCache = _cache();
    globalContext.setProperty(
      'caches'.toJS,
      JSObject()
        ..setProperty('default'.toJS, defaultCache)
        ..setProperty(
          'open'.toJS,
          ((JSString name) => Future<JSAny?>.value(defaultCache).toJS).toJS,
        ),
    );
    final cache = await cloudflareCache();
    final namedCache = await cloudflareCache(name: 'assets');
    expect(namedCache, isA<CloudflareCache>());
    final cached = await cache.match(request);
    expect(cached?.status, 200);
    expect(cached?.headers['x-cache'], 'hit');
    expect(cached?.text(), 'cached-value');
    await cache.put(request, CloudflareResponse.text('new-value'));
    expect(await cache.delete(request, ignoreMethod: true), isTrue);
  });

  test('Containers, Workflows, and Secrets Store stay host-neutral', () async {
    workflowCalls.clear();
    containerCalls.clear();
    final environment = JSObject()
      ..setProperty('CONTAINER'.toJS, _containerBinding())
      ..setProperty('WORKFLOW'.toJS, _workflowBinding())
      ..setProperty('ACCOUNT_SECRET'.toJS, _secretStore());
    final env = cloudflare_internal.cloudflareEnvironmentFromJavaScript(
      environment,
    );

    final request = createCloudflareRequest('https://example.test/container');
    final containerResponse = await env
        .container('CONTAINER')
        .get('session-1')
        .fetch(request);
    expect(containerResponse.status, 202);
    expect(containerResponse.text(), 'from-container');
    expect(containerCalls, ['get:session-1']);

    final secret = await env.secretsStore('ACCOUNT_SECRET').get();
    expect(secret, 'secret-value');

    final workflow = env.workflow('WORKFLOW');
    final instance = await workflow.create(
      options: const CloudflareWorkflowCreateOptions(
        id: 'order-1',
        params: <String, Object?>{'orderId': 7},
        successRetention: '1 day',
      ),
    );
    expect(instance.id, 'workflow-1');
    final status = await instance.status();
    expect(status.status, 'complete');
    expect(status.output, {'id': 'workflow-1'});
    expect(status.rollback?.outcome, 'complete');
    await instance.pause();
    await instance.resume();
    await instance.restart(
      options: const CloudflareWorkflowRestartOptions(
        from: CloudflareWorkflowStepReference(name: 'charge', count: 2),
      ),
    );
    await instance.terminate(
      options: const CloudflareWorkflowTerminateOptions(rollback: true),
    );
    await instance.sendEvent(type: 'payment-received', payload: {'id': 7});
    expect(workflowCalls, hasLength(6));
    expect(workflowCalls[0], contains('create:'));
    expect(workflowCalls.last, contains('payment-received'));

    final batch = await workflow.createBatch(const [
      CloudflareWorkflowCreateOptions(id: 'order-2'),
    ]);
    expect(batch.single.id, 'workflow-1');
    expect((await workflow.get('workflow-3')).id, 'workflow-3');

    final state = cloudflare_internal
        .cloudflareDurableObjectStateFromJavaScript(
          _durableObjectState(_webSocket(), container: _containerControl()),
        );
    final controls = state.container;
    expect(controls?.running, isTrue);
    controls?.start(
      options: const CloudflareContainerStartOptions(
        environment: {'MODE': 'test'},
        entrypoint: ['server'],
        enableInternet: false,
      ),
    );
    final process = await controls?.exec(
      ['echo', 'ok'],
      options: const CloudflareContainerExecOptions(
        stderr: CloudflareContainerStreamMode.combined,
      ),
    );
    expect(process?.pid, 42);
    expect(await process?.exitCode, 0);
    expect((await process?.output())?.stdoutText, 'ok');
    process?.kill(15);
    final port = controls?.getTcpPort(8080);
    final portResponse = await port?.fetch(request);
    expect(portResponse?.status, 203);
    await controls?.destroy('test complete');
    controls?.signal(9);
    await controls?.monitor();
    expect(containerCalls, contains(startsWith('exec:[echo, ok]:')));
    expect(containerCalls, contains('port:8080'));
  });

  test('D1 and Durable Object bindings wrap native Worker objects', () async {
    final environment = JSObject()
      ..setProperty('DB'.toJS, _d1Database())
      ..setProperty('COUNTER'.toJS, _durableObjectNamespace());
    final env = cloudflare_internal.cloudflareEnvironmentFromJavaScript(
      environment,
    );

    final row = await env
        .d1('DB')
        .prepare('SELECT id, email FROM users WHERE id = ?')
        .bind([42])
        .first<Map<String, Object?>>();
    expect(row?['id'], 42);
    expect(row?['email'], 'user@example.test');

    final result = await env
        .d1('DB')
        .prepare('SELECT id, email FROM users')
        .all<Map<String, Object?>>();
    expect(result.success, isTrue);
    expect(result.results.single['id'], 42);
    expect(result.meta?.rowsRead, 1);
    expect(result.meta?.rowsWritten, 1);

    final id = env.durableObjectNamespace('COUNTER').getByName('global').id;
    expect(id.name, 'global');
    expect(id.toString(), 'global-id');

    final state = JSObject()
      ..setProperty('id'.toJS, JSObject())
      ..setProperty('storage'.toJS, JSObject());
    final objectEnvironment = JSObject();
    defineCloudflareDurableObjects({
      'Counter': (state, environment) => _TestDurableObject(state, environment),
    });
    final registry =
        globalContext.getProperty(cloudflareDurableObjectRegistryName.toJS)
            as JSObject;
    final constructor = registry.getProperty('Counter'.toJS) as JSFunction;
    final delegate =
        constructor.callAsFunction(null, state, objectEnvironment) as JSObject;
    final response =
        (delegate.getProperty('fetch'.toJS) as JSFunction).callAsFunction(
              delegate,
              web.Request('https://example.test'.toJS),
            )
            as web.Response;
    expect((await response.text().toDart).toDart, 'GET');
  });

  test('Durable Object hibernation sockets stay host-neutral', () {
    sentWebSocketMessages.clear();
    closedWebSockets.clear();
    acceptedWebSockets.clear();

    final nativeSocket = _webSocket();
    final state = cloudflare_internal
        .cloudflareDurableObjectStateFromJavaScript(
          _durableObjectState(nativeSocket),
        );
    final socket = state.getWebSockets().single;

    socket.send('hello');
    socket.send(Uint8List.fromList([1, 2]));
    socket.serializeAttachment(<String, Object?>{'room': 'one'});
    final attachment = socket.deserializeAttachment<Map<String, Object?>>();
    socket.close(1001, 'going away');
    state.acceptWebSocket(socket, tags: const ['room']);

    expect(socket.readyState, 1);
    expect(sentWebSocketMessages, <Object>[
      'hello',
      Uint8List.fromList([1, 2]),
    ]);
    expect(attachment?['room'], 'one');
    expect(closedWebSockets, ['1001:going away']);
    expect(acceptedWebSockets.single, same(nativeSocket));
    expect(state.getTags(socket), ['room']);
  });

  test('WebSocketPair is converted to a host-neutral upgrade response', () {
    globalContext.setProperty(
      'WebSocketPair'.toJS,
      (() {
        return JSObject()
          ..setProperty('0'.toJS, _webSocket())
          ..setProperty('1'.toJS, _webSocket());
      }).toJS,
    );

    final pair = cloudflareWebSocketPair();
    expect(pair.client, isA<CloudflareWebSocket>());
    expect(pair.server, isA<CloudflareWebSocket>());
    expect(pair.response.status, 101);
    expect(pair.response.webSocket, same(pair.client));
  });

  test('Durable Object registry forwards hibernation callbacks', () {
    durableObjectMessages.clear();
    durableObjectCloses.clear();
    durableObjectErrors.clear();

    final state = _durableObjectState(_webSocket());
    defineCloudflareDurableObjects({
      'Counter': (state, environment) => _TestDurableObject(state, environment),
    });
    final registry =
        globalContext.getProperty(cloudflareDurableObjectRegistryName.toJS)
            as JSObject;
    final constructor = registry.getProperty('Counter'.toJS) as JSFunction;
    final delegate =
        constructor.callAsFunction(null, state, JSObject()) as JSObject;
    final socket = _webSocket();
    final messageHandler =
        delegate.getProperty('webSocketMessage'.toJS) as JSFunction;
    messageHandler.callAsFunction(delegate, socket, 'hello'.toJS);
    final closeHandler =
        delegate.getProperty('webSocketClose'.toJS) as JSFunction;
    closeHandler.callAsFunction(
      delegate,
      socket,
      1000.toJS,
      'done'.toJS,
      true.toJS,
    );
    final errorHandler =
        delegate.getProperty('webSocketError'.toJS) as JSFunction;
    errorHandler.callAsFunction(delegate, socket, 'boom'.toJS);

    expect(durableObjectMessages, ['hello']);
    expect(durableObjectCloses, ['1000:done:true']);
    expect(durableObjectErrors, ['boom']);
  });
}

final class _TestDurableObject extends CloudflareDurableObject {
  const _TestDurableObject(super.state, super.env);

  @override
  CloudflareResponse fetch(CloudflareRequest request) =>
      CloudflareResponse.text(request.method);

  @override
  void webSocketMessage(CloudflareWebSocket webSocket, Object message) {
    durableObjectMessages.add(message);
  }

  @override
  void webSocketClose(
    CloudflareWebSocket webSocket,
    int code,
    String reason,
    bool wasClean,
  ) {
    durableObjectCloses.add('$code:$reason:$wasClean');
  }

  @override
  void webSocketError(CloudflareWebSocket webSocket, Object error) {
    durableObjectErrors.add(error);
  }
}
