library;

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

/// Placeholder for the Netlify fetch/function export implementation.
Never defineNetlifyFetch(Object engine) {
  throw UnsupportedError(
    'Netlify support is not implemented yet. This entrypoint is reserved for '
    'the Netlify function adapter.',
  );
}
