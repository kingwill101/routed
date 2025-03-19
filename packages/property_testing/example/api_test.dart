import 'package:property_testing/src/generators.dart';
import 'package:property_testing/src/payload_builder.dart';
import 'package:property_testing/src/property_test.dart';

void main() async {
  final schema = {
    'name': Any.string(),
    'phone': Any.phone(),
    'age': Any.randomDigit(min: 18, max: 100),
  };

  final payloadGenerator = PayloadBuilder(schema);
  final tester =
      ForAllTester((random, size) => payloadGenerator.generate(random, size));

  await tester.check((payload) async {
    print('payload: $payload');
  });
}
