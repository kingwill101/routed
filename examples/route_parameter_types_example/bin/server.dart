import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();
  final router = Router();

  // Integer parameter
  router.get('/users/{id:int}', (ctx) {
    final id = ctx.param('id');
    ctx.json({
      'message': 'Got user by ID',
      'id': id,
      'type': id.runtimeType.toString()
    });
  });

  // Double parameter
  router.get('/products/{price:double}', (ctx) {
    final price = ctx.param('price');
    ctx.json({
      'message': 'Got product by price',
      'price': price,
      'type': price.runtimeType.toString()
    });
  });

  // Slug parameter
  router.get('/posts/{slug:slug}', (ctx) {
    final slug = ctx.param('slug');
    ctx.json({'message': 'Got post by slug', 'slug': slug});
  });

  // UUID parameter
  router.get('/resources/{id:uuid}', (ctx) {
    final id = ctx.param('id');
    ctx.json({'message': 'Got resource by UUID', 'id': id});
  });

  // Email parameter
  router.get('/users/by-email/{email:email}', (ctx) {
    final email = ctx.param('email');
    ctx.json({'message': 'Got user by email', 'email': email});
  });

  // IP parameter
  router.get('/clients/{ip:ip}', (ctx) {
    final ip = ctx.param('ip');
    ctx.json({'message': 'Got client by IP', 'ip': ip});
  });

  // Optional parameter
  router.get('/articles/{category}/{subcategory?}', (ctx) {
    final category = ctx.param('category');
    final subcategory = ctx.param('subcategory');
    ctx.json({
      'message': 'Got articles',
      'category': category,
      'subcategory': subcategory
    });
  });

  // Wildcard parameter
  router.get('/files/{*path}', (ctx) {
    final path = ctx.param('path');
    ctx.json({'message': 'Got file path', 'path': path});
  });

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
