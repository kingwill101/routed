// ignore_for_file: depend_on_referenced_packages

import 'package:routed/routed.dart';

final Map<String, String> db = {};

void main() {
  final engine = Engine();
  engine.post("/post", (c) async {
    final ids = c.queryMap("ids");
    final names = await c.postFormMap("names");
    c.string("$ids  $names");
  });

  engine.post('/upload', (ctx) async {
    // await ctx.shouldBindWith({}, multipartBinding);

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

  engine.get("/search", (c) {
    final search = c.query("q");
    if (search != null) {
      c.json({'search': search});
    } else {
      c.json({'error': 'No search query provided'});
    }
  });

  engine.serve(port: 8080);
}
