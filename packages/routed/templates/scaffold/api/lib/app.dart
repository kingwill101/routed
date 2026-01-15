import 'dart:io';

import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create(
    configOptions: const ConfigLoaderOptions(
      configDirectory: 'config',
      loadEnvFiles: false,
      includeEnvironmentSubdirectory: false,
    ),
  );

  final users = <String, Map<String, dynamic>>{
    '1': {'id': '1', 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
    '2': {'id': '2', 'name': 'Alan Turing', 'email': 'alan@example.com'},
  };

  engine.group(path: '/api/v1', builder: (router) {
    router.get('/health', (ctx) async {
      return ctx.json({'status': 'ok'});
    });

    router.get('/users', (ctx) async {
      return ctx.json({'data': users.values.toList()});
    });

    router.get('/users/{id}', (ctx) async {
      final id = ctx.mustGetParam<String>('id');
      final user = await ctx.fetchOr404(
        () async => users[id],
        message: 'User not found',
      );
      return ctx.json(user);
    });

    router.post('/users', (ctx) async {
      final payload =
          Map<String, dynamic>.from(await ctx.bindJSON({}) as Map? ?? const {});
      final id = (users.length + 1).toString();
      final created = {
        'id': id,
        'name': payload['name'] ?? 'user-$id',
        'email': payload['email'] ?? 'user$id@example.com',
      };
      users[id] = created;
      return ctx.json(created, statusCode: HttpStatus.created);
    });
  });

  return engine;
}
