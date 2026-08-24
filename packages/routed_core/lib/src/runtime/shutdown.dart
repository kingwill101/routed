import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:routed_core/src/utils/process_env.dart';

/// Runtime configuration for graceful shutdown.
@immutable
class ShutdownConfig {
  /// Creates a [ShutdownConfig].
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

  /// Creates a [ShutdownConfig].
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
  /// Creates a [ShutdownController].
  ShutdownController({
    required this.config,
    required FutureOr<void> Function() onShutdown,
    required FutureOr<void> Function() onDrain,
    required FutureOr<void> Function() onForceClose,
  }) : _onShutdown = onShutdown,
       _onDrain = onDrain,
       _onForceClose = onForceClose;

  /// The config value.
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

  /// Whether this is draining is enabled.
  bool get isDraining => _draining;

  /// Whether this is closed is enabled.
  bool get isClosed => _closed;

  /// Whether this was forced is enabled.
  bool get wasForced => _forced;

  /// The trigger signal value.
  ProcessSignal? get triggerSignal => _triggerSignal;

  /// The done value.
  Future<void> get done => _completer.future;

  /// Creates a [ShutdownController].
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
    // hostIsWindows is portable (VM + Node); avoids Platform.isWindows on JS.
    if (!hostIsWindows) return true;
    return signal == ProcessSignal.sigint;
  }

  /// Creates a [ShutdownController].
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

  /// Creates a [ShutdownController].
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
