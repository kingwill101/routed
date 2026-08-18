/// Whether a host owns a long-lived listener or invokes a fetch export.
enum RoutedNodeEntryModel { listener, fetchExport }

/// Runtime families supported by `routed_node`.
enum RoutedNodeRuntime { node, bun, deno, cloudflare, vercel, netlify }

/// Capabilities declared by one host invocation.
final class RoutedNodeCapabilities {
  const RoutedNodeCapabilities({
    required this.runtime,
    required this.entryModel,
    required this.streaming,
    required this.bufferedResponses,
    required this.webSocket,
    required this.fileSystem,
    required this.backgroundWork,
  });

  final RoutedNodeRuntime runtime;
  final RoutedNodeEntryModel entryModel;
  final bool streaming;
  final bool bufferedResponses;
  final bool webSocket;
  final bool fileSystem;
  final bool backgroundWork;
}

/// Common runtime metadata exposed by a host adapter.
final class RoutedNodeRuntimeInfo {
  const RoutedNodeRuntimeInfo({
    required this.runtime,
    required this.capabilities,
  });

  final RoutedNodeRuntime runtime;
  final RoutedNodeCapabilities capabilities;
}

/// A typed lookup for host-owned request context values.
abstract interface class RoutedNodeExtension {
  RoutedNodeRuntime get runtime;
}

/// Host-native Node request, response, and server handles.
final class NodeRuntimeExtension implements RoutedNodeExtension {
  const NodeRuntimeExtension({this.request, this.response, this.server});

  final Object? request;
  final Object? response;
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.node;
}

/// Host-native Vercel Node.js request, response, and server handles.
final class VercelNodeRuntimeExtension implements RoutedNodeExtension {
  const VercelNodeRuntimeExtension({this.request, this.response, this.server});

  final Object? request;
  final Object? response;
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.vercel;
}

/// Host-native Bun request and server handles.
final class BunRuntimeExtension implements RoutedNodeExtension {
  const BunRuntimeExtension({this.request, this.server});

  final Object? request;
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.bun;
}

/// Host-native Deno request and server handles.
final class DenoRuntimeExtension implements RoutedNodeExtension {
  const DenoRuntimeExtension({this.request, this.server});

  final Object? request;
  final Object? server;

  @override
  RoutedNodeRuntime get runtime => RoutedNodeRuntime.deno;
}

/// Host-native Fetch request and execution context handles.
final class FetchRuntimeExtension implements RoutedNodeExtension {
  const FetchRuntimeExtension({
    required this.runtime,
    this.request,
    this.executionContext,
    this.environment,
  });

  @override
  final RoutedNodeRuntime runtime;
  final Object? request;
  final Object? executionContext;
  final Object? environment;
}

/// Runtime-scoped host context carried through a Routed request.
final class RoutedNodeContext {
  const RoutedNodeContext({required this.info, this.extension});

  final RoutedNodeRuntimeInfo info;
  final RoutedNodeExtension? extension;

  T? extensionAs<T extends RoutedNodeExtension>() {
    final value = extension;
    return value is T ? value : null;
  }
}

const RoutedNodeCapabilities nodeCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.node,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

const RoutedNodeCapabilities bunCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.bun,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

const RoutedNodeCapabilities denoCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.deno,
  entryModel: RoutedNodeEntryModel.listener,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: true,
  backgroundWork: true,
);

const RoutedNodeCapabilities cloudflareCapabilities = RoutedNodeCapabilities(
  runtime: RoutedNodeRuntime.cloudflare,
  entryModel: RoutedNodeEntryModel.fetchExport,
  streaming: true,
  bufferedResponses: true,
  webSocket: true,
  fileSystem: false,
  backgroundWork: false,
);

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
