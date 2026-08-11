import 'package:routed_core/routed_core.dart';

void main() async {
  final engine = Engine();
  engine.get('/', (ctx) => ctx.json({'view': 'liquify/mustache via routed_views'}));
  print('routed_views example');
  await engine.close();
}
