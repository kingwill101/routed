import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();
  final router = Router(groupName: 'api');

  // API version 1 group
  router
      .group(
        path: '/v1',
        middlewares: [
          (ctx) async {
            ctx.setHeader('API-Version', 'v1');
            await ctx.next();
          },
        ],
        builder: (v1) {
          // Users group
          v1
              .group(
                path: '/users',
                builder: (users) {
                  users
                      .get('/', (ctx) => ctx.json({'message': 'List users'}))
                      .name('list');
                  users.get('/{id:int}', (ctx) {
                    final id = ctx.param('id');
                    ctx.json({'message': 'Get user', 'id': id});
                  }).name('get');
                },
              )
              .name('users');

          // Posts group
          v1
              .group(
                path: '/posts',
                builder: (posts) {
                  posts
                      .get('/', (ctx) => ctx.json({'message': 'List posts'}))
                      .name('list');
                  posts.get('/{id:int}', (ctx) {
                    final id = ctx.param('id');
                    ctx.json({'message': 'Get post', 'id': id});
                  }).name('get');
                },
              )
              .name('posts');
        },
      )
      .name('v1');

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
