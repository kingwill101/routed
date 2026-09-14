import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/handlers/api.dart' as api;
import 'package:kitchen_sink_example/handlers/web.dart' as web;
import 'package:kitchen_sink_example/middleware/middleware.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';

import 'migrations.dart';

Future<Engine> buildApp({
  String? viewsPath,
  String databasePath = 'storage/kitchen_sink.sqlite',
  String cachePath = 'storage/kitchen_sink-cache',
  bool initialize = true,
}) async {
  final resolvedViewsPath = viewsPath ?? templateDirectory;
  if (databasePath != ':memory:') {
    File(databasePath).absolute.parent.createSync(recursive: true);
  }
  final database = await SqliteDatabase.connect(path: databasePath);
  final databases = DatabaseManager()..register('default', database);
  final recipeProvider = RoutedDatabaseProvider(
    manager: databases,
    migrations: appMigrations,
    migrateOnBoot: true,
  );
  final appKey = 'base64:AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
  final cacheStore = FileStoreFactory().create(
    FileStoreConfiguration(path: cachePath),
  );
  final cacheManager = CacheManager()..registerStore('file', cacheStore);
  final sessionStore = CookieStore(
    codecs: [SecureCookie(useEncryption: true, useSigning: true, key: appKey)],
  );
  // Use an explicit typed provider composition so every feature has its
  // required application configuration before boot.
  final engine = Engine(
    config: EngineConfig(
      appKey: appKey,
      multipart: MultipartConfig(
        maxFileSize: 1024 * 1024,
        allowedExtensions: {'jpg', 'png'},
      ),
      templateDirectory: resolvedViewsPath,
      views: ViewConfig(viewPath: resolvedViewsPath),
    ),
    providers: [
      recipeProvider,
      ...Engine.defaultProviders,
      RoutedCacheProvider(CacheConfig(store: cacheStore)),
      RoutedSessionsProvider(
        SessionConfig(store: sessionStore, cookieName: 'kitchen_sink_session'),
      ),
      ViewServiceProvider(RoutedViewConfig(directory: resolvedViewsPath)),
    ],
    options: [withCacheManager(cacheManager)],
    middlewares: [
      sessionMiddleware(sessionStore),
      (EngineContext ctx, Next next) async {
        print('Request: ${ctx.method} ${ctx.uri.path}');
        return await next();
      },
    ],
  );

  engine.container.get<ViewEngineManager>().register(
    LiquidViewEngine(directory: resolvedViewsPath),
  );

  // API Routes
  final apiRouter = Router(
    path: '/api',
    middlewares: [validateApiKey],
    groupName: 'api',
  );
  apiRouter.get('/recipes', api.listRecipes).name("recipe.list");
  apiRouter.post('/recipes', api.createRecipe).name("recipe.create");
  apiRouter.get('/recipes/{id}', api.getRecipe).name("recipe.show");
  apiRouter.put('/recipes/{id}', api.updateRecipe).name("recipe.update");
  apiRouter.delete('/recipes/{id}', api.deleteRecipe).name("recipe.delete");
  apiRouter
      .post('/recipes/{id}/image', api.uploadImage)
      .name("recipe.image.upload");

  // Web Routes
  final webRouter = Router(groupName: "web");
  webRouter.get('/', web.homePage).name("recipe.home");
  webRouter.post('/recipes', web.saveRecipe).name("recipe.save");
  webRouter
      .get('/recipes/{id}/edit', web.editRecipe, middlewares: [validateSession])
      .name("recipe.edit");
  webRouter
      .get('/recipes/{id}', web.showRecipe, middlewares: [validateSession])
      .name("recipe.show");
  webRouter
      .post(
        '/recipes/{id}/delete',
        web.deleteRecipe,
        middlewares: [validateSession],
      )
      .name("recipe.delete");
  webRouter.static('/public', 'public');
  webRouter.fallback((c) => c.string('fallback'));
  // Session test routes
  engine.get('/set', (ctx) async {
    ctx.setSession('set_worked', 'it worked!');
    return ctx.string('ok');
  });

  engine.get('/test', (ctx) async {
    return ctx.string(ctx.sessionData['set_worked'].toString());
  });

  // Add routers to engine
  engine.use(apiRouter);
  engine.use(webRouter);

  if (initialize) {
    await engine.initialize();
    await RecipeService.configure(database);
  }
  return engine;
}

/// Entrypoint consumed by `routed deploy` for host adapters.
Future<Engine> createEngine({
  bool initialize = true,
  String databasePath = 'storage/kitchen_sink.sqlite',
  String cachePath = 'storage/kitchen_sink-cache',
}) async {
  return buildApp(
    databasePath: databasePath,
    cachePath: cachePath,
    initialize: initialize,
  );
}
