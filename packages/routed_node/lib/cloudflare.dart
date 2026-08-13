library;

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

/// Placeholder for the Cloudflare Fetch export implementation.
Never defineCloudflareFetch(Object engine) {
  throw UnsupportedError(
    'Cloudflare support is not implemented yet. This entrypoint is reserved '
    'for the Workers fetch adapter.',
  );
}
