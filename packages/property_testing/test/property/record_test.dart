import 'package:property_testing/src/property_test.dart';
import 'package:property_testing/src/record.dart';
import 'package:test/test.dart';
import 'dart:math' as math;

void main() {
  group('Record generation', () {
    test('can generate a basic record', () {
      final random = math.Random(42);
      const size = 10;

      makeRecord(id, name, test, test2) {
        return {"id": id, "name": name, "test": test, "test2": test2};
      }

      List<Generator> generators = [
        (random, size) => DataShape<int>(random.nextInt(size)),
        (random, size) => DataShape<String>("test", shrinkValues: ['']),
        (random, size) => DataShape<String>("test", shrinkValues: ['']),
        (random, size) => DataShape<String>("test", shrinkValues: [''])
      ];

      final record = Record(makeRecord, generators, random, size);
      expect(record.value, isNotNull);
      expect(record.value, isA<Map<String, dynamic>>());
      expect(record.value.length, equals(4));
    });
  });
}
