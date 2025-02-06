// ignore_for_file: unused_import

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:routed_testing/src/client.dart';
import 'package:routed_testing/src/environment.dart';
import 'package:routed_testing/src/transport/memory.dart';
import 'package:routed_testing/src/transport/server.dart';
import 'package:routed_testing/src/transport/transport.dart';
import 'package:test/test.dart';

typedef TestCallback = Future<void> Function(
    Engine engine, EngineTestClient client);

@visibleForTesting
void engineTest(
  String description,
  TestCallback callback, {
  TransportMode transportMode = TransportMode.inMemory,
  Map<String, dynamic>? configItems,
  EngineConfig? engineConfig,
  List<EngineOpt>? options,
}) {
  test(description, () async {
    // Initialize Engine with config
    final engine = Engine(
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
        ? EngineTestClient.inMemory(engine)
        : EngineTestClient.ephemeralServer(engine);

    try {
      await AppZone.run(
        engine: engine,
        body: () async {
          await callback(engine, client);
        },
      );
    } finally {
      await client.close();
    }
  });
}

/// Creates a group of tests with shared engine configuration
@visibleForTesting
void engineGroup(
  String description, {
  required void Function(Engine engine, EngineTestClient client) define,
  TransportMode transportMode = TransportMode.inMemory,
  Map<String, dynamic>? configItems,
  EngineConfig? engineConfig,
  List<EngineOpt>? options,
}) {
  group(description, () {
    Engine sharedEngine;
    EngineTestClient sharedClient;

    sharedEngine = Engine(
      configItems: configItems ??
          {
            'app.name': 'Test App',
            'app.env': 'testing',
          },
      config: engineConfig,
      options: options,
    );
    sharedClient = transportMode == TransportMode.inMemory
        ? EngineTestClient.inMemory(sharedEngine)
        : EngineTestClient.ephemeralServer(sharedEngine);

    tearDown(() async {
      await sharedClient.close();
    });

    // Run the test definitions with the shared configuration
    define(sharedEngine, sharedClient);
  });
}
