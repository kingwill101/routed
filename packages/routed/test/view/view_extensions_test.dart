import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test('liquid extensions apply to renders', () async {
    final engine = LiquidViewEngine();
    ViewExtensionRegistry.instance.registerFor('liquid', (target) {
      final env = target as dynamic;
      env.registerLocalFilter(
        'test_upper',
        (value, args, named) => value.toString().toUpperCase(),
      );
    });

    final result = await engine.render('Value: {{ name | test_upper }}', {
      'name': 'hello',
    });

    expect(result.trim(), equals('Value: HELLO'));
  });
}
