import 'package:file/memory.dart';
import 'package:routed/src/render/html/liquid.dart';
import 'package:routed/src/render/html/template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('LiquidRoot', () {
    test('resolves existing templates', () {
      final fileSystem = MemoryFileSystem();
      final file =
          fileSystem.file(fileSystem.path.join('templates', 'welcome.liquid'))
            ..createSync(recursive: true)
            ..writeAsStringSync('Hello');

      final root = LiquidRoot(fileSystem: fileSystem);
      final source = root.resolve(file.path);

      expect(source.content, equals('Hello'));
    });

    test('throws when template missing', () {
      final root = LiquidRoot(fileSystem: MemoryFileSystem());

      expect(() => root.resolve('missing.liquid'), throwsA(isA<Exception>()));
    });

    test('resolves templates asynchronously', () async {
      final fileSystem = MemoryFileSystem();
      final file =
          fileSystem.file(fileSystem.path.join('templates', 'async.liquid'))
            ..createSync(recursive: true)
            ..writeAsStringSync('Hi');

      final root = LiquidRoot(fileSystem: fileSystem);
      final source = await root.resolveAsync(file.path);

      expect(source.content, equals('Hi'));
    });
  });

  group('LiquidTemplateEngine', () {
    test('renders templates with registered filters', () async {
      final fileSystem = MemoryFileSystem();
      fileSystem.directory('/templates').createSync();
      fileSystem
          .file('/templates/greeting.liquid')
          .writeAsStringSync('Hello {{ name | upper }}');

      final engine = LiquidTemplateEngine(fileSystem: fileSystem);
      engine.addFilter('upper', (dynamic value, List<dynamic> args) {
        return value.toString().toUpperCase();
      });
      engine.addFunc('noop', () {});
      final originalCwd = fileSystem.currentDirectory.path;
      engine.loadTemplates('/templates');

      final result = await engine.render('greeting.liquid', {'name': 'routed'});

      expect(result, equals('Hello ROUTED'));
      expect(engine.filterMap.keys, contains('upper'));
      expect(engine.funcMap, isEmpty);
      expect(fileSystem.currentDirectory.path, equals(originalCwd));
    });

    test('throws when loading missing template directory', () {
      final engine = LiquidTemplateEngine(fileSystem: MemoryFileSystem());

      expect(() => engine.loadTemplates('/missing'), throwsA(isA<Exception>()));
    });

    test('renderContent throws for now', () {
      final engine = LiquidTemplateEngine(fileSystem: MemoryFileSystem());

      expect(
        () => engine.renderContent('Hello'),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('implements TemplateEngine interface', () {
      final engine = LiquidTemplateEngine(fileSystem: MemoryFileSystem());

      expect(engine, isA<TemplateEngine>());
    });
  });
}
