import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:liquify/src/filter_registry.dart' as liquify;
import 'package:routed/routed.dart';
import 'package:routed/src/translation/locale_manager.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  late FileSystem fs;
  late Engine engine;
  late TestClient client;
  late String rootDir;

  setUp(() async {
    fs = MemoryFileSystem();
    rootDir = '/app';
    fs.directory(rootDir).createSync(recursive: true);

    _writeTranslation(fs, rootDir, 'en', '''
greeting: "Hello :name"
notifications:
  count: "No notifications|{1} One notification|[2,*] :count notifications"
''');
    _writeTranslation(fs, rootDir, 'fr', '''
greeting: "Bonjour :name"
notifications:
  count: "Aucune notification|{1} Une notification|[2,*] :count notifications"
''');

    _writeTemplate(fs, rootDir, '''
<p>{{ 'messages.greeting' | trans: name: user.name }}</p>
<p>{{ "messages.notifications.count" | trans_choice: user.count }}</p>
''');

    engine = testEngine(
      config: EngineConfig(fileSystem: fs),
      fileSystem: fs,
      configItems: {
        'translation': {
          'paths': [fs.path.join(rootDir, 'resources', 'lang')],
          'resolvers': ['query', 'header'],
          'query': {'parameter': 'lang'},
        },
        'view': {'directory': fs.path.join(rootDir, 'views')},
      },
    );

    engine.get('/welcome', (ctx) async {
      return await ctx.template(
        templateName: 'welcome.liquid',
        data: {
          'user': {'name': 'Jess', 'count': 3},
        },
      );
    });

    engine.get('/raw', (ctx) async {
      return ctx.json({
        'message': ctx.trans('messages.greeting', replacements: {'name': 'Jess'}),
      });
    });

    engine.get('/current', (ctx) async {
      return ctx.json({
        'locale': ctx.currentLocale(),
        'param': ctx.request.queryParameters['lang'],
      });
    });

    client = TestClient(RoutedRequestHandler(engine));
  });

  tearDown(() async {
    await client.close();
    await engine.close();
  });

  test('translation config', () async {
    expect(
      engine.appConfig.getStringListOrNull('translation.resolvers'),
      equals(['query', 'header']),
    );

    final loader = engine.container.get<TranslationLoader>();
    final map = loader.load('en', 'messages');
    expect(map['greeting'], equals('Hello :name'));

    final localeManager = engine.container.get<LocaleManager>();
    final manualContext = LocaleResolutionContext(
      header: (_) => null,
      query: (name) => name == 'lang' ? 'fr' : null,
      cookie: (_) => null,
      sessionValue: null,
    );
    expect(localeManager.resolve(manualContext), equals('fr'));

    expect(liquify.FilterRegistry.getFilter('trans'), isNotNull);
    expect(liquify.FilterRegistry.getFilter('trans_choice'), isNotNull);
  });

  test('renders translations via trans and trans_choice filters', () async {
    final raw = await client.getJson('/raw');
    expect(raw.json()['message'], equals('Hello Jess'));

    final localeResp = await client.getJson('/current?lang=fr');
    expect(localeResp.json()['param'], equals('fr'));
    expect(localeResp.json()['locale'], equals('fr'));

    final english = await client.get('/welcome');
    expect(english.body, contains('Hello Jess'));
    expect(english.body, contains('3 notifications'));

    final french = await client.get('/welcome?lang=fr');
    expect(french.body, contains('Bonjour Jess'));
    expect(french.body, contains('3 notifications'));
  });
}

void _writeTranslation(FileSystem fs, String root, String locale, String yaml) {
  final file = fs.file(
    fs.path.join(root, 'resources', 'lang', locale, 'messages.yaml'),
  );
  file
    ..createSync(recursive: true)
    ..writeAsStringSync(yaml.trim());
}

void _writeTemplate(FileSystem fs, String root, String content) {
  final file = fs.file(fs.path.join(root, 'views', 'welcome.liquid'));
  file
    ..createSync(recursive: true)
    ..writeAsStringSync(content.trim());
}
