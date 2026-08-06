import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('Localization end-to-end', () {
    late MemoryFileSystem fs;
    late Directory tempDir;
    late TestClient client;

    setUp(() async {
      fs = MemoryFileSystem();
      tempDir = fs.systemTempDirectory.createTempSync(
        'routed_translation_test',
      );
      _writeTranslation(fs, tempDir.path, 'en', 'greeting: "Hello"\n');
      _writeTranslation(fs, tempDir.path, 'fr', 'greeting: "Bonjour"\n');

      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
        configItems: {
          'app': {'locale': 'en', 'fallback_locale': 'en'},
          'translation': {
            'paths': [tempDir.path],
            'resolvers': ['query', 'header'],
            'query': {'parameter': 'lang'},
          },
        },
      );

      engine.get('/greet', (ctx) async {
        final message = ctx.trans('messages.greeting')?.toString() ?? '';
        ctx.response.write(message);
        return ctx.response;
      });

      client = TestClient(RoutedRequestHandler(engine));
    });

    tearDown(() async {
      await client.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('resolves locale via query, header, and fallback', () async {
      final defaultResp = await client.get('/greet');
      expect(defaultResp.body, equals('Hello'));

      final queryResp = await client.get('/greet?lang=fr');
      expect(queryResp.body, equals('Bonjour'));

      final headerResp = await client.get(
        '/greet',
        headers: {
          HttpHeaders.acceptLanguageHeader: ['fr'],
        },
      );
      expect(headerResp.body, equals('Bonjour'));

      final fallbackResp = await client.get('/greet?lang=es');
      expect(fallbackResp.body, equals('Hello'));
    });
  });
}

void _writeTranslation(
  FileSystem fileSystem,
  String root,
  String locale,
  String content,
) {
  final file = fileSystem.file('$root/$locale/messages.yaml');
  file
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}
