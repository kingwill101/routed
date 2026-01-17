import 'dart:async';

import 'package:meta/meta.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/src/routed_transport.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart'
    as test_package; // Use a prefix to avoid conflicts

/// A callback function used by the `engineTest` helper.
/// It receives the `Engine` and `TestClient` instances for the test.
typedef TestCallback = Future<void> Function(Engine engine, TestClient client);

/// A callback function used by the `engineGroup` helper to define tests within the group.
/// It receives the shared `Engine` and `TestClient` instances, and a function
/// (`engineTest`) which should be used to define individual tests within the group.
typedef EngineTestFunction =
    void Function(String description, TestCallback callback);

/// Defines a single test that runs with a dedicated `Engine` and `TestClient`.
///
/// This helper ensures that the test callback is executed within an `AppZone`,
/// providing the correct context for `routed` operations.
///
/// - `description`: The description of the test.
/// - `callback`: The async function containing the test logic. It receives the
///   `Engine` and `TestClient` instances.
/// - `engine`: An optional existing `Engine` instance to use. If not provided,
///   a new one is created.
/// - `client`: An optional existing `TestClient` instance to use. If not provided,
///   a new one is created based on `transportMode`.
/// - `transportMode`: The transport mode for the `TestClient` (defaults to `inMemory`).
/// - `configItems`: Initial configuration items for the `Engine` if a new one is created.
/// - `engineConfig`: An `EngineConfig` instance for the `Engine` if a new one is created.
/// - `options`: A list of `EngineOpt` for the `Engine` if a new one is created.
/// - `autoCloseEngine`: Close the provided engine after the test finishes. Engines
///   created by this helper are always closed automatically.
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
  bool autoCloseEngine = false,
}) {
  test_package.test(description, () async {
    final ownsEngine = engine == null;
    final shouldCloseEngine = ownsEngine || autoCloseEngine;

    final testEngine =
        engine ??
        Engine.full(
          configItems:
              configItems ?? {'app.name': 'Test App', 'app.env': 'testing'},
          config: engineConfig,
          options: options,
        );

    final handler = RoutedRequestHandler(testEngine);
    final client = transportMode == TransportMode.inMemory
        ? TestClient.inMemory(handler)
        : TestClient.ephemeralServer(handler);

    try {
      // TEMP: avoid AppZone wrapping to surface zone dependencies.
      await callback(testEngine, client);
    } finally {
      await client.close();
      if (shouldCloseEngine) {
        // Ensure providers are booted before cleanup so provider teardown
        // hooks can resolve their dependencies.
        await testEngine.initialize();
        await testEngine.close();
      }
    }
  });
}

/// Creates a group of tests with shared engine configuration
@visibleForTesting
@isTestGroup
void engineGroup(
  String description, {
  Engine? engine,
  required void Function(Engine engine, TestClient client, EngineTestFunction)
  define,
  TransportMode transportMode = TransportMode.inMemory,
  Map<String, dynamic>? configItems,
  EngineConfig? engineConfig,
  List<EngineOpt>? options,
}) {
  test_package.group(description, () {
    void testWrapper(String testDescription, TestCallback callback) {
      engineTest(
        testDescription,
        callback,
        transportMode: transportMode,
        configItems: configItems,
        engineConfig: engineConfig,
        options: options,
      );
    }

    final ownsGroupEngine = engine == null;
    final groupEngine =
        engine ??
        Engine.full(
          configItems:
              configItems ?? {'app.name': 'Test App', 'app.env': 'testing'},
          config: engineConfig,
          options: options,
        );

    final handler = RoutedRequestHandler(groupEngine);
    final groupClient = transportMode == TransportMode.inMemory
        ? TestClient.inMemory(handler)
        : TestClient.ephemeralServer(handler);

    define(groupEngine, groupClient, testWrapper);

    test_package.setUpAll(() async {
      await groupEngine.initialize();
    });

    test_package.tearDownAll(() async {
      await groupClient.close();
      if (ownsGroupEngine) {
        await groupEngine.close();
      }
    });
  });
}
