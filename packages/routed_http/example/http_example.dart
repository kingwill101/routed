import 'package:routed_core/routed_core.dart';

void main() async {
  final engine = Engine()
    ..get('/hello', (ctx) {
      final name = ctx.query('name') ?? 'world';
      return ctx.json({'hello': name});
    });
  await engine.close();
}
