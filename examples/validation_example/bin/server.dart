import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  // JSON validation example
  engine.post('/json', (ctx) async {
    final data = <String, dynamic>{};

    await ctx.validate({
      'name': 'required',
      'age': 'required|numeric',
      'tags': 'required|array'
    });

    await ctx.bind(data);
    ctx.json(data);
  });

  // Form validation example
  engine.post('/form', (ctx) async {
    final data = <String, dynamic>{};

    await ctx.validate({
      'name': 'required',
      'age': 'required|numeric',
    });

    await ctx.bind(data);
    ctx.json(data);
  });

  // Query validation example
  engine.get('/search', (ctx) async {
    final data = <String, dynamic>{};

    await ctx.validate({
      'q': 'required',
      'page': 'required|numeric',
      'sort': 'required',
    });

    await ctx.bind(data);
    ctx.json(data);
  });

  // Validation error handling example
  engine.post('/validate', (ctx) async {
    final data = <String, dynamic>{};

    try {
      await ctx.validate({
        'name': 'required',
        'age': 'required|numeric',
        'email': 'required|email',
        'tags': 'required|array'
      });

      await ctx.bind(data);
      ctx.json(data);
    } on ValidationError catch (e) {
      ctx.status(422);
      ctx.json({'errors': e.errors});
    }
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
