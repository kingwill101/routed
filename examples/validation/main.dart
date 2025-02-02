import 'package:routed/routed.dart';

void main() {
  final engine = Engine();
  final router = Router();

  router.post('/validate', (ctx) async {
    await ctx.validate({
      'name': 'required',
      'age': 'required|numeric',
    });
    ctx.string('Validation passed!');
  });

  engine.use(router);
  engine.serve(port: 8080);
}
