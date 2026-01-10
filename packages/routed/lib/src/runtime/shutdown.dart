import 'dart:async';
import 'dart:io';

import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:meta/meta.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../config/spec.dart';

/// Runtime configuration grouping.
@immutable
class RuntimeConfig {
  const RuntimeConfig({required this.shutdown});

  final ShutdownConfig shutdown;
}

/// Runtime configuration for graceful shutdown.
@immutable
class ShutdownConfig {
  const ShutdownConfig({
    required this.enabled,
    required this.gracePeriod,
    required this.forceAfter,
    required this.exitCode,
    required this.notifyReadiness,
    required this.signals,
  });

  /// Whether graceful shutdown is enabled.
  final bool enabled;

  /// Time to wait for in-flight requests to complete before force-closing.
  final Duration gracePeriod;

  /// Maximum time before the process exits regardless of outstanding work.
  final Duration forceAfter;

  /// Process exit code to use after shutdown completes.
  final int exitCode;

  /// Whether readiness hooks should report "not ready" during draining.
  final bool notifyReadiness;

  /// Set of process signals that should trigger graceful shutdown.
  final Set<ProcessSignal> signals;

  ShutdownConfig copyWith({
    bool? enabled,
    Duration? gracePeriod,
    Duration? forceAfter,
    int? exitCode,
    bool? notifyReadiness,
    Set<ProcessSignal>? signals,
  }) {
    return ShutdownConfig(
      enabled: enabled ?? this.enabled,
      gracePeriod: gracePeriod ?? this.gracePeriod,
      forceAfter: forceAfter ?? this.forceAfter,
      exitCode: exitCode ?? this.exitCode,
      notifyReadiness: notifyReadiness ?? this.notifyReadiness,
      signals: Set<ProcessSignal>.from(signals ?? this.signals),
    );
  }
}

/// Typed runtime configuration spec for shutdown settings.
class RuntimeConfigSpec extends ConfigSpec<RuntimeConfig> {
  const RuntimeConfigSpec();

  @override
  String get root => 'runtime';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Runtime Configuration',
    description: 'Process runtime and shutdown settings.',
    properties: {
      'shutdown': ConfigSchema.object(
        description: 'Graceful shutdown settings.',
        properties: {
          'enabled': ConfigSchema.boolean(
            description: 'Enable graceful shutdown signal handling.',
            defaultValue: true,
          ),
          'grace_period': ConfigSchema.duration(
            description:
                'Time to wait for in-flight requests before forcing close.',
            defaultValue: '20s',
          ),
          'force_after': ConfigSchema.duration(
            description: 'Absolute time limit before shutdown completes.',
            defaultValue: '1m',
          ),
          'exit_code': ConfigSchema.integer(
            description: 'Process exit code returned after graceful shutdown.',
            defaultValue: 0,
          ),
          'notify_readiness': ConfigSchema.boolean(
            description: 'Mark readiness probes unhealthy while draining.',
            defaultValue: true,
          ),
          'signals': ConfigSchema.list(
            description: 'Signals that trigger graceful shutdown.',
            items: ConfigSchema.string(),
            defaultValue: const ['sigint', 'sigterm'],
          ),
        },
      ),
    },
  );

  @override
  RuntimeConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final shutdownMap = map['shutdown'];
    final shutdown = shutdownMap == null
        ? const <String, dynamic>{}
        : stringKeyedMap(shutdownMap as Object, 'runtime.shutdown');

    final enabled =
        parseBoolLike(
          shutdown['enabled'],
          context: 'runtime.shutdown.enabled',
          throwOnInvalid: true,
        ) ??
        true;

    final grace =
        parseDurationLike(
          shutdown['grace_period'],
          context: 'runtime.shutdown.grace_period',
          throwOnInvalid: true,
        ) ??
        const Duration(seconds: 20);

    final force =
        parseDurationLike(
          shutdown['force_after'],
          context: 'runtime.shutdown.force_after',
          throwOnInvalid: true,
        ) ??
        const Duration(minutes: 1);

    final exitCode =
        parseIntLike(
          shutdown['exit_code'],
          context: 'runtime.shutdown.exit_code',
          throwOnInvalid: true,
        ) ??
        0;

    final notify =
        parseBoolLike(
          shutdown['notify_readiness'],
          context: 'runtime.shutdown.notify_readiness',
          throwOnInvalid: true,
        ) ??
        true;

    final signalNames =
        parseStringList(
          shutdown['signals'],
          context: 'runtime.shutdown.signals',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        const <String>[];

    final signals = signalNames
        .map(_signalFromName)
        .whereType<ProcessSignal>()
        .toSet();

    final normalizedGrace = grace < Duration.zero ? Duration.zero : grace;
    final normalizedForce = force < Duration.zero ? Duration.zero : force;

    return RuntimeConfig(
      shutdown: ShutdownConfig(
        enabled: enabled,
        gracePeriod: normalizedGrace,
        forceAfter: normalizedForce,
        exitCode: exitCode,
        notifyReadiness: notify,
        signals: signals,
      ),
    );
  }

  @override
  Map<String, dynamic> toMap(RuntimeConfig value) {
    return {
      'shutdown': {
        'enabled': value.shutdown.enabled,
        'grace_period': value.shutdown.gracePeriod,
        'force_after': value.shutdown.forceAfter,
        'exit_code': value.shutdown.exitCode,
        'notify_readiness': value.shutdown.notifyReadiness,
        'signals': value.shutdown.signals.map(_signalName).toList(),
      },
    };
  }
}

