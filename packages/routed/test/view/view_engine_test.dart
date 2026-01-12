import 'package:routed/src/view/view_engine.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateNotFoundException', () {
    test('exposes a readable message', () {
      final exception = TemplateNotFoundException('missing.liquid');

      expect(exception.message, equals('Template not found: missing.liquid'));
      expect(
        exception.toString(),
        equals('Template not found: missing.liquid'),
      );
    });
  });
}
