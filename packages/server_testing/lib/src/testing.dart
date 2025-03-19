library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:server_testing/server_testing.dart';

typedef TestCallback = Future<void> Function(EngineTestClient client);

@visibleForTesting
@isTest
void engineTest(
  String description,
  TestCallback callback, {
  required RequestHandler handler,
  TransportMode transportMode = TransportMode.inMemory,
  Timeout? timeout,
  Object? skip,
  Object? tags,
  Map<String, dynamic>? onPlatform,
  int? retry,
}) {
  test(description, () async {
    // Initialize TestClient based on transport mode
    final client = transportMode == TransportMode.inMemory
        ? EngineTestClient.inMemory(handler)
        : EngineTestClient.ephemeralServer(handler);

    try {
      await callback(client);
    } catch (e) {
      print(e);
    } finally {
      await client.close();
    }
  },
      timeout: timeout,
      skip: skip,
      tags: tags,
      onPlatform: onPlatform,
      retry: retry);
}
