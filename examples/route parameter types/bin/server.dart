import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  // Integer parameter
  engine.get('/items/{id:int}', (ctx) {
    final id = ctx.param('id');
    return ctx.json({
      'type': 'integer',
      'value': id,
      'dart_type': id.runtimeType.toString()
    });
  });

  // Double parameter
  engine.get('/prices/{amount:double}', (ctx) {
    final amount = ctx.param('amount');
    return ctx.json({
      'type': 'double',
      'value': amount,
      'dart_type': amount.runtimeType.toString()
    });
  });

  // UUID parameter
  engine.get('/users/{uuid:uuid}', (ctx) {
    final uuid = ctx.param('uuid');
    return ctx.json({
      'type': 'uuid',
      'value': uuid,
      'format': 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
    });
  });

  // Slug parameter
  engine.get('/posts/{slug:slug}', (ctx) {
    final slug = ctx.param('slug');
    return ctx.json({
      'type': 'slug',
      'value': slug,
      'format': 'lowercase-words-with-hyphens'
    });
  });

  // Email parameter
  engine.get('/mail/{email:email}', (ctx) {
    final email = ctx.param('email');
    return ctx.json({'type': 'email', 'value': email, 'valid': true});
  });

  // URL parameter
  engine.get('/links/{url:url}', (ctx) {
    final url = ctx.param('url');
    return ctx
        .json({'type': 'url', 'value': url, 'protocol': Uri.parse(url).scheme});
  });

  // IP address parameter
  engine.get('/address/{ip:ip}', (ctx) {
    final ip = ctx.param('ip');
    return ctx.json({'type': 'ip', 'value': ip, 'format': 'IPv4'});
  });

  // Multiple parameters with different types
  engine.get('/orders/{id:int}/items/{sku:string}/price/{amount:double}',
      (ctx) {
    return ctx.json({
      'order_id': ctx.param('id'),
      'sku': ctx.param('sku'),
      'price': ctx.param('amount')
    });
  });

  // Custom type pattern example
  registerCustomType('phone', r'\d{3}-\d{3}-\d{4}');
  engine.get('/contact/{phone:phone}', (ctx) {
    final phone = ctx.param('phone');
    return ctx
        .json({'type': 'phone', 'value': phone, 'format': 'XXX-XXX-XXXX'});
  });

  // Global parameter pattern example
  registerParamPattern('code', r'[A-Z]{2}\d{4}');
  engine.get('/products/{code}', (ctx) {
    final code = ctx.param('code');
    return ctx
        .json({'type': 'product_code', 'value': code, 'format': 'AA9999'});
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
  print('\nTry these URLs:');
  print('- http://localhost:3000/items/123');
  print('- http://localhost:3000/prices/99.99');
  print('- http://localhost:3000/users/123e4567-e89b-12d3-a456-426614174000');
  print('- http://localhost:3000/posts/my-blog-post');
  print('- http://localhost:3000/mail/user@example.com');
  print('- http://localhost:3000/links/https://example.com');
  print('- http://localhost:3000/address/192.168.1.1');
  print('- http://localhost:3000/orders/123/items/SKU123/price/49.99');
  print('- http://localhost:3000/contact/123-456-7890');
  print('- http://localhost:3000/products/AB1234');
}
