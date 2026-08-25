/// Cloudflare Workers adapters, typed bindings, and Fetch entrypoints.
///
/// The public types in this library keep Cloudflare's JavaScript objects
/// behind a host-neutral Dart boundary. Application code can use the typed
/// bindings without importing `package:web` or `dart:js_interop`.
///
/// {@canonicalFor fetch_entry_stub.defineFetchExport}
/// {@canonicalFor fetch_entry_stub.defineFetchExportAsync}
/// {@canonicalFor fetch_entry_stub.defineFetchExportFactoryAsync}
/// {@canonicalFor fetch_entry_stub.defineFetchExportFactoryWithEnvironmentAsync}
library;

import 'package:routed_core/routed_core.dart';

import 'src/cloudflare/cloudflare_bindings_stub.dart'
    if (dart.library.js_interop) 'src/cloudflare/cloudflare_bindings_js.dart'
    as cloudflare_bindings;
import 'src/cloudflare/cloudflare_types.dart';
import 'src/fetch/fetch_entry.dart';
import 'src/runtime/runtime.dart';

export 'src/cloudflare/cloudflare_types.dart';
export 'src/cloudflare/cloudflare_durable_object_store.dart';
export 'src/cloudflare/cloudflare_bindings_stub.dart'
    if (dart.library.js_interop) 'src/cloudflare/cloudflare_bindings_js.dart'
    show
        cloudflareEnvironmentOf,
        cloudflareTextBinding,
        cloudflareRequestOf,
        createCloudflareRequest,
        cloudflareCache,
        cloudflareWebSocketPair,
        cloudflareExecutionContextOf,
        defineCloudflareDurableObjects;
export 'src/runtime/runtime.dart'
    show
        RoutedNodeCapabilities,
        RoutedNodeContext,
        RoutedNodeEntryModel,
        RoutedNodeExtension,
        RoutedNodeRuntime,
        RoutedNodeRuntimeInfo,
        cloudflareCapabilities;
export 'src/runtime/lifecycle.dart';
export 'src/fetch/fetch_exchange.dart';
export 'src/fetch/web_fetch_adapter.dart';
export 'src/fetch/fetch_entry.dart'
    show
        defineFetchExport,
        defineFetchExportAsync,
        defineFetchExportFactoryAsync,
        defineFetchExportFactoryWithEnvironmentAsync;

/// Installs the Cloudflare Fetch bootstrap function.
void defineCloudflareFetch(Object engine) {
  defineFetchExport(
    'Cloudflare',
    engine as Engine,
    capabilities: cloudflareCapabilities,
  );
}

/// Installs a Cloudflare Fetch export from an asynchronously-built engine.
void defineCloudflareFetchAsync(Future<Engine> engine) {
  defineFetchExportAsync(
    'Cloudflare',
    engine,
    capabilities: cloudflareCapabilities,
  );
}

/// Installs a Cloudflare Fetch entry whose engine is initialized lazily per
/// Worker isolate, on the first request.
void defineCloudflareFetchFactoryAsync(Future<Engine> Function() factory) {
  defineFetchExportFactoryAsync(
    'Cloudflare',
    factory,
    capabilities: cloudflareCapabilities,
  );
}

/// Installs a lazy Cloudflare Fetch entry whose engine is built with the
/// Worker environment and its typed D1, KV, R2, or secret bindings.
///
/// The factory runs once per Worker isolate, on the first request. The
/// environment is wrapped before it reaches application code, so Cloudflare
/// applications do not need to use `package:web` or JS interop directly.
void defineCloudflareFetchFactoryWithEnvironmentAsync(
  Future<Engine> Function(CloudflareEnvironment environment) factory,
) {
  defineFetchExportFactoryWithEnvironmentAsync('Cloudflare', (environment) {
    if (environment == null) {
      throw StateError('Cloudflare Worker environment was not provided.');
    }
    return factory(
      cloudflare_bindings.cloudflareEnvironmentFromJavaScript(environment),
    );
  }, capabilities: cloudflareCapabilities);
}
