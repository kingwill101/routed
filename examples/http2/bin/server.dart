import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = Engine(
    config: EngineConfig(
      http2: const Http2Config(enabled: true),
      tlsCertificatePath: 'cert.pem',
      tlsKeyPath: 'key.pem',
    ),
  )..get('/', (ctx) => ctx.string('Hello World'));

  await engine.serveSecure(port: 4043);
}
