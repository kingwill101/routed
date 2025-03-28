import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/handlers/api.dart' as api;
import 'package:kitchen_sink_example/handlers/web.dart' as web;
import 'package:kitchen_sink_example/middleware/middleware.dart';
import 'package:routed/routed.dart';
import 'package:routed/session.dart';

Engine buildApp() {
  final appKey = 'base64:AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
  env["APP_KEY"] = appKey;
  final engine = Engine(
      config: EngineConfig(
        appKey: appKey,
        multipart: MultipartConfig(
            maxFileSize: 1024 * 1024, allowedExtensions: {'.jpg', '.png'}),
        templateDirectory: templateDirectory,
      ),
      options: [
        withCacheManager(CacheManager()
          ..registerStore(
            'file',
            {
              'driver': 'file',
              'path': 'cache',
            },
          )),
        withSessionConfig(SessionConfig(
          store: CookieStore(
            codecs: [
              SecureCookie(
                useEncryption: true,
                useSigning: true,
                key: appKey,
              ),
            ],
          ),
          cookieName: 'kitchen_sink_session',
        )),
      ],
      middlewares: [
        (ctx) async {
          print('Request: ${ctx.method} ${ctx.uri.path}');
          await ctx.next();
        }
      ]);

  engine.useLiquid(
      directory: templateDirectory, fileSystem: templateFileSystem);

  // API Routes
  final apiRouter =
      Router(path: '/api', middlewares: [validateApiKey], groupName: 'api');
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
  webRouter.get('/recipes/{id}/edit', web.editRecipe,
      middlewares: [validateSession]).name("recipe.edit");
  webRouter.get('/recipes/{id}', web.showRecipe,
      middlewares: [validateSession]).name("recipe.show");
  webRouter.delete('/recipes/{id}', web.deleteRecipe,
      middlewares: [validateSession]).name("recipe.delete");
  webRouter.static('/public', 'public');
  webRouter.fallback((c) {
    print('fallback');
  });
  // Session test routes
  engine.get('/set', (ctx) async {
    ctx.setSession('set_worked', 'it worked!');
  });

  engine.get('/test', (ctx) async {
    return ctx.string(ctx.sessionData['set_worked'].toString());
  });

  // Add routers to engine
  engine.use(apiRouter);
  engine.use(webRouter);

  return engine;
}
