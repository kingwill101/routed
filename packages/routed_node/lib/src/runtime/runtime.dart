/// Whether a host owns a long-lived listener or invokes a fetch export.
enum RoutedNodeEntryModel {
  /// The host owns a long-lived listener.
  listener,

  /// The host invokes a Fetch-style export for each request.
  fetchExport,
}

/// Runtime families supported by `routed_node`.
enum RoutedNodeRuntime {
  /// Node.js runtime.
  node,

  /// Bun runtime.
  bun,

  /// Deno runtime.
  deno,

  /// Cloudflare Workers runtime.
  cloudflare,

  /// Vercel runtime.
  vercel,

  /// Netlify runtime.
  netlify,
}

/// Capabilities declared by one host invocation.
final class RoutedNodeCapabilities {
  /// Describes the features available from a host adapter.
  const RoutedNodeCapabilities({
    required this.runtime,
    required this.entryModel,
    required this.streaming,
    required this.bufferedResponses,
    required this.webSocket,
    required this.fileSystem,
    required this.backgroundWork,
  });

  /// The runtime family that owns the current request.
  final RoutedNodeRuntime runtime;

  /// Whether the host owns a listener or invokes a Fetch export.
  final RoutedNodeEntryModel entryModel;

  /// Whether the adapter can stream response bodies.
  final bool streaming;

  /// Whether the adapter supports the buffered portable response path.
  final bool bufferedResponses;

  /// Whether the host can accept WebSocket upgrades.
  final bool webSocket;

  /// Whether application code can use a host filesystem through this entrypoint.
  final bool fileSystem;

  /// Whether the host supports work that continues after a response.
  final bool backgroundWork;
}

/// Common runtime metadata exposed by a host adapter.
final class RoutedNodeRuntimeInfo {
  /// Creates runtime metadata for a host invocation.
  const RoutedNodeRuntimeInfo({
    required this.runtime,
    required this.capabilities,
  });

  /// The runtime family represented by this metadata.
  final RoutedNodeRuntime runtime;

  /// The feature set declared by the host adapter.
  final RoutedNodeCapabilities capabilities;
}

/// A typed lookup for host-owned request context values.
abstract interface class RoutedNodeExtension {
  /// The runtime family that owns this extension.
  RoutedNodeRuntime get runtime;
}

/// Host-native Node request, response, and server handles.
final class NodeRuntimeExtension implements RoutedNodeExtension {
  /// Captures Node request, response, and server handles.
  const NodeRuntimeExtension({this.request, this.response, this.server});

  /// The host-native request handle, when the adapter exposes one.
  final Object? request;

  /// The host-native response handle, when the adapter exposes one.
  final Object? response;

  /// The host-native server handle, when the adapter exposes one.
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.node;
}

/// Host-native Vercel Node.js request, response, and server handles.
final class VercelNodeRuntimeExtension implements RoutedNodeExtension {
  /// Captures Vercel's Node request, response, and server handles.
  const VercelNodeRuntimeExtension({this.request, this.response, this.server});

  /// The Vercel Node request handle, when available.
  final Object? request;

  /// The Vercel Node response handle, when available.
  final Object? response;

  /// The Vercel Node server handle, when available.
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.vercel;
}

/// Host-native Bun request and server handles.
final class BunRuntimeExtension implements RoutedNodeExtension {
  /// Captures Bun request and server handles.
  const BunRuntimeExtension({this.request, this.server});

  /// The Bun request handle, when available.
  final Object? request;

  /// The Bun server handle, when available.
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.bun;
}

/// Host-native Deno request and server handles.
final class DenoRuntimeExtension implements RoutedNodeExtension {
  /// Captures Deno request and server handles.
  const DenoRuntimeExtension({this.request, this.server});

  /// The Deno request handle, when available.
  final Object? request;

  /// The Deno server handle, when available.
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.deno;
}

/// Host-native Fetch request and execution context handles.
final class FetchRuntimeExtension implements RoutedNodeExtension {
  /// Creates a FetchRuntimeExtension value.
  const FetchRuntimeExtension({
    required this.runtime,
    this.request,
    this.executionContext,
    this.environment,
  });

  @override
  final RoutedNodeRuntime runtime;

  /// The host-native Fetch request handle, when available.
  final Object? request;

  /// The host execution context, when the platform supplies one.
  final Object? executionContext;

  /// The host environment or binding object, when available.
  final Object? environment;
}

/// Runtime-scoped host context carried through a Routed request.
final class RoutedNodeContext {
  /// Creates request-scoped runtime metadata and an optional extension.
  const RoutedNodeContext({required this.info, this.extension});

  /// The runtime and capabilities for the current host invocation.
  final RoutedNodeRuntimeInfo info;

  /// The optional host-specific handles for the current request.
  final RoutedNodeExtension? extension;

  /// Returns the host extension when it has type [T].
  T? extensionAs<T extends RoutedNodeExtension>() {
    final value = extension;
    return value is T ? value : null;
  }
}

/// Capabilities advertised by the Node listener adapter.
const RoutedNodeCapabilities nodeCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.node,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

/// Capabilities advertised by the Bun listener adapter.
const RoutedNodeCapabilities bunCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.bun,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

/// Capabilities advertised by the Deno listener adapter.
const RoutedNodeCapabilities denoCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.deno,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

/// Capabilities advertised by the Cloudflare Workers Fetch adapter.
const RoutedNodeCapabilities cloudflareCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.cloudflare,
  entryModel: RoutedNodeEntryModel.fetchExport,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: false,
  backgroundWork: false,
);

/// Capabilities advertised by the Vercel Fetch adapter.
const RoutedNodeCapabilities vercelCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.vercel,
  entryModel: RoutedNodeEntryModel.fetchExport,
  streaming: true,
  bufferedResponses: true,
  webSocket: false,
  fileSystem: false,
  backgroundWork: false,
);

/// Vercel Node Functions use the vendor's request-context upgrade boundary
/// and the `ws` server implementation for native WebSocket connections.
const RoutedNodeCapabilities vercelNodeCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.vercel,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: false,
  backgroundWork: false,
);

/// Netlify Edge Functions expose Fetch-style request/response handlers, but
/// Netlify does not provide a server-side socket upgrade boundary to the Edge
/// Function. Real-time connections must use a managed WebSocket provider (for
/// example Ably) or a separate WebSocket service.
const RoutedNodeCapabilities netlifyCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.netlify,
  entryModel: RoutedNodeEntryModel.fetchExport,
  streaming: true,
  bufferedResponses: true,
  webSocket: false,
  fileSystem: false,
  backgroundWork: false,
);
