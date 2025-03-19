import 'package:property_testing/src/generators.dart';
import 'package:property_testing/src/payload_builder.dart';
import 'package:property_testing/src/property_context.dart';
import 'package:property_testing/src/property_test.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() async {
  final engine = Engine(); // Properly initialized engine

  final schema = {
    'name': Any.string(),
    'phone': Any.phone(),
    'age': Any.randomDigit(min: 18, max: 100),
  };

  final payloadGenerator = PayloadBuilder(schema);

  final tester = ForAllTester(
      (random, size) => payloadGenerator.generate(random, size),
      config: ExploreConfig(numRuns: 200));

  await tester.check((payload) async {
    final context = PropertyContext(
      client: TestClient.inMemory(RoutedRequestHandler(engine)),
    );

    final response = await context.client.postJson('/api/users', payload);
    expect(response.statusCode, anyOf([200, 400]));
  });
}
