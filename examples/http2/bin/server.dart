import 'package:routed/routed.dart';

void main() {
  final engine = Engine();

  engine.get("/", (ctx) {
    ctx.string("Hellow World");
  });

  engine.serveSecure(
    port: 4043,
    certificatePath: 'cert.pem',
    keyPath: 'key.pem',
  );
}
