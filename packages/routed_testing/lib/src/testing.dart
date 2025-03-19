library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/src/routed_transport.dart';
import 'package:server_testing/server_testing.dart';

typedef TestCallback = Future<void> Function(
    Engine engine, EngineTestClient client);

@visibleForTesting
@isTest
void engineTest(
  String description,
  TestCallback callback, {
  Engine? engine,
  TransportMode transportMode = TransportMode.inMemory,
  Map<String, dynamic>? configItems,
  EngineConfig? engineConfig,
  List<EngineOpt>? options,
}) {
  test(description, () async {
    // Use provided engine or create new one
    final testEngine = engine ??
        Engine(
          configItems: configItems ??
              {
                'app.name': 'Test App',
                'app.env': 'testing',
              },
          config: engineConfig,
          options: options,
        );

    // Initialize TestClient based on transport mode
    final client = transportMode == TransportMode.inMemory
        ? EngineTestClient.inMemory(RoutedRequestHandler(testEngine))
        : EngineTestClient.ephemeralServer(RoutedRequestHandler(testEngine));

    try {
      await AppZone.run(
        engine: testEngine,
        body: () async {
          await callback(testEngine, client);
        },
      );
    } finally {
      await client.close();
    }
  });
}

/// Creates a group of tests with shared engine configuration
@visibleForTesting
@isTestGroup
void engineGroup(
  String description, {
  Engine? engine,
  required void Function(Engine engine, EngineTestClient client) define,
  TransportMode transportMode = TransportMode.inMemory,
  Map<String, dynamic>? configItems,
  EngineConfig? engineConfig,
  List<EngineOpt>? options,
}) {
  group(description, () {
    Engine sharedEngine;
    EngineTestClient sharedClient;

    sharedEngine = engine ??
        Engine(
          configItems: configItems ??
              {
                'app.name': 'Test App',
                'app.env': 'testing',
              },
          config: engineConfig,
          options: options,
        );

    sharedClient = transportMode == TransportMode.inMemory
        ? EngineTestClient.inMemory(RoutedRequestHandler(sharedEngine))
        : EngineTestClient.ephemeralServer(RoutedRequestHandler(sharedEngine));

    tearDown(() async {
      await sharedClient.close();
    });

    define(sharedEngine, sharedClient);
  });
}
