library;

import 'package:routed_core/routed_core.dart';

import 'src/fetch/fetch_entry.dart';
import 'src/runtime/runtime.dart';

export 'src/runtime/runtime.dart'
    show
        RoutedNodeCapabilities,
        RoutedNodeContext,
        RoutedNodeEntryModel,
        RoutedNodeExtension,
        RoutedNodeRuntime,
        RoutedNodeRuntimeInfo,
        netlifyCapabilities;
export 'src/runtime/lifecycle.dart';
export 'src/fetch/fetch_exchange.dart';
export 'src/fetch/web_fetch_adapter.dart';
export 'src/fetch/fetch_entry.dart'
    show defineFetchExport, defineFetchExportAsync;

/// Installs the Netlify Fetch bootstrap function.
void defineNetlifyFetch(Object engine) {
  defineFetchExport(
    'Netlify',
    engine as Engine,
    capabilities: netlifyCapabilities,
  );
}

/// Installs a Netlify Fetch export from an asynchronously-built engine.
void defineNetlifyFetchAsync(Future<Engine> engine) {
  defineFetchExportAsync('Netlify', engine, capabilities: netlifyCapabilities);
}
