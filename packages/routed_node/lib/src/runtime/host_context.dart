import 'package:routed_core/routed_core.dart';

import 'runtime.dart';

/// Attaches host context to a portable request adapter.
final class RoutedNodeRequestAdapter
    implements RequestAdapter, WebSocketUpgradeRequest, HostContextCarrier {
  /// Performs the RoutedNodeRequestAdapter operation.
  RoutedNodeRequestAdapter(this.delegate, this.hostContext);

  /// The delegate value.
  final RequestAdapter delegate;
  WebSocketUpgradeRequest? get _upgrade => delegate is WebSocketUpgradeRequest
      ? delegate as WebSocketUpgradeRequest
      : null;
  @override
  final RoutedNodeContext hostContext;

  @override
  bool get isWebSocketUpgrade => _upgrade?.isWebSocketUpgrade ?? false;

  @override
  Object? get nativeUpgradeResponse => _upgrade?.nativeUpgradeResponse;

  @override
  Future<RoutedWebSocket> accept() {
    final value = _upgrade;
    if (value != null) {
      return value.accept();
    }
    throw UnsupportedError('WebSocket upgrade is not available.');
  }

  @override
  String get method => delegate.method;

  @override
  Uri get uri => delegate.uri;

  @override
  Map<String, List<String>> get headers => delegate.headers;

  @override
  Stream<List<int>> get body => delegate.body;

  @override
  String? get remoteAddress => delegate.remoteAddress;
}

/// Returns the host context installed by a `routed_node` adapter.
RoutedNodeContext? routedNodeContextOf(EngineContext context) {
  final value = context.hostContext;
  return value is RoutedNodeContext ? value : null;
}

/// Returns the typed host extension installed by a `routed_node` adapter.
T? routedNodeExtensionOf<T extends RoutedNodeExtension>(EngineContext context) {
  return routedNodeContextOf(context)?.extensionAs<T>();
}
