import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

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
      StreamSubscription<ProcessSignal>? sub;
      try {
        sub = signal.watch().listen((sig) {
          onTriggered?.call(sig);
          trigger(sig);
        });
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
  final enabled =
      config.getBoolOrNull('runtime.shutdown.enabled') ?? current.enabled;

  final grace =
      config.getDurationOrNull('runtime.shutdown.grace_period') ??
      current.gracePeriod;

  final force =
      config.getDurationOrNull('runtime.shutdown.force_after') ??
      current.forceAfter;

  final exitCode =
      config.getIntOrNull('runtime.shutdown.exit_code') ?? current.exitCode;

  final notify =
      config.getBoolOrNull('runtime.shutdown.notify_readiness') ??
      current.notifyReadiness;

  final signalNames =
      config.getStringListOrNull('runtime.shutdown.signals') ?? const [];

  final resolvedSignals = signalNames.isEmpty
      ? current.signals
      : signalNames.map(_signalFromName).whereType<ProcessSignal>().toSet();

  final normalizedGrace = grace < Duration.zero ? Duration.zero : grace;
  final normalizedForce = force < Duration.zero ? Duration.zero : force;

  return current.copyWith(
    enabled: enabled,
    gracePeriod: normalizedGrace,
    forceAfter: normalizedForce,
    exitCode: exitCode,
    notifyReadiness: notify,
    signals: resolvedSignals.isNotEmpty ? resolvedSignals : current.signals,
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
