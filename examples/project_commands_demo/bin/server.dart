import 'package:project_commands_demo/app.dart' as app;
import 'package:routed/routed.dart';

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  await engine.serve(host: '127.0.0.1', port: 8080);
}
