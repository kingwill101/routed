import 'package:routed_core/routed_core.dart';

Never defineVercelNodeHandlerRuntime(Engine engine) {
  throw UnsupportedError(
    'Vercel Node.js handlers require compilation for JavaScript.',
  );
}

Never defineVercelNodeHandlerFactoryRuntime(Future<Engine> Function() factory) {
  throw UnsupportedError(
    'Vercel Node.js handlers require compilation for JavaScript.',
  );
}
