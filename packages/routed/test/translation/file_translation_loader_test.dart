import 'package:file/memory.dart';
import 'package:routed/src/translation/loaders/file_translation_loader.dart';
import 'package:test/test.dart';

void main() {
  group('FileTranslationLoader', () {
    test('loads YAML files from default path', () {
      final fs = MemoryFileSystem();
      fs.file('resources/lang/en/messages.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('greeting: "Hello"\ninner:\n  value: "Nested"\n');

      final loader = FileTranslationLoader(fileSystem: fs);
      final lines = loader.load('en', 'messages');

      expect(lines['greeting'], equals('Hello'));
      expect(lines['inner'], equals({'value': 'Nested'}));
    });

    test('merges additional search paths', () {
      final fs = MemoryFileSystem();
      fs.file('resources/lang/en/messages.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('app: "base"');
      fs.file('modules/blog/lang/en/messages.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('blog: "enabled"');

      final loader = FileTranslationLoader(fileSystem: fs)
        ..addPath('modules/blog/lang');

      final lines = loader.load('en', 'messages');

      expect(lines['app'], equals('base'));
      expect(lines['blog'], equals('enabled'));
    });

    test('loads JSON dictionaries when group and namespace are wildcards', () {
      final fs = MemoryFileSystem();
      fs.file('resources/lang/en.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"Hi": "Hola", "Bye": "Adiós"}');

      final loader = FileTranslationLoader(fileSystem: fs);
      final jsonLines = loader.load('en', '*', namespace: '*');

      expect(jsonLines['Hi'], equals('Hola'));
      expect(jsonLines['Bye'], equals('Adiós'));
    });

    test('applies vendor overrides for namespaces', () {
      final fs = MemoryFileSystem();
      fs.file('packages/demo/lang/en/messages.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('status: "base"\nsettings:\n  mode: "default"');
      fs.file('resources/lang/vendor/demo/en/messages.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('status: "override"\nsettings:\n  mode: "custom"');

      final loader = FileTranslationLoader(fileSystem: fs)
        ..addNamespace('demo', 'packages/demo/lang');

      final lines = loader.load('en', 'messages', namespace: 'demo');

      expect(lines['status'], equals('override'));
      expect(lines['settings'], equals({'mode': 'custom'}));
    });

    test('throws FormatException for invalid JSON files', () {
      final fs = MemoryFileSystem();
      fs.file('resources/lang/en.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{invalid json');

      final loader = FileTranslationLoader(fileSystem: fs);

      expect(
        () => loader.load('en', '*', namespace: '*'),
        throwsFormatException,
      );
    });
  });
}
