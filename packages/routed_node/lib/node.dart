/// Node.js runtime metadata and the native listener entrypoint for Routed.
library;

export 'src/runtime/runtime.dart'
    show
        RoutedNodeCapabilities,
        RoutedNodeContext,
        RoutedNodeEntryModel,
        RoutedNodeExtension,
        RoutedNodeRuntime,
        RoutedNodeRuntimeInfo,
        NodeRuntimeExtension,
        nodeCapabilities;
export 'src/runtime/lifecycle.dart';
export 'src/node_environment.dart' show NodeRuntimeEnvironment;
export 'src/server_boot.dart' show serveNode;
export 'src/node_runtime.dart' show keepNodeEventLoopAlive;
