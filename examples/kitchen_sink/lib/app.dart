import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/handlers/api.dart' as api;
import 'package:kitchen_sink_example/handlers/web.dart' as web;
import 'package:kitchen_sink_example/middleware/middleware.dart';
import 'package:routed/routed.dart';

Engine buildApp({String? viewsPath}) {
  final resolvedViewsPath = viewsPath ?? templateDirectory;
  final appKey = 'base64:AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
  env["APP_KEY"] = appKey;
  final cacheManager = CacheManager()
    ..registerStore('array', {'driver': 'array', 'serialize': false})
    ..registerStore('file', {'driver': 'file', 'path': 'cache'});
  final sessionStore = CookieStore(
    codecs: [SecureCookie(useEncryption: true, useSigning: true, key: appKey)],
  );
  // Use an explicit provider composition so every feature has its required
  // application configuration before options are applied.
  final engine = Engine(
    config: EngineConfig(
      appKey: appKey,
      multipart: MultipartConfig(
        maxFileSize: 1024 * 1024,
        allowedExtensions: {'.jpg', '.png'},
      ),
      templateDirectory: resolvedViewsPath,
      views: ViewConfig(viewPath: resolvedViewsPath),
    ),
    providers: [...Engine.defaultProviders, ViewServiceProvider()],
    configItems: {
      'view': {'directory': resolvedViewsPath},
    },
    options: [
      withCacheManager(cacheManager),
      withSessionConfig(
        SessionConfig(store: sessionStore, cookieName: 'kitchen_sink_session'),
      ),
    ],
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

  return engine;
}

/// Entrypoint consumed by `routed deploy` for host adapters.
Future<Engine> createEngine({bool initialize = true}) async {
  final engine = buildApp();
  if (initialize) await engine.initialize();
  return engine;
}
