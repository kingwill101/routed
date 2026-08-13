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
        vercelCapabilities;
export 'src/runtime/lifecycle.dart';
export 'src/fetch/fetch_exchange.dart';
export 'src/fetch/web_fetch_adapter.dart';

/// Installs the Vercel Fetch bootstrap function.
void defineVercelFetch(Object engine) {
  defineFetchExport(
    'Vercel',
    engine as Engine,
    capabilities: vercelCapabilities,
  );
}
