import 'package:routed_core/routed_core.dart';

/// Performs the defineVercelNodeHandlerRuntime operation.
Never defineVercelNodeHandlerRuntime(Engine engine) {
  throw UnsupportedError(
    'Vercel Node.js handlers require compilation for JavaScript.',
  );
}

/// Performs the defineVercelNodeHandlerFactoryRuntime operation.
Never defineVercelNodeHandlerFactoryRuntime(Future<Engine> Function() factory) {
  throw UnsupportedError(
    'Vercel Node.js handlers require compilation for JavaScript.',
  );
}
