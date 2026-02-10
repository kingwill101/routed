import 'dart:async';
import 'dart:io';

import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/runtime/shutdown.dart';
import 'package:test/test.dart';

void main() {
  group('ShutdownConfig', () {
    test('copyWith preserves fields when no overrides given', () {
      final config = ShutdownConfig(
        enabled: true,
        gracePeriod: const Duration(seconds: 20),
        forceAfter: const Duration(minutes: 1),
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
      final config = ShutdownConfig(
        enabled: true,
        gracePeriod: const Duration(seconds: 20),
        forceAfter: const Duration(minutes: 1),
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

  group('RuntimeConfigSpec.fromMap', () {
    const spec = RuntimeConfigSpec();

    test('returns defaults for empty map', () {
      final result = spec.fromMap({});
      expect(result.shutdown.enabled, isTrue);
      expect(result.shutdown.gracePeriod, const Duration(seconds: 20));
      expect(result.shutdown.forceAfter, const Duration(minutes: 1));
      expect(result.shutdown.exitCode, 0);
      expect(result.shutdown.notifyReadiness, isTrue);
    });

    test('negative durations are clamped to zero', () {
      final result = spec.fromMap({
        'shutdown': {'grace_period': '-5s', 'force_after': '-10s'},
      });
      expect(result.shutdown.gracePeriod, Duration.zero);
      expect(result.shutdown.forceAfter, Duration.zero);
    });

    test('parses known signal names', () {
      final result = spec.fromMap({
        'shutdown': {
          'signals': ['sigint', 'sigterm', 'sighup'],
        },
      });
      expect(
        result.shutdown.signals,
        containsAll([
          ProcessSignal.sigint,
          ProcessSignal.sigterm,
          ProcessSignal.sighup,
        ]),
      );
    });

    test('unknown signal name throws ProviderConfigException', () {
      expect(
        () => spec.fromMap({
          'shutdown': {
            'signals': ['BOGUS'],
          },
        }),
        throwsA(isA<ProviderConfigException>()),
      );
    });
  });

  group('ShutdownController', () {
    late ShutdownConfig config;

    setUp(() {
      config = ShutdownConfig(
        enabled: true,
        gracePeriod: const Duration(seconds: 5),
        forceAfter: const Duration(seconds: 30),
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
