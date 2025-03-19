import 'package:property_testing/src/property_test.dart';
import 'dart:math' as math;

typedef RecordMaker = Map<String, dynamic> Function(
    dynamic id, dynamic name, dynamic test, dynamic test2);

class Record extends ShrinkableValue<Map<String, dynamic>> {
  final List<Generator> generators;
  final RecordMaker maker;
  final math.Random random;
  final int size;

  Record(this.maker, this.generators, this.random, this.size)
      : super(_generateValue(maker, generators, random, size));

  static Map<String, dynamic> _generateValue(RecordMaker maker,
      List<Generator> generators, math.Random random, int size) {
    final values = generators.map((gen) => gen(random, size).value).toList();

    return maker(values[0], values[1], values[2], values[3]);
  }

  @override
  bool canShrink() => true;

  @override
  dynamic shrink() {
    // Implement shrinking logic for records
    final shrunkValues =
        generators.map((gen) => gen(random, size ~/ 2).value).toList();

    return maker(
        shrunkValues[0], shrunkValues[1], shrunkValues[2], shrunkValues[3]);
  }
}
