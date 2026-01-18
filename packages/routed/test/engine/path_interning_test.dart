import 'package:routed/routed.dart';
import 'package:test/test.dart';

String _fresh(String value) => String.fromCharCodes(value.codeUnits);

void main() {
  test('interns normalized paths with LRU eviction', () {
    final engine = Engine(
      config: EngineConfig(pathInternCacheSize: 2),
    );

    final firstA = engine.debugNormalizePath(_fresh('/a'));
    final firstB = engine.debugNormalizePath(_fresh('/b'));
    final secondA = engine.debugNormalizePath(_fresh('/a'));

    expect(identical(firstA, secondA), isTrue);

    engine.debugNormalizePath(_fresh('/c'));
    expect(engine.debugPathInternCacheSize, equals(2));

    final secondB = engine.debugNormalizePath(_fresh('/b'));
    expect(identical(firstB, secondB), isFalse);
  });
}
