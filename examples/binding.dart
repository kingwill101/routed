import 'package:routed/routed.dart';
import 'package:routed/bindings.dart';

void main(List<String> args) async {
  final engine = Engine();

  // JSON binding example
  engine.post('/json', (ctx) async {
    final data = <String, dynamic>{};
    await ctx.shouldBindWith(data, jsonBinding);
    ctx.json(data);
  });

  // Form URL encoded binding example
  engine.post('/form', (ctx) async {
    final data = <String, dynamic>{};
    await ctx.shouldBindWith(data, formBinding);
    ctx.json(data);
  });

  // Query binding example
  engine.get('/search', (ctx) async {
    final data = <String, dynamic>{};
    await ctx.shouldBindWith(data, queryBinding);
    ctx.json(data);
  });

  // Multipart form binding example
  engine.post('/upload', (ctx) async {
    final name = await ctx.postForm('name');
    final age = await ctx.defaultPostForm('age', '0');
    final hobby = await ctx.postForm('hobby');
    final tags = await ctx.postFormArray('tags');
    final Map<String, dynamic> prefs = {
      "pref_theme": await ctx.postForm('pref_theme'),
      "pref_lang": await ctx.postForm('pref_lang'),
    };
    final file = await ctx.formFile('document');

    ctx.json({
      'name': name,
      'age': age,
      'hobby': hobby,
      'tags': tags,
      'preferences': prefs,
      'hasFile': file != null,
      'fileName': file?.filename,
      'fileSize': file?.size,
    });
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
