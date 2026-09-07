part of '../routed_jobs.dart';

/// Internal bridge between Routed's typed schedule definitions and Stem Beat.
///
/// This file is deliberately not exported. Routed owns the application-facing
/// schedule and occurrence contracts; Stem owns the timer, due-entry
/// calculation, and schedule execution state used by a normal long-lived
/// process.
final class _StemBeatRunner {
  _StemBeatRunner(this.scheduler)
    : _store = _RoutedBeatStore(),
      _publisher = _RoutedBeatPublisher(scheduler),
      _clock = _SchedulerStemClock(scheduler._clock) {
    _beat = stem_beat.Beat.withPublisher(
      store: _store,
      publisher: _publisher,
      tickInterval: scheduler.tickInterval,
      lockTtl: scheduler.claimLease,
    );
  }

  final RoutedScheduler scheduler;
  final _RoutedBeatStore _store;
  final _RoutedBeatPublisher _publisher;
  final stem_clock.StemClock _clock;
  late final stem_beat.Beat _beat;
  bool _initialized = false;

  bool get isRunning => _running;
  bool _running = false;

  Future<void> start() async {
    await _initialize();
    if (_running) return;
    _running = true;
    await stem_clock.withStemClock(_clock, _beat.start);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _beat.stop();
  }

  Future<void> runOnce() async {
    await _initialize();
    await stem_clock.withStemClock(_clock, _beat.runOnce);
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    final now = scheduler._clock().toUtc();
    for (final definition in scheduler.schedules) {
      await _store.upsert(
        stem.ScheduleEntry(
          id: definition.name,
          taskName: 'routed.schedule.${definition.name}',
          queue: 'routed-schedule',
          spec: _toStemSpec(definition.frequency),
          enabled: definition.enabled,
          nextRunAt: _nextRunAt(definition.frequency, now),
          meta: <String, Object?>{'routed.schedule': definition.name},
        ),
      );
    }
    _initialized = true;
  }

  DateTime _nextRunAt(ScheduleFrequency frequency, DateTime now) {
    final candidates = frequency.occurrencesBetween(
      // The Routed one-shot API treats an occurrence at the tick instant as
      // due. Preserve that boundary for a worker that starts exactly on a
      // cron/interval boundary while still ignoring older occurrences.
      now.subtract(const Duration(microseconds: 1)),
      now.add(const Duration(days: 366)),
      limit: 1,
    );
    for (final candidate in candidates) {
      return candidate;
    }
    // An interval anchored beyond the look-ahead window is still safe to
    // wake on the next Beat interval; the Stem store will calculate the next
    // occurrence after execution.
    return now.add(scheduler.tickInterval);
  }

  static stem.ScheduleSpec _toStemSpec(ScheduleFrequency frequency) {
    return switch (frequency) {
      _IntervalFrequency(:final interval, :final anchor) =>
        stem.IntervalScheduleSpec(every: interval, startAt: anchor),
      _CronFrequency(:final expression) => stem.CronScheduleSpec(
        expression: expression,
      ),
      _ => throw StateError(
        'Unsupported Routed schedule frequency: ${frequency.runtimeType}',
      ),
    };
  }
}

/// A portable schedule store for Beat's due-entry contract.
///
/// Stem's optional `memory.dart` barrel also imports VM worker internals, so it
/// cannot be used by a Cloudflare Worker. This tiny adapter keeps only the
/// schedule state needed by Beat and uses Stem's portable calculator for the
/// temporal rules.
final class _RoutedBeatStore implements stem.ScheduleStore {
  final Map<String, stem.ScheduleEntry> _entries =
      <String, stem.ScheduleEntry>{};
  final Set<String> _locked = <String>{};
  final Map<String, DateTime> _dueAt = <String, DateTime>{};
  final stem.ScheduleCalculator _calculator = stem.ScheduleCalculator();

  DateTime? dueAt(String id) => _dueAt[id];

