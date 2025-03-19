import 'dart:math';

import 'package:property_testing/src/property_test.dart';

/// A builder that generates test payloads based on a schema of generators.
class PayloadBuilder {
  /// Schema that maps field names to their corresponding generators.
  final Map<String, Generator> schema;

  /// Creates a [PayloadBuilder] with the given generator [schema].
  PayloadBuilder(this.schema);

  /// Generates a payload using the schema generators.
  ///
  /// Takes a [random] number generator and [size] parameter to pass to each
  /// generator in the schema. Returns a [ShrinkableValue] containing the
  /// generated payload map.
  ShrinkableValue<Map<String, dynamic>> generate(Random random, int size) {
    final payload = schema.map((key, generator) {
      return MapEntry(key, generator(random, size).value);
    });

    return DataShape(payload);
  }
}
