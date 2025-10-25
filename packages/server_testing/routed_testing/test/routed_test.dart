import 'dart:async';
import 'dart:io' show Platform;

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

Future<void> main() async {
  Engine engine = Engine()
    ..get("/hello", (c) => c.string("world")).name("hello")
    ..get("/world", (c) => c.string("hello"));

  testRunner(TransportMode transportMode) {
    engineTest(
      'GET /world returns hello',
      (_, client) async {
        final response = await client.get('/world');
        response.assertStatus(200).assertBodyContains("hello");
      },
      engine: engine,
      transportMode: transportMode,
    );

    engineTest(
      'GET /hello returns world',
      (_, client) async {
        final response = await client.get('/hello');
        response.assertStatus(200).assertBodyContains("world");
      },
      engine: engine,
      transportMode: transportMode,
    );
  }

  group(
    "Ephemeral transport",
    () {
      testRunner(TransportMode.ephemeralServer);
    },
    skip: Platform.isWindows
        ? 'Ephemeral server transport not supported on Windows CI '
            'due to lack of SIGTERM support.'
        : false,
  );
  group("In-memory transport", () {
    testRunner(TransportMode.inMemory);
  });
}
