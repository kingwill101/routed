import 'package:config_demo/drivers/cache/in_memory_cache_driver.dart';
import 'package:config_demo/drivers/storage/memory_storage_driver.dart';
import 'package:config_demo/providers/mail_provider.dart';
import 'package:routed/routed.dart';
import 'package:routed_core/providers.dart' show ProviderRegistry;

Future<Engine> createEngine() async {
  ProviderRegistry.instance.register(
    'config_demo.mail',
    factory: () => MailProvider(),
    description: 'Mail service provider for the config demo',
  );

  final engine = await Engine.create(
    providers: [
      CoreServiceProvider.withLoader(
        ConfigLoaderOptions(
          configDirectory: 'config',
          envFiles: ['.env', '.env.local'],
          watch: true,
          defaults: {'features.beta_banner': true},
        ),
      ),
      RoutingServiceProvider(),
    ],
  );

  // Register demo drivers on the engine's managers (config-driven via
  // `routed.storage` / `routed.cache` providers from the manifest).
  final storageManager = engine.container.get<StorageManager>();
  final cacheManager = engine.container.get<CacheManager>();
  registerMemoryStorageDriver(storageManager);
  registerTransientStorageDriver(storageManager);
  registerInMemoryCacheDriver(cacheManager);

  engine.get('/', (ctx) async {
    final config = Config.current;
    final mail = await ctx.container.make<MailService>();
    final storageManager = await ctx.container.make<StorageManager>();
    final cacheManager = await ctx.container.make<CacheManager>();

    final staticMounts = (config.get('static.mounts') as List?)
        ?.whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    final mailCredentials = (config.get('mail.credentials') as Map?)?.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final sessionConfig = (config.get('session.config') as Map?)?.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final appKey = sessionConfig?['app_key'] as String? ?? '';
    final appKeyPreview = appKey.length > 8
        ? '${appKey.substring(0, 8)}\u2026'
        : appKey;

    final cacheStores = <String, dynamic>{};
    final rawCacheStores = config.get('cache.stores');
    if (rawCacheStores is Map) {
      rawCacheStores.forEach((key, value) {
        if (value is Map) {
          cacheStores[key.toString()] = value.map(
            (k, v) => MapEntry(k.toString(), v),
          );
        } else {
          cacheStores[key.toString()] = value;
        }
      });
    }

    final storageDriverNames = storageManager.diskNames.toList()..sort();
    final cacheStoreFactories = cacheManager.storeFactoryDrivers.toList()
      ..sort();

    return ctx.json({
      'app': {
        'name': config.get('app.name'),
        'env': config.get('app.env'),
        'debug': config.get('app.debug'),
        'greeting': config.get('app.greeting'),
      },
      'mail': {
        'host': mail.host,
        'port': mail.port,
        'from': config.get('mail.from'),
        'credentials': mailCredentials,
      },
      'session': {
        'cookie_name': sessionConfig?['cookie_name'],
        'secure': sessionConfig?['secure'],
        'http_only': sessionConfig?['http_only'],
        'app_key_preview': appKeyPreview,
      },
      'cache': {
        'default': config.get('cache.default'),
        'drivers': cacheStoreFactories,
        'manager_default_store': cacheManager.getDefaultDriver(),
        'stores': cacheStores,
      },
      'logging': {
        'extra_fields': config.get('logging.extra_fields'),
        'request_headers': config.get('logging.request_headers'),
      },
      'static': {'mounts': staticMounts},
      'storage': {
        'default': config.get('storage.default'),
        'assets_root': config.get('storage.disks.assets.root'),
        'transient_root': storageManager.resolve('', disk: 'transient'),
        'drivers': storageDriverNames,
      },
      'uploads': {
        'allowed_extensions': config.get('uploads.allowed_extensions'),
        'max_file_size': config.get('uploads.max_file_size'),
      },
      'security': {
        'headers': config.get('security.headers'),
        'referrer_policy': config.get('security.headers.Referrer-Policy'),
      },
      'features': {'beta_banner': config.get('features.beta_banner', false)},
    });
  });

  engine.get('/override', (ctx) async {
    final snapshot = Map<String, dynamic>.from(Config.current.all());
    snapshot['app'] = {
      ...?snapshot['app'] as Map<String, dynamic>?,
      'name': 'Scoped Override',
    };

    await Config.runWith(ConfigImpl(snapshot), () async {
      ctx.write('Scoped app.name -> ${Config.current.get('app.name')}');
    });

    return ctx.string('');
  });

  return engine;
}