/// Tracks the state of a graceful shutdown.
class ShutdownController {
  ShutdownController({
    required this.config,
    required FutureOr<void> Function() onShutdown,
    required FutureOr<void> Function() onDrain,
    required FutureOr<void> Function() onForceClose,
  }) : _onShutdown = onShutdown,
       _onDrain = onDrain,
       _onForceClose = onForceClose;

  final ShutdownConfig config;

  final FutureOr<void> Function() _onShutdown;
  final FutureOr<void> Function() _onDrain;
  final FutureOr<void> Function() _onForceClose;

  final _listeners = <StreamSubscription<ProcessSignal>>[];
  final _completer = Completer<void>();
  bool _draining = false;
  bool _closed = false;
  bool _forced = false;
  ProcessSignal? _triggerSignal;

  bool get isDraining => _draining;

  bool get isClosed => _closed;

  bool get wasForced => _forced;

  ProcessSignal? get triggerSignal => _triggerSignal;

  Future<void> get done => _completer.future;

  void watchSignals([void Function(ProcessSignal signal)? onTriggered]) {
    if (!config.enabled || _listeners.isNotEmpty) return;

    for (final signal in config.signals) {
      if (!_isSignalSupported(signal)) {
        continue;
      }
      StreamSubscription<ProcessSignal>? sub;
      try {
        sub = signal.watch().listen((sig) {
          onTriggered?.call(sig);
          trigger(sig);
        }, onError: (_, _) {});
      } on StateError {
        // Platform does not support this signal.
      } on SignalException {
        // Platform does not support this signal.
      }
      if (sub != null) {
        _listeners.add(sub);
      }
    }
  }

  bool _isSignalSupported(ProcessSignal signal) {
    if (!Platform.isWindows) return true;
    return signal == ProcessSignal.sigint;
  }

  Future<void> trigger([ProcessSignal? signal]) async {
    if (_draining || _closed) {
      return;
    }
    _draining = true;
    _triggerSignal = signal;
    await _onShutdown();

    final grace = config.gracePeriod;
    final force = config.forceAfter;
    Timer? forceTimer;
    Timer? graceTimer;

    if (force > Duration.zero) {
      forceTimer = Timer(force, () async {
        if (_closed) return;
        await _onForceClose();
        _finish(forced: true);
      });
    }

    if (grace <= Duration.zero) {
      await _onForceClose();
      forceTimer?.cancel();
      _finish(forced: true);
      return;
    }

    graceTimer = Timer(grace, () async {
      if (_closed) {
        return;
      }
      await _onForceClose();
      forceTimer?.cancel();
      _finish(forced: true);
    });

    try {
      await _onDrain();
      if (_closed) {
        return;
      }
      graceTimer.cancel();
      forceTimer?.cancel();
      _finish();
    } catch (_) {
      if (_closed) return;
      graceTimer.cancel();
      forceTimer?.cancel();
      await _onForceClose();
      _finish(forced: true);
      rethrow;
    }
  }

  void dispose() {
    for (final sub in _listeners) {
      sub.cancel();
    }
    _listeners.clear();
  }

  void _finish({bool forced = false}) {
    if (_closed) return;
    _closed = true;
    _forced = forced;
    dispose();
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

/// Resolves shutdown configuration from [config], falling back to
/// [current] when values are not supplied.
ShutdownConfig resolveShutdownConfig(Config config, ShutdownConfig current) {
  final resolved = const RuntimeConfigSpec().resolve(config).shutdown;
  final hasEnabled = config.has('runtime.shutdown.enabled');
  final hasGrace = config.has('runtime.shutdown.grace_period');
  final hasForce = config.has('runtime.shutdown.force_after');
  final hasExitCode = config.has('runtime.shutdown.exit_code');
  final hasNotify = config.has('runtime.shutdown.notify_readiness');
  final hasSignals = config.has('runtime.shutdown.signals');

  final signals = hasSignals
      ? (resolved.signals.isNotEmpty ? resolved.signals : current.signals)
      : current.signals;

  return current.copyWith(
    enabled: hasEnabled ? resolved.enabled : current.enabled,
    gracePeriod: hasGrace ? resolved.gracePeriod : current.gracePeriod,
    forceAfter: hasForce ? resolved.forceAfter : current.forceAfter,
    exitCode: hasExitCode ? resolved.exitCode : current.exitCode,
    notifyReadiness: hasNotify
        ? resolved.notifyReadiness
        : current.notifyReadiness,
    signals: signals,
  );
}

ProcessSignal? _signalFromName(String name) {
  switch (name.trim().toLowerCase()) {
    case 'sigint':
      return ProcessSignal.sigint;
    case 'sigterm':
      return ProcessSignal.sigterm;
    case 'sighup':
      return ProcessSignal.sighup;
    case 'sigusr1':
      return ProcessSignal.sigusr1;
    case 'sigusr2':
      return ProcessSignal.sigusr2;
    default:
      throw ProviderConfigException(
        'runtime.shutdown.signals contains unknown signal "$name"',
      );
  }
}

String _signalName(ProcessSignal signal) {
  if (signal == ProcessSignal.sigint) return 'sigint';
  if (signal == ProcessSignal.sigterm) return 'sigterm';
  if (signal == ProcessSignal.sighup) return 'sighup';
  if (signal == ProcessSignal.sigusr1) return 'sigusr1';
  if (signal == ProcessSignal.sigusr2) return 'sigusr2';
  return signal.toString().split('.').last.toLowerCase();
}
