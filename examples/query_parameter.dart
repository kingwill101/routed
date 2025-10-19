import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  // Simple query parameters
  engine.get('/search', (ctx) {
    final query = ctx.query('q');
    final page = ctx.defaultQuery('page', '1');
    final sort = ctx.query('sort');

    ctx.json({'query': query, 'page': page, 'sort': sort});
  });

  // Array query parameters
  engine.get('/filter', (ctx) {
    final tags = ctx.queryArray('tag');
    final categories = ctx.queryArray('category');

    ctx.json({'tags': tags, 'categories': categories});
  });

  // Query parameter with validation
  engine.get('/products', (ctx) async {
    await ctx.validate({
      'minPrice': 'numeric',
      'maxPrice': 'numeric',
      'category': 'required',
    });

    final minPrice = ctx.query('minPrice');
    final maxPrice = ctx.query('maxPrice');
    final category = ctx.query('category');

    ctx.json({
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'category': category,
    });
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
