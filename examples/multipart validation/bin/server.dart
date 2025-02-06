import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  engine.post('/upload', (ctx) async {
    // Test form fields
    final name = await ctx.postForm('name');
    final age = await ctx.defaultPostForm('age', '0');
    final hobby = await ctx.postForm('hobby');
    final tags = await ctx.postFormArray('tags');
    final Map<String, dynamic> prefs = {
      "pref_theme": await ctx.postForm('pref_theme'),
      "pref_lang": await ctx.postForm('pref_lang'),
    };

    // Test file upload
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
