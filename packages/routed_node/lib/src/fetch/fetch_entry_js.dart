@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';
import 'package:web/web.dart' as web;

import '../runtime/lifecycle.dart';
import '../runtime/runtime.dart';
import 'fetch_exchange.dart';
import 'web_fetch_adapter_js.dart';

const defaultRoutedFetchEntryName = '__routed_fetch__';

/// Installs a native Fetch export for a JavaScript host runtime.
void defineFetchExport(
  String runtime,
  Engine engine, {
  required RoutedNodeCapabilities capabilities,
  String name = defaultRoutedFetchEntryName,
}) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Fetch entry name must not be empty',
    );
  }

  final info = RoutedNodeRuntimeInfo(
    runtime: capabilities.runtime,
    capabilities: capabilities,
  );
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.bootRequested,
      info: info,
    ),
  );

  final handler = ((JSAny request, [JSAny? context, JSAny? environment]) {
    return handleNativeFetch(
      engine,
      info,
      web.Request(request),
      context: context,
      environment: environment,
    ).toJS;
  }).toJS;

  globalContext.setProperty(name.toJS, handler);
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(phase: RoutedNodeLifecyclePhase.ready, info: info),
  );
}

/// Installs a Fetch export whose engine is initialized asynchronously.
///
/// This is the safe entrypoint for generated Worker modules: the native
/// handler is installed immediately, while each request waits for the single
/// shared engine future to complete.
void defineFetchExportAsync(
  String runtime,
  Future<Engine> engineFuture, {
  required RoutedNodeCapabilities capabilities,
  String name = defaultRoutedFetchEntryName,
}) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Fetch entry name must not be empty',
    );
  }

  final info = RoutedNodeRuntimeInfo(
    runtime: capabilities.runtime,
    capabilities: capabilities,
  );
  final handler = ((JSAny request, [JSAny? context, JSAny? environment]) {
    return _handleNativeFetchAfterEngine(
      engineFuture,
      info,
      web.Request(request),
      context: context,
      environment: environment,
    ).toJS;
  }).toJS;
  globalContext.setProperty(name.toJS, handler);
}

Future<web.Response> _handleNativeFetchAfterEngine(
  Future<Engine> engineFuture,
  RoutedNodeRuntimeInfo info,
  web.Request request, {
  JSAny? context,
  JSAny? environment,
}) async {
  try {
    final engine = await engineFuture;
    return await handleNativeFetch(
      engine,
      info,
      request,
      context: context,
      environment: environment,
    );
  } catch (_) {
    return web.Response(
      'Internal Server Error'.toJS,
      web.ResponseInit(status: 500, statusText: 'Internal Server Error'),
    );
  }
}

/// Handles one native Fetch request and returns a native Fetch response.
Future<web.Response> handleNativeFetch(
  Engine engine,
  RoutedNodeRuntimeInfo info,
  web.Request request, {
  JSAny? context,
  JSAny? environment,
}) async {
  try {
    final hostContext = RoutedNodeContext(
      info: info,
      extension: FetchRuntimeExtension(
        runtime: info.runtime,
        request: request,
        executionContext: context,
        environment: environment,
      ),
    );
    final view = WebFetchRequest(request, hostContext: hostContext);
    final streaming = WebStreamingResponseAdapter();
    final dispatch = dispatchFetchConnection(
      engine,
      view,
      streaming,
      runtime: info,
    );
    unawaited(
      dispatch.catchError((Object error, StackTrace stackTrace) {
        streaming.fail(error, stackTrace);
      }),
    );
    await streaming.headersReady;
    return webResponseFromStreamingAdapter(streaming);
  } catch (_) {
    return web.Response(
      'Internal Server Error'.toJS,
      web.ResponseInit(status: 500, statusText: 'Internal Server Error'),
    );
  }
}
