import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  engine.post('/upload', (ctx) async {
    final data = <String, dynamic>{};

    await ctx.validate({
      'name': 'required',
      'age': 'required|numeric',
      'tags': 'required|array',
      'document': 'required|file'
    });

    await ctx.bind(data);
    ctx.json(data);
  });

  // Start the server on localhost:8080
  await engine.serve(host: '127.0.0.1', port: 8080);
}
