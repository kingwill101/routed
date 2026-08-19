import 'dart:async';
import 'dart:io';

import 'package:routed_core/src/runtime/shutdown.dart';
import 'package:test/test.dart';

void main() {
  group('ShutdownConfig', () {
    test('copyWith preserves fields when no overrides given', () {
      final config = const ShutdownConfig(
        enabled: true,
        gracePeriod: Duration(seconds: 20),
        forceAfter: Duration(minutes: 1),
        exitCode: 0,
        notifyReadiness: true,
        signals: {ProcessSignal.sigint},
      );
      final copy = config.copyWith();
      expect(copy.enabled, config.enabled);
      expect(copy.gracePeriod, config.gracePeriod);
      expect(copy.forceAfter, config.forceAfter);
      expect(copy.exitCode, config.exitCode);
      expect(copy.notifyReadiness, config.notifyReadiness);
      expect(copy.signals, config.signals);
    });

    test('copyWith overrides specified fields', () {
      final config = const ShutdownConfig(
        enabled: true,
        gracePeriod: Duration(seconds: 20),
        forceAfter: Duration(minutes: 1),
        exitCode: 0,
        notifyReadiness: true,
        signals: {ProcessSignal.sigint},
      );
      final copy = config.copyWith(
        enabled: false,
        exitCode: 42,
        signals: {ProcessSignal.sigterm},
      );
      expect(copy.enabled, isFalse);
      expect(copy.exitCode, 42);
      expect(copy.signals, {ProcessSignal.sigterm});
      // Unoveridden fields unchanged.
      expect(copy.gracePeriod, config.gracePeriod);
    });
  });

  group('ShutdownController', () {
    late ShutdownConfig config;

    setUp(() {
      config = const ShutdownConfig(
        enabled: true,
        gracePeriod: Duration(seconds: 5),
        forceAfter: Duration(seconds: 30),
        exitCode: 0,
        notifyReadiness: true,
        signals: {},
      );
    });

    test(
      'trigger completes when drain completes before grace period',
      () async {
        final events = <String>[];
        final controller = ShutdownController(
          config: config,
          onShutdown: () => events.add('shutdown'),
          onDrain: () => events.add('drain'),
          onForceClose: () => events.add('force'),
        );

        expect(controller.isDraining, isFalse);
        expect(controller.isClosed, isFalse);

        await controller.trigger();

        expect(controller.isDraining, isTrue);
        expect(controller.isClosed, isTrue);
        expect(controller.wasForced, isFalse);
        expect(events, ['shutdown', 'drain']);
      },
    );

    test('double trigger is a no-op', () async {
      var shutdownCount = 0;
      final controller = ShutdownController(
        config: config,
        onShutdown: () => shutdownCount++,
        onDrain: () {},
        onForceClose: () {},
      );

      await controller.trigger();
      await controller.trigger();
      expect(shutdownCount, 1);
    });

    test('isDraining and isClosed transition correctly', () async {
      final completer = Completer<void>();
      late ShutdownController controller;
      controller = ShutdownController(
        config: config,
        onShutdown: () {
          expect(controller.isDraining, isTrue);
          expect(controller.isClosed, isFalse);
        },
        onDrain: () => completer.future,
        onForceClose: () {},
      );

      // Start trigger but don't await — drain is pending.
      final future = controller.trigger();
      // Allow microtask to process the onShutdown callback.
      await Future<void>.delayed(Duration.zero);
      expect(controller.isDraining, isTrue);
      expect(controller.isClosed, isFalse);

      completer.complete();
      await future;
      expect(controller.isClosed, isTrue);
    });

    test('trigger records signal', () async {
      final controller = ShutdownController(
        config: config,
        onShutdown: () {},
        onDrain: () {},
        onForceClose: () {},
      );

      await controller.trigger(ProcessSignal.sigint);
      expect(controller.triggerSignal, ProcessSignal.sigint);
    });

    test('zero grace period forces immediately', () async {
      final zeroGraceConfig = config.copyWith(gracePeriod: Duration.zero);
      final events = <String>[];
      final controller = ShutdownController(
        config: zeroGraceConfig,
        onShutdown: () => events.add('shutdown'),
        onDrain: () => events.add('drain'),
        onForceClose: () => events.add('force'),
      );

      await controller.trigger();
      expect(controller.wasForced, isTrue);
      expect(events, contains('force'));
    });
  });
}
