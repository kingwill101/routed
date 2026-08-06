import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();
  engine.get('/hello', (ctx) {
    final name = ctx.query('name') ?? 'world';
    return ctx.json({'hello': name});
  });
  print('routed_http example: GET /hello?name=routed');
  await engine.close();
}
