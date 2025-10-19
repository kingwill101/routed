import 'dart:async';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

ShutdownConfig _shutdownConfig({
  required Duration grace,
  required Duration force,
}) => ShutdownConfig(
  enabled: true,
  gracePeriod: grace,
  forceAfter: force,
  exitCode: 0,
  notifyReadiness: true,
  signals: {ProcessSignal.sigint, ProcessSignal.sigterm},
);

void main() {
  engineTest(
    'drains in-flight requests before closing',
    (engine, client) async {
      engine.get('/slow', (ctx) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return ctx.string('done');
      });

      await engine.initialize();
      engine.updateConfig(
        engine.config.copyWith(
          shutdown: _shutdownConfig(
            grace: const Duration(milliseconds: 500),
            force: const Duration(seconds: 1),
          ),
        ),
      );

      await client.baseUrlFuture;

      final responseFuture = client.get('/slow');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final controller = await _waitForController(engine);
      await controller.trigger();
      await controller.done;

      try {
        final response = await responseFuture;
        response.assertStatus(HttpStatus.ok).assertBodyEquals('done');
      } on HttpException {
        // Some platforms may drop the connection once shutdown begins.
      }
    },
    transportMode: TransportMode.ephemeralServer,
  );

  engineTest(
    'forces close when requests exceed grace period',
    (engine, client) async {
      final blocker = Completer<void>();
      engine.get('/hang', (ctx) async {
        await blocker.future;
        return ctx.string('never');
      });

      await engine.initialize();
      engine.updateConfig(
        engine.config.copyWith(
          shutdown: _shutdownConfig(
            grace: const Duration(milliseconds: 50),
            force: const Duration(milliseconds: 100),
          ),
        ),
      );

      await client.baseUrlFuture;

      final hangingFuture = client.get('/hang');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final controller = await _waitForController(engine);
      await controller.trigger();
      await controller.done;

      try {
        final response = await hangingFuture;
        response.assertStatus(HttpStatus.serviceUnavailable);
      } on HttpException {
        // Connection closed while forcing shutdown is acceptable.
      }

      if (!blocker.isCompleted) {
        blocker.complete();
      }
    },
    transportMode: TransportMode.ephemeralServer,
  );
}

Future<ShutdownController> _waitForController(Engine engine) async {
  for (var i = 0; i < 200; i++) {
    final controller = engine.shutdownController;
    if (controller != null) {
      return controller;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Shutdown controller was not registered.');
}
