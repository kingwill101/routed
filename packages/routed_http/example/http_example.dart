import 'package:routed_core/routed_core.dart';

void main() async {
  final engine = Engine();
  engine.get('/hello', (ctx) {
    final name = ctx.query('name') ?? 'world';
    return ctx.json({'hello': name});
  });
  print('routed_http example: GET /hello?name=routed');
  await engine.close();
}
