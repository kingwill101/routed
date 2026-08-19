import 'package:routed_core/src/engine/engine.dart';
import 'package:routed_core/src/router/types.dart';

/// A startup hook for imperative engine wiring that is not configuration.
///
/// Provider configuration belongs in the provider's typed constructor. Engine
/// options are intentionally limited to wiring concerns such as middleware
/// and host service instances.
typedef EngineOpt = void Function(Engine engine);

/// Adds global middleware to the engine.
EngineOpt withMiddleware(List<Middleware> middleware) {
  return (Engine engine) => engine.middlewares.addAll(middleware);
}

/// Registers an application-owned service instance in the engine container.
///
/// Prefer a typed service provider for reusable integrations. This helper is
/// useful for small applications and test hosts that already own the object
/// lifetime.
EngineOpt withService<T extends Object>(T service) {
  return (Engine engine) => engine.container.instance<T>(service);
}
