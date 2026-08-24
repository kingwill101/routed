import 'package:liquify/liquify.dart' as liquify;
import 'package:routed_views/routed_views.dart';
import 'package:test/test.dart';

void main() {
  test('liquid extensions apply to renders', () async {
    final engine = LiquidViewEngine();
    ViewExtensionRegistry.instance.registerFor('liquid', (Object target) {
      (target as liquify.Environment).registerLocalFilter('test_upper', (
        Object? value,
        List<Object?> args,
        Map<String, Object?> named,
      ) {
        return value.toString().toUpperCase();
      });
    });

    final result = await engine.render('Value: {{ name | test_upper }}', {
      'name': 'hello',
    });

    expect(result.trim(), equals('Value: HELLO'));
  });
}
