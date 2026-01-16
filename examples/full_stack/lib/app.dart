import 'package:ormed/ormed.dart';
import 'package:routed/routed.dart';

import 'package:full_stack/src/database/datasource.dart';
import 'package:full_stack/src/database/models/todo.dart';

Future<Engine> createEngine() async {
  final dataSource = createDataSource();
  await dataSource.init();
  DataSource.setDefault(dataSource);

  final engine = await Engine.create(
    configOptions: const ConfigLoaderOptions(
      configDirectory: 'config',
      loadEnvFiles: true,
      includeEnvironmentSubdirectory: false,
    ),
  );

  engine.container.instance<DataSource>(dataSource);

  engine.group(
    path: '/api',
    builder: (router) {
      router.get('/todos', (ctx) async {
        final items = await dataSource.query<Todo>().orderBy('id').get();
        return ctx.json({'data': items.map(_serializeTodo).toList()});
      });

      router.post('/todos', (ctx) async {
        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final title = payload['title']?.toString().trim() ?? '';
        if (title.isEmpty) {
          return ctx.json({
            'message': 'Title is required.',
          }, statusCode: HttpStatus.unprocessableEntity);
        }

        final completed = payload['completed'] == true;
        final created = await dataSource.repo<Todo>().insert({
          'title': title,
          'completed': completed,
        });
        return ctx.json(
          _serializeTodo(created),
          statusCode: HttpStatus.created,
        );
      });

      router.patch('/todos/{id}', (ctx) async {
        final idValue = int.tryParse(ctx.mustGetParam<String>('id'));
        if (idValue == null) {
          return ctx.json({
            'message': 'Invalid todo id.',
          }, statusCode: HttpStatus.badRequest);
        }

        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final updates = <String, Object?>{};
        if (payload.containsKey('title')) {
          final title = payload['title']?.toString().trim();
          if (title == null || title.isEmpty) {
            return ctx.json({
              'message': 'Title cannot be empty.',
            }, statusCode: HttpStatus.unprocessableEntity);
          }
          updates['title'] = title;
        }
        if (payload.containsKey('completed')) {
          updates['completed'] = payload['completed'] == true;
        }
        if (updates.isEmpty) {
          return ctx.json({
            'message': 'No updates provided.',
          }, statusCode: HttpStatus.unprocessableEntity);
        }

        final existing = await dataSource
            .query<Todo>()
            .whereEquals('id', idValue)
            .first();
        await ctx.fetchOr404(() async => existing, message: 'Todo not found');

        final updated = await dataSource.repo<Todo>().update(
          updates,
          where: {'id': idValue},
        );
        return ctx.json(_serializeTodo(updated));
      });
    },
  );

  engine.get('/', (ctx) async {
    return await ctx.template(templateName: 'todos.liquid');
  });

  return engine;
}

Map<String, dynamic> _serializeTodo(Todo todo) => {
  'id': todo.id,
  'title': todo.title,
  'completed': todo.completed,
};
