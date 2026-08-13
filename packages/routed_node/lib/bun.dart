library;

export 'src/runtime/runtime.dart'
    show
        RoutedNodeCapabilities,
        RoutedNodeContext,
        RoutedNodeEntryModel,
        RoutedNodeExtension,
        RoutedNodeRuntime,
        RoutedNodeRuntimeInfo,
        bunCapabilities;
export 'src/runtime/lifecycle.dart';

/// Placeholder for the Bun listener implementation.
Never serveBun(Object engine, {String host = '0.0.0.0', int port = 0}) {
  throw UnsupportedError(
    'Bun support is not implemented yet. This entrypoint is reserved for the '
    'Bun.serve adapter.',
  );
}
