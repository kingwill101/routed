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

/// Creates a test similar to `test()`, but with Engine transport preconfigured.
@visibleForTesting
void engineTest(
  String description,
  Future<void> Function(EngineTestClient client) body, {
  TransportMode transportMode = TransportMode.inMemory,
}) {
  test(description, () async {
    // Initialize Engine
    final engine = Engine();

    // Initialize TestClient based on transport mode
    final client = transportMode == TransportMode.inMemory
        ? EngineTestClient.inMemory(engine)
        : EngineTestClient.ephemeralServer(engine);

    try {
      await body(client);
    } finally {
      await client.close();
    }
  });
}

/// Creates a group of tests similar to `group()`, with optional transport configuration.
@visibleForTesting
void engineGroup(
  String description,
  void Function() body, {
  TransportMode? transportMode,
}) {
  group(description, () {
    if (transportMode != null) {
      // Push the transport mode to the stack
      EngineTestEnvironment.pushTransportMode(transportMode);
      // Ensure it's popped after the group is done
      tearDown(() {
        EngineTestEnvironment.popTransportMode();
      });
    }
    body();
  });
}