  @override
  Future<List<stem.ScheduleEntry>> due(
    DateTime now, {
    int limit = 100,
  }) async {
    final entries =
        _entries.values
            .where(
              (entry) =>
                  !_locked.contains(entry.id) &&
                  entry.enabled &&
                  entry.nextRunAt != null &&
                  !entry.nextRunAt!.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.nextRunAt!.compareTo(b.nextRunAt!));
    final selected = <stem.ScheduleEntry>[];
    for (final entry in entries.take(limit)) {
      _locked.add(entry.id);
      _dueAt[entry.id] = (entry.nextRunAt ?? now).toUtc();
      selected.add(entry);
    }
    return selected;
  }

  @override
  Future<void> upsert(stem.ScheduleEntry entry) async {
    _entries[entry.id] = entry;
    _locked.remove(entry.id);
  }

  @override
  Future<void> remove(String id) async {
    _entries.remove(id);
    _locked.remove(id);
    _dueAt.remove(id);
  }

  @override
  Future<List<stem.ScheduleEntry>> list({int? limit}) async {
    final entries = _entries.values.toList()
      ..sort(
        (a, b) => (a.nextRunAt ?? DateTime.utc(9999)).compareTo(
          b.nextRunAt ?? DateTime.utc(9999),
        ),
      );
    return limit == null ? entries : entries.take(limit).toList();
  }

  @override
  Future<stem.ScheduleEntry?> get(String id) async => _entries[id];

  @override
  Future<void> markExecuted(
    String id, {
    required DateTime scheduledFor,
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
    bool success = true,
    Duration? runDuration,
    DateTime? nextRunAt,
    Duration? drift,
  }) async {
    final entry = _entries[id];
    if (entry == null) return;
    _dueAt.remove(id);
    final updated = entry.copyWith(
      lastRunAt: executedAt,
      lastJitter: jitter,
      lastError: lastError,
      lastSuccessAt: success ? executedAt : entry.lastSuccessAt,
      lastErrorAt: success ? entry.lastErrorAt : executedAt,
      totalRunCount: entry.totalRunCount + 1,
      drift: drift,
    );

    // Beat calls markExecuted with success=false after a publish/action
    // failure. Keep the original due timestamp so the next pass retries the
    // same occurrence instead of advancing past a transient failure.
    if (!success) {
      _entries[id] = updated.copyWith(
        nextRunAt: entry.nextRunAt ?? scheduledFor,
      );
      _locked.remove(id);
      return;
    }

    var next = nextRunAt;
    if (next == null && updated.enabled) {
      try {
        next = _calculator.nextRun(updated, executedAt, includeJitter: false);
      } on Object {
        next = executedAt.add(const Duration(minutes: 1));
      }
    }
    _entries[id] = updated.copyWith(nextRunAt: next);
    _locked.remove(id);
  }
}

final class _RoutedBeatPublisher implements stem.TaskPublisher {
  _RoutedBeatPublisher(this.scheduler);

  final RoutedScheduler scheduler;

  @override
  Future<void> publish(
    stem.Envelope envelope, {
    stem.RoutingInfo? routing,
  }) async {
    final name = envelope.headers['schedule-id'];
    if (name == null) {
      throw StateError('Stem Beat published a schedule without an id.');
    }
    ScheduleDefinition? definition;
    for (final candidate in scheduler.schedules) {
      if (candidate.name == name) {
        definition = candidate;
        break;
      }
    }
    if (definition == null) {
      throw StateError('No Routed schedule is registered for "$name".');
    }

    final scheduledAt =
        scheduler._beatRunner?._store.dueAt(name) ?? scheduler._clock().toUtc();
    final occurrence = ScheduleOccurrence(
      scheduleName: name,
      scheduledAt: scheduledAt,
    );
    final claim = await scheduler.store.claim(
      occurrence,
      lease: scheduler.claimLease,
    );
    if (claim == null) return;

    try {
      await definition.action(
        ScheduleContext(
          dispatcher: scheduler.dispatcher,
          occurrence: occurrence,
          now: scheduler._clock().toUtc(),
        ),
      );
      await scheduler.store.complete(claim);
    } on Object {
      await scheduler.store.release(claim);
      rethrow;
    }
  }
}

final class _SchedulerStemClock extends stem_clock.StemClock {
  _SchedulerStemClock(this._clock);

  final DateTime Function() _clock;

  @override
  DateTime now() => _clock().toUtc();
}
