library;

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

/// Placeholder for the Vercel fetch/function export implementation.
Never defineVercelFetch(Object engine) {
  throw UnsupportedError(
    'Vercel support is not implemented yet. This entrypoint is reserved for '
    'the Vercel function adapter.',
  );
}
