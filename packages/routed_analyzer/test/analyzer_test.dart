import 'package:test/test.dart';
import 'package:routed_analyzer/routed_analyzer.dart';

void main() {
  group('RoutedAnalyzer', () {
    test('plugin class is exported', () {
      expect(RoutedAnalyzerPlugin, isNotNull);
    });

    test('plugin can be instantiated', () {
      expect(() => RoutedAnalyzerPlugin, returnsNormally);
    });
  });
}
