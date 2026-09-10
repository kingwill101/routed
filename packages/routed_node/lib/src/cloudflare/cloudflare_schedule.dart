import 'package:routed_jobs/routed_jobs.dart';
import 'package:server_contracts/server_contracts.dart';

import 'cloudflare_bindings_stub.dart'
    if (dart.library.js_interop) 'cloudflare_bindings_js.dart'
    as cloudflare_bindings;
import 'cloudflare_durable_object_store.dart';
import 'cloudflare_types.dart';

/// A durable schedule occurrence ledger backed by an atomic [Store] and lock.
///
/// [CloudflareDurableObjectStore] is a suitable Cloudflare implementation: its
/// lock operations are owner-aware across Worker isolates. The adapter
/// deliberately stores only leases and completed occurrence keys; schedule
/// definitions and executable actions remain in the application layer.
final class CloudflareScheduleStore implements ScheduleStore {
  /// Creates a schedule store from [store].
  CloudflareScheduleStore({
    required this.store,
    LockProvider? locks,
    this.keyPrefix = 'routed:schedule:',
    this.completedTtl = const Duration(days: 366),
  }) : locks = locks ?? _asLockProvider(store) {
    if (keyPrefix.trim().isEmpty) {
      throw ArgumentError.value(
        keyPrefix,
        'keyPrefix',
        'Schedule store key prefix must not be empty.',
      );
    }
    if (completedTtl < Duration.zero) {
      throw ArgumentError.value(
        completedTtl,
        'completedTtl',
        'Completed occurrence retention must not be negative.',
      );
    }
  }

  /// Atomic key-value store used for claims and completion records.
  final Store store;

  /// Owner-aware lock provider used for occurrence leases.
  final LockProvider locks;

  /// Namespace prefix applied to occurrence keys.
  final String keyPrefix;

  /// How long completed occurrences remain deduplicated.
  ///
  /// A zero duration asks the backend to retain the key indefinitely.
  final Duration completedTtl;

  @override
  Future<ScheduleClaim?> claim(
    ScheduleOccurrence occurrence, {
    required Duration lease,
  }) async {
    if (lease <= Duration.zero) {
      throw ArgumentError.value(lease, 'lease', 'Lease must be positive.');
    }
    if (await _completionExists(occurrence)) return null;
    final lock = await locks.lock(_lockKey(occurrence), _seconds(lease));
    if (!await lock.acquire()) return null;
    if (await _completionExists(occurrence)) {
      await lock.release();
      return null;
    }
    return ScheduleClaim(
      occurrence: occurrence,
      token: await lock.owner(),
    );
  }

  Future<bool> _completionExists(ScheduleOccurrence occurrence) async {
    final durableStore = _durableStore;
    if (durableStore != null) {
      return durableStore.scheduleCompletionExists(
        lockName: _lockKey(occurrence),
        completedKey: _completedKey(occurrence),
      );
    }
    return await store.get(_completedKey(occurrence)) != null;
  }

  @override
  Future<void> complete(ScheduleClaim claim) async {
    final durableStore = _durableStore;
    if (durableStore != null) {
      final completed = await durableStore.completeScheduleClaim(
        lockName: _lockKey(claim.occurrence),
        owner: claim.token,
        completedKey: _completedKey(claim.occurrence),
        completedSeconds: _seconds(completedTtl),
      );
      if (!completed) {
        throw StateError(
          'Schedule claim is no longer owned by this runtime.',
        );
      }
      return;
    }

    // Generic Store implementations do not have a compound operation for
    // fencing a write against a lock owner. Check ownership before writing so
    // stale claims are rejected; the Durable Object implementation above is
    // the atomic path used in production Cloudflare deployments.
    final lock = await locks.restoreLock(
      _lockKey(claim.occurrence),
      claim.token,
    );
    if (!await lock.isOwnedByCurrentProcess()) {
      throw StateError('Schedule claim is no longer owned by this runtime.');
    }
    final stored = await store.put(
      _completedKey(claim.occurrence),
      'completed',
      _seconds(completedTtl),
    );
    if (!stored) {
      throw StateError('Schedule completion could not be recorded.');
    }
    await lock.release();
  }

  CloudflareDurableObjectStore? get _durableStore {
    final candidate = store;
    if (candidate is CloudflareDurableObjectStore &&
        identical(locks, candidate)) {
      return candidate;
    }
    return null;
  }

  @override
  Future<void> release(ScheduleClaim claim) async {
    final lock = await locks.restoreLock(
      _lockKey(claim.occurrence),
      claim.token,
    );
    await lock.release();
  }

  String _completedKey(ScheduleOccurrence occurrence) =>
      '${keyPrefix}completed:${occurrence.key}';

  String _lockKey(ScheduleOccurrence occurrence) =>
      '${keyPrefix}lock:${occurrence.key}';

  static int _seconds(Duration duration) {
    if (duration <= Duration.zero) return 0;
    return (duration.inMilliseconds + 999) ~/ 1000;
  }

  static LockProvider _asLockProvider(Store store) {
    if (store case final LockProvider locks) return locks;
    throw ArgumentError.value(
      store,
      'store',
      'The schedule store must also implement LockProvider, or provide locks.',
    );
  }
}

/// Runs a Routed scheduler from one Cloudflare scheduled invocation.
Future<ScheduleTickReport> processCloudflareScheduleTick(
  CloudflareScheduledEvent event,
  RoutedScheduler scheduler,
) {
  return scheduler.tick(now: event.scheduledTime);
}

/// Installs a Cloudflare Cron Trigger that evaluates a Routed scheduler.
///
/// The factory is evaluated once per Worker isolate. Configure one fixed
/// platform cron (usually every minute); the scheduler then decides which
/// application schedules are due and dispatches their jobs.
void defineCloudflareSchedulerExportFactoryWithEnvironmentAsync(
  Future<RoutedScheduler> Function(CloudflareEnvironment environment) factory,
) {
  Future<RoutedScheduler>? schedulerFuture;
  cloudflare_bindings.defineCloudflareScheduledExport((event, environment, _) {
    schedulerFuture ??= factory(environment);
    return schedulerFuture!.then((scheduler) async {
      await processCloudflareScheduleTick(event, scheduler);
    });
  });
}
