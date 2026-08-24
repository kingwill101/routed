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
  /// Creates a RoutedNodeCapabilities value.
  const RoutedNodeCapabilities({
    required this.runtime,
    required this.entryModel,
    required this.streaming,
    required this.bufferedResponses,
    required this.webSocket,
    required this.fileSystem,
    required this.backgroundWork,
  });

  /// The runtime value.
  final RoutedNodeRuntime runtime;

  /// The entryModel value.
  final RoutedNodeEntryModel entryModel;

  /// The streaming value.
  final bool streaming;

  /// The bufferedResponses value.
  final bool bufferedResponses;

  /// The webSocket value.
  final bool webSocket;

  /// The fileSystem value.
  final bool fileSystem;

  /// The backgroundWork value.
  final bool backgroundWork;
}

/// Common runtime metadata exposed by a host adapter.
final class RoutedNodeRuntimeInfo {
  /// Creates a RoutedNodeRuntimeInfo value.
  const RoutedNodeRuntimeInfo({
    required this.runtime,
    required this.capabilities,
  });

  /// The runtime value.
  final RoutedNodeRuntime runtime;

  /// The capabilities value.
  final RoutedNodeCapabilities capabilities;
}

/// A typed lookup for host-owned request context values.
abstract interface class RoutedNodeExtension {
  /// The runtime value.
  RoutedNodeRuntime get runtime;
}

/// Host-native Node request, response, and server handles.
final class NodeRuntimeExtension implements RoutedNodeExtension {
  /// Creates a NodeRuntimeExtension value.
  const NodeRuntimeExtension({this.request, this.response, this.server});

  /// The request value.
  final Object? request;

  /// The response value.
  final Object? response;

  /// The server value.
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.node;
}

/// Host-native Vercel Node.js request, response, and server handles.
final class VercelNodeRuntimeExtension implements RoutedNodeExtension {
  /// Creates a VercelNodeRuntimeExtension value.
  const VercelNodeRuntimeExtension({this.request, this.response, this.server});

  /// The request value.
  final Object? request;

  /// The response value.
  final Object? response;

  /// The server value.
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.vercel;
}

/// Host-native Bun request and server handles.
final class BunRuntimeExtension implements RoutedNodeExtension {
  /// Creates a BunRuntimeExtension value.
  const BunRuntimeExtension({this.request, this.server});

  /// The request value.
  final Object? request;

  /// The server value.
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.bun;
}

/// Host-native Deno request and server handles.
final class DenoRuntimeExtension implements RoutedNodeExtension {
  /// Creates a DenoRuntimeExtension value.
  const DenoRuntimeExtension({this.request, this.server});

  /// The request value.
  final Object? request;

  /// The server value.
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

  /// The request value.
  final Object? request;

  /// The executionContext value.
  final Object? executionContext;

  /// The environment value.
  final Object? environment;
}

/// Runtime-scoped host context carried through a Routed request.
final class RoutedNodeContext {
  /// Creates a RoutedNodeContext value.
  const RoutedNodeContext({required this.info, this.extension});

  /// The info value.
  final RoutedNodeRuntimeInfo info;

  /// The extension value.
  final RoutedNodeExtension? extension;

  /// Provides the declared host integration API member.
  T? extensionAs<T extends RoutedNodeExtension>() {
    final value = extension;
    return value is T ? value : null;
  }
}

/// Provides the declared host integration API member.
const RoutedNodeCapabilities nodeCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.node,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

/// Provides the declared host integration API member.
const RoutedNodeCapabilities bunCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.bun,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

/// Provides the declared host integration API member.
const RoutedNodeCapabilities denoCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.deno,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

/// Provides the declared host integration API member.
const RoutedNodeCapabilities cloudflareCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.cloudflare,
  entryModel: RoutedNodeEntryModel.fetchExport,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: false,
  backgroundWork: false,
);

/// Provides the declared host integration API member.
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
