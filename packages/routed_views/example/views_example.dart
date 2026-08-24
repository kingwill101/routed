import 'package:routed_core/routed_core.dart';

void main() async {
  final engine = Engine()
    ..get(
      '/',
      (ctx) => ctx.json({'view': 'liquify/mustache via routed_views'}),
    );
  await engine.close();
}
