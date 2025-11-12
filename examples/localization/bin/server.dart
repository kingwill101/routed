import 'package:routed/routed.dart';
import 'package:localization_example/app.dart' as app;

Future<void> main(List<String> args) async {
  final Engine engine = await app.createEngine();
  await engine.serve(host: '127.0.0.1', port: 8080);
}
