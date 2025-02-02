import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  // Integer parameter
  engine.get('/users/{id:int}', (ctx) {
    final id = ctx.param('id');
    ctx.string('User ID: $id');
  });

  // Double parameter
  engine.get('/price/{amount:double}', (ctx) {
    final amount = ctx.param('amount');
    ctx.string('Price: $amount');
  });

  // Slug parameter
  engine.get('/posts/{slug:slug}', (ctx) {
    final slug = ctx.param('slug');
    ctx.string('Post Slug: $slug');
  });

  // UUID parameter
  engine.get('/resources/{rid:uuid}', (ctx) {
    final rid = ctx.param('rid');
    ctx.string('Resource ID: $rid');
  });

  // Email parameter
  engine.get('/subscribe/{contact:email}', (ctx) {
    final contact = ctx.param('contact');
    ctx.string('Contact Email: $contact');
  });

  // IP parameter
  engine.get('/diagnose/{address:ip}', (ctx) {
    final address = ctx.param('address');
    ctx.string('IP Address: $address');
  });

  // String parameter
  engine.get('/anything/{value:string}', (ctx) {
    final value = ctx.param('value');
    ctx.string('Value: $value');
  });

  // Optional parameter
  engine.get('/users/{id}/posts/{title?}', (ctx) {
    final id = ctx.param('id');
    final title = ctx.param('title') ?? 'no title';
    ctx.string('User $id, Post: $title');
  });

  // Wildcard parameter
  engine.get('/files/{*path}', (ctx) {
    final path = ctx.param('path');
    ctx.string('File Path: $path');
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
