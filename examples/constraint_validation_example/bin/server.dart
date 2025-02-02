import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();
  final router = Router();

  // Route with numeric constraint
  router.get('/items/{id}', (ctx) {
    final id = ctx.param('id');
    ctx.string('Item ID: $id');
  }, constraints: {
    'id': r'^\d+$', // Only digits allowed
  });

  // Route with multiple constraints
  router.get('/users/{userId}/{slug}', (ctx) {
    final userId = ctx.param('userId');
    final slug = ctx.param('slug');
    ctx.string('User ID: $userId, Slug: $slug');
  }, constraints: {
    'userId': r'^\d+$', // Only digits
    'slug': r'^[a-z0-9-]+$', // Lowercase letters, numbers, and hyphens
  });

  // Route with custom pattern constraint
  router.get('/products/{sku}', (ctx) {
    final sku = ctx.param('sku');
    ctx.string('Product SKU: $sku');
  }, constraints: {
    'sku':
        r'^[A-Z]{2}\d{4}$', // Format: 2 uppercase letters followed by 4 digits
  });

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
