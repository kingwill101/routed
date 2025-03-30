import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() async {
  final engine = Engine(); // Properly initialized engine
  final client = TestClient.inMemory(RoutedRequestHandler(engine));

  // Create a complex object generator
  final nameGenerator = Specialized.email().map((email) => email.split('@')[0]);
  final ageGenerator = Specialized.duration(
    min: const Duration(days: 18 * 365),
    max: const Duration(days: 100 * 365),
  ).map((duration) => duration.inDays ~/ 365);

  // Create a user payload generator that combines different fields
  final payloadGenerator =
      nameGenerator.flatMap((name) => ageGenerator.map((age) => {
            'name': name,
            'age': age,
            'registered': DateTime.now().toIso8601String(),
          }));

  final runner = PropertyTestRunner(
    payloadGenerator,
    (payload) async {
      // Test API endpoint with generated payload
      final response = await client.postJson('/api/users', payload);

      // Property: API should always return a valid status code
      expect(response.statusCode, anyOf([200, 400, 404, 422]));

      // Property: Server should never crash with 500 errors
      expect(response.statusCode, isNot(500));
    },
    PropertyConfig(numTests: 100),
  );

  final result = await runner.run();
}
