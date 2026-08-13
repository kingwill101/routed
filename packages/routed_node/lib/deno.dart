library;

export 'src/runtime/runtime.dart'
    show
        RoutedNodeCapabilities,
        RoutedNodeContext,
        RoutedNodeEntryModel,
        RoutedNodeExtension,
        RoutedNodeRuntime,
        RoutedNodeRuntimeInfo,
        denoCapabilities;
export 'src/runtime/lifecycle.dart';

/// Placeholder for the Deno listener implementation.
Never serveDeno(Object engine, {String host = '0.0.0.0', int port = 0}) {
  throw UnsupportedError(
    'Deno support is not implemented yet. This entrypoint is reserved for the '
    'Deno.serve adapter.',
  );
}
