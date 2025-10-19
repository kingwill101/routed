import 'package:jaspr/jaspr.dart';
import 'package:routed/routed.dart';
import 'package:routed/session.dart' show Session;

/// Provides the active [EngineContext] to Jaspr components rendered via Routed.
class InheritedEngineContext extends InheritedComponent {
  const InheritedEngineContext({
    required this.context,
    required super.child,
    super.key,
  });

  final EngineContext context;

  /// Retrieves the [InheritedEngineContext] component from the tree.
  static InheritedEngineContext of(BuildContext context) {
    final result = context
        .dependOnInheritedComponentOfExactType<InheritedEngineContext>();
    assert(result != null, 'No InheritedEngineContext found in Jaspr tree.');
    return result!;
  }

  /// Accesses the current [EngineContext] inside a Jaspr build method.
  static EngineContext engineOf(BuildContext context) {
    return of(context).context;
  }

  @override
  bool updateShouldNotify(InheritedEngineContext oldComponent) {
    return oldComponent.context != context;
  }
}

/// Convenience extensions for reaching Routed request data from Jaspr widgets.
extension BuildContextEngineContextX on BuildContext {
  EngineContext get engineContext => InheritedEngineContext.engineOf(this);

  Request get routedRequest => engineContext.request;

  Response get routedResponse => engineContext.response;

  Session get routedSession => engineContext.session;
}
