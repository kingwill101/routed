import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed_core/routed_core.dart' hide LiquidViewEngine, ViewEngine;
import 'package:routed_hotwire/routed_hotwire.dart';
import 'package:routed_storage/routed_storage.dart';
import 'package:routed_views/routed_views.dart';

import 'controllers/todo_controller.dart';
import 'repositories/todo_repository.dart';

Future<Engine> createTodoApp({
  Directory? root,
  TodoRepository? repository,
  TurboStreamHub? hub,
}) async {
  final baseDir = root ?? Directory(p.dirname(Platform.script.toFilePath()));
  final templatesPath = p.join(baseDir.path, 'templates');
  final assetsPath = p.join(baseDir.path, 'public');

  final engine = await Engine.create(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [...Engine.defaultProviders, ViewServiceProvider()],
  );

  engine.container
      .get<ViewEngineManager>()
      .register(LiquidViewEngine(directory: templatesPath));

  final assetsRouter = Router()..static('/assets', assetsPath);
  engine.use(assetsRouter);

  final todoHub = hub ?? TurboStreamHub();
  final todoRepository = repository ?? TodoRepository.seed();
  final controller = TodoController(repository: todoRepository, hub: todoHub);

  engine.ws('/ws/todos', TurboStreamSocketHandler(hub: todoHub));

  engine
    ..get('/', controller.home)
    ..get('/todos', controller.list)
    ..get('/todos/new', controller.form)
    ..get('/todos/{id}', controller.detail)
    ..post('/todos', controller.create)
    ..post('/todos/{id}/toggle', controller.toggle)
    ..post('/todos/{id}/delete', controller.delete);

  return engine;
}
