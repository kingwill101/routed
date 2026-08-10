import 'package:test/test.dart';
import 'package:routed_config/routed_config.dart';
import 'package:routed_core/src/contracts/config/config.dart';

void main() {
  group('RoutedConfig', () {
    test('re-exports config helpers', () {
      expect(Config, isNotNull);
    });

    test('config facade is importable', () {
      expect(() => Config, returnsNormally);
    });
  });
}
