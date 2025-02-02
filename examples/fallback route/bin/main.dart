import 'package:routed/routed.dart';

void main() {
  final engine = Engine.d();

  // Standard route
  engine.get('/hello', (ctx) => ctx.string('Hello World!'));

  // Fallback route to catch unmatched requests
  engine.fallback((ctx) {
    ctx.string('This is the fallback handler');
  });

  engine.serve(port: 8080);
}
