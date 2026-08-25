/// Vercel Fetch and Node.js adapters for Routed applications.
///
/// Use the Fetch entrypoints for Vercel Edge-style handlers and the Node
/// entrypoints when Vercel captures a native Node.js server handler.
library;

import 'package:routed_core/routed_core.dart';
import 'package:web/web.dart' as web;

import 'src/fetch/fetch_entry.dart';
import 'src/runtime/runtime.dart';
import 'src/vercel_node_runtime.dart';

export 'src/runtime/runtime.dart'
    show
        RoutedNodeCapabilities,
        RoutedNodeContext,
        RoutedNodeEntryModel,
        RoutedNodeExtension,
        RoutedNodeRuntime,
        RoutedNodeRuntimeInfo,
        vercelCapabilities,
        vercelNodeCapabilities,
        VercelNodeRuntimeExtension;
export 'src/runtime/lifecycle.dart';
export 'src/fetch/fetch_exchange.dart';
export 'src/fetch/web_fetch_adapter.dart';
export 'src/fetch/fetch_entry.dart'
    show
        defineFetchExport,
        defineFetchExportAsync,
        defineFetchExportFactoryAsync;
export 'src/node_views.dart'
    show NodeIncomingView, NodeServerResponseView, NodeWebSocketSocketView;
export 'src/node_websocket.dart'
    show NodeRoutedWebSocket, NodeWebSocketUpgradeResponse;

/// Installs the Vercel Fetch bootstrap function.
void defineVercelFetch(Object engine) {
  defineFetchExport(
    'Vercel',
    engine as Engine,
    capabilities: vercelCapabilities,
  );
}

/// Installs a Vercel Fetch export from an asynchronously-built engine.
void defineVercelFetchAsync(Future<Engine> engine) {
  defineFetchExportAsync('Vercel', engine, capabilities: vercelCapabilities);
}

/// Installs a Vercel Fetch entry whose engine is created lazily on request.
void defineVercelFetchFactoryAsync(Future<Engine> Function() factory) {
  defineFetchExportFactoryAsync(
    'Vercel',
    factory,
    capabilities: vercelCapabilities,
  );
}

/// Installs a Vercel Node.js server entrypoint with native WebSocket upgrades.
///
/// This is for Vercel's captured Node.js server runtime, not the Edge Fetch
/// runtime installed by [defineVercelFetch].
void defineVercelNodeHandler(Engine engine) {
  defineVercelNodeHandlerRuntime(engine);
}

/// Installs a Vercel Node.js handler with lazy engine initialization.
void defineVercelNodeHandlerFactory(Future<Engine> Function() factory) {
  defineVercelNodeHandlerFactoryRuntime(factory);
}

/// Vercel request metadata exposed by the platform's `x-vercel-*` headers.
///
/// This is the Routed equivalent of Dart Edge's `request.vc` properties. The
/// values are optional because they are not present for every request or local
/// development environment.
final class VercelRequestProperties {
  /// Creates a VercelRequestProperties value.
  const VercelRequestProperties(this.request);

  /// Provides the declared host integration API member.
  final web.Request request;

  /// Client IP address reported by Vercel, when available.
  String? get ipAddress => request.headers.get('x-real-ip');

  /// Client city reported by Vercel, when available.
  String? get city => request.headers.get('x-vercel-ip-city');

  /// Client country code reported by Vercel, when available.
  String? get country => request.headers.get('x-vercel-ip-country');

  /// Vercel region inferred from the request identifier.
  String? get region {
    final requestId = request.headers.get('x-vercel-id');
    if (requestId == null || requestId.isEmpty) return 'dev1';
    return requestId.split(':').first;
  }

  /// Client country or state region reported by Vercel.
  String? get countryRegion =>
      request.headers.get('x-vercel-ip-country-region');

  /// Client latitude reported by Vercel, when available.
  String? get latitude => request.headers.get('x-vercel-ip-latitude');

  /// Client longitude reported by Vercel, when available.
  String? get longitude => request.headers.get('x-vercel-ip-longitude');
}

/// Returns Vercel metadata for a request handled by the Vercel Fetch entry.
extension RoutedVercelRequest on Request {
  /// Vercel request metadata for this Fetch request, when available.
  VercelRequestProperties? get vc {
    final context = hostContext;
    if (context is! RoutedNodeContext ||
        context.info.runtime != RoutedNodeRuntime.vercel) {
      return null;
    }
    final extension = context.extension;
    if (extension is! FetchRuntimeExtension || extension.request == null) {
      return null;
    }
    return VercelRequestProperties(extension.request! as web.Request);
  }
}
