import 'package:file/memory.dart';
import 'package:liquify/liquify.dart' as liquid;
import 'package:path/path.dart' as path;
import 'package:routed/src/render/html/liquid.dart';
import 'package:routed/src/view/engines/liquid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('LiquidViewEngine', () {
    test('exposes supported extensions', () {
      final engine = LiquidViewEngine();

      expect(engine.extensions, equals(['.liquid', '.html']));
    });

    test('renders inline template content', () async {
      final engine = LiquidViewEngine();

      final result = await engine.render('Hello {{ name }}', {
        'name': 'Routed',
      });

      expect(result.trim(), equals('Hello Routed'));
    });

    test('wraps render errors as TemplateRenderException', () async {
      const filterName = 'throw_render_error';
      liquid.FilterRegistry.register(filterName, (
        dynamic value,
        List<dynamic> args,
        Map<String, dynamic> namedArgs,
      ) {
        throw StateError('boom');
      });

      final engine = LiquidViewEngine();

      expect(
        () => engine.render('{{ name | $filterName }}', {'name': 'Routed'}),
        throwsA(isA<TemplateRenderException>()),
      );
    });

    test('renders templates from files', () async {
      final fileSystem = MemoryFileSystem();
      final directory = fileSystem.directory('/templates')..createSync();
      final templateFile = fileSystem.file('/templates/greeting.liquid')
        ..writeAsStringSync('Hi {{ who }}!');

      final engine = LiquidViewEngine(
        directory: directory.path,
        root: LiquidRoot(fileSystem: fileSystem),
      );

      final result = await engine.renderFile(path.basename(templateFile.path), {
        'who': 'Quinn',
      });

      expect(result.trim(), equals('Hi Quinn!'));
    });

    test('throws TemplateRenderException for missing templates', () async {
      final fileSystem = MemoryFileSystem();
      final directory = fileSystem.directory('/views')..createSync();
      final engine = LiquidViewEngine(
        directory: directory.path,
        root: LiquidRoot(fileSystem: fileSystem),
      );

      expect(
        () => engine.renderFile('missing.liquid'),
        throwsA(isA<TemplateRenderException>()),
      );
    });

    test('formats TemplateRenderException messages', () {
      final exception = TemplateRenderException('greeting.liquid', 'oops');

      expect(
        exception.toString(),
        equals('Error rendering template greeting.liquid: oops'),
      );
    });

    test('sets directory for file system roots', () async {
      final fileSystem = MemoryFileSystem();
      fileSystem.directory('/templates').createSync();
      fileSystem.directory('/custom').createSync();
      final root = liquid.FileSystemRoot('/templates', fileSystem: fileSystem);

      LiquidViewEngine(directory: '/custom', root: root);

      expect(
        root.fileSystem.currentDirectory.path,
        equals(fileSystem.path.normalize('/custom')),
      );
    });
  });
}
