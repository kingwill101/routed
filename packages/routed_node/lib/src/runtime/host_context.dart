import 'package:routed_core/routed_core.dart';

import 'runtime.dart';

/// Attaches host context to a portable request adapter.
final class RoutedNodeRequestAdapter
    implements RequestAdapter, HostContextCarrier {
  RoutedNodeRequestAdapter(this.delegate, this.hostContext);

  final RequestAdapter delegate;
  @override
  final RoutedNodeContext hostContext;

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
