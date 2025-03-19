import 'package:property_testing/src/generators.dart';
import 'package:property_testing/src/property_context.dart';
import 'package:property_testing/src/property_test.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:routed/routed.dart';
import 'package:server_testing/server_testing.dart';

void main() async {
  final engine = Engine();

  final tester = ForAllTester(Any.string(maxLength: 20),
      config: ExploreConfig(numRuns: 200));

  await tester.check((input) async {
    final context = PropertyContext(
        client: TestClient.inMemory(RoutedRequestHandler(engine)));

    // Convert bool to void using expect
    // final exists = await RouteProperties.routeExists(context, '/api/$input');
    // expect(exists, isTrue, reason: 'Route should exist');
  });
}
