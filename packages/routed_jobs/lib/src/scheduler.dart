part of '../routed_jobs.dart';

/// Performs one scheduled action for a due occurrence.
typedef ScheduleAction = FutureOr<void> Function(ScheduleContext context);

/// Coordinates due schedule occurrences across multiple application runtimes.
///
/// A store is a small durable ledger rather than a source of executable code:
/// schedule definitions remain in Dart, while the store prevents two runtime
/// instances from dispatching the same occurrence. Applications that need
/// user-editable schedules can build a definition repository on top of the
/// same occurrence and lease contracts.
abstract interface class ScheduleStore {
  /// Claims [occurrence] for [lease].
  ///
  /// Returns a private lease for the one runtime that may execute the action.
  /// An unexpired claim or completed occurrence returns `null`.
  Future<ScheduleClaim?> claim(
    ScheduleOccurrence occurrence, {
    required Duration lease,
  });

  /// Marks [claim] as dispatched successfully.
  ///
  /// Implementations should retain the completed key long enough to cover
  /// the schedule's replay window. This operation is idempotent.
  Future<void> complete(ScheduleClaim claim);

  /// Releases [claim] whose action failed before dispatch completed.
  ///
  /// Implementations may keep the lease until it expires instead when a
  /// dispatch result is uncertain.
  Future<void> release(ScheduleClaim claim);
}

/// A schedule occurrence identified by its stable schedule name and instant.
final class ScheduleOccurrence {
  /// Creates an occurrence.
  ScheduleOccurrence({
    required this.scheduleName,
    required DateTime scheduledAt,
  }) : scheduledAt = scheduledAt.toUtc() {
    if (scheduleName.trim().isEmpty) {
      throw ArgumentError.value(
        scheduleName,
        'scheduleName',
        'Schedule name must not be empty.',
      );
    }
  }

  /// Stable schedule name.
  final String scheduleName;

  /// UTC instant represented by this occurrence.
  final DateTime scheduledAt;

  /// Stable key suitable for an idempotency or lease store.
  String get key => '$scheduleName:${scheduledAt.toIso8601String()}';
}

/// An ownership token returned by [ScheduleStore.claim].
///
/// The token prevents a slow or failed runtime from releasing or completing a
/// lease that has already expired and been claimed by another runtime.
final class ScheduleClaim {
  /// Creates a schedule claim.
  const ScheduleClaim({required this.occurrence, required this.token});

  /// Claimed occurrence.
  final ScheduleOccurrence occurrence;

  /// Opaque store-owned ownership token.
  final String token;
}

/// Context passed to a scheduled action.
final class ScheduleContext {
  /// Creates a schedule context.
  const ScheduleContext({
    required this.dispatcher,
    required this.occurrence,
    required this.now,
  });

  /// Dispatcher used to enqueue application jobs.
  final JobDispatcher dispatcher;

  /// The occurrence being handled.
  final ScheduleOccurrence occurrence;

  /// Time at which the scheduler tick started.
  final DateTime now;

  /// The schedule's stable name.
  String get scheduleName => occurrence.scheduleName;

  /// The intended UTC execution time.
  DateTime get scheduledAt => occurrence.scheduledAt;

  /// Idempotency key for jobs dispatched by this occurrence.
  String get idempotencyKey => occurrence.key;

  /// Dispatches a job with this occurrence's idempotency key by default.
  Future<JobReceipt<TResult>> dispatch<TArgs, TResult>(
    JobDefinition<TArgs, TResult> definition,
    TArgs args, {
    JobDispatchOptions options = const JobDispatchOptions(),
  }) {
    return dispatcher.dispatch(
      definition,
      args,
      options: JobDispatchOptions(
        queue: options.queue,
        delay: options.delay,
        idempotencyKey:
            options.idempotencyKey ?? '$idempotencyKey:${definition.name}',
        priority: options.priority,
        headers: options.headers,
        meta: <String, Object?>{
          ...options.meta,
          'schedule': scheduleName,
          'scheduledAt': scheduledAt.toIso8601String(),
        },
      ),
    );
  }
}

/// Describes when and how one scheduled action runs.
final class ScheduleDefinition {
  /// Creates a schedule definition.
  ScheduleDefinition({
    required this.name,
    required this.frequency,
    required this.action,
    this.enabled = true,
    this.maxCatchUp = 1,
  }) {
    _validate();
  }

  /// Creates a schedule that dispatches [job] with [args] when due.
  static ScheduleDefinition job<TArgs, TResult>({
    required String name,
    required ScheduleFrequency frequency,
    required JobDefinition<TArgs, TResult> job,
    required TArgs args,
    bool enabled = true,
    int maxCatchUp = 1,
  }) {
    return ScheduleDefinition(
      name: name,
      frequency: frequency,
      enabled: enabled,
      maxCatchUp: maxCatchUp,
      action: (context) async {
        await context.dispatch(job, args);
      },
    );
  }

  /// Stable application name.
  final String name;

  /// Frequency used to calculate due occurrences.
  final ScheduleFrequency frequency;

  /// Action invoked after an occurrence is claimed.
  final ScheduleAction action;

  /// Whether this schedule participates in ticks.
  final bool enabled;

  /// Maximum missed occurrences dispatched during one tick.
  final int maxCatchUp;

  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Schedule name must not be empty.',
      );
    }
    if (maxCatchUp < 1) {
      throw ArgumentError.value(
        maxCatchUp,
        'maxCatchUp',
        'maxCatchUp must be at least 1.',
      );
    }
  }
}

/// A portable schedule frequency.
///
/// Cron values are interpreted in UTC. Cloudflare scheduled events are UTC,
/// and keeping the core contract timezone-neutral avoids silently applying a
/// host-local timezone in a Worker. A timezone-aware frequency can be added
/// without changing the scheduler or store contracts.
abstract class ScheduleFrequency {
  /// Creates a custom schedule frequency.
  const ScheduleFrequency();

  /// Creates a fixed interval aligned to [anchor], or the Unix epoch.
  factory ScheduleFrequency.every(
    Duration interval, {
    DateTime? anchor,
  }) = _IntervalFrequency;

  /// Creates a standard five-field UTC cron frequency.
  factory ScheduleFrequency.cron(String expression) = _CronFrequency;

  /// Runs every minute.
  static ScheduleFrequency everyMinute() => _CronFrequency('* * * * *');

  /// Runs at [minute] past every hour.
  static ScheduleFrequency hourly({int minute = 0}) =>
      _CronFrequency('$minute * * * *');

  /// Runs every day at [hour]:[minute] UTC.
  static ScheduleFrequency dailyAt({int hour = 0, int minute = 0}) =>
      _CronFrequency('$minute $hour * * *');

  /// Runs every week on [weekday] at [hour]:[minute] UTC.
  ///
  /// [weekday] uses ISO values from 1 (Monday) through 7 (Sunday).
  static ScheduleFrequency weeklyOn(
    int weekday, {
    int hour = 0,
    int minute = 0,
  }) {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(
        weekday,
        'weekday',
        'Weekday must be between 1 (Monday) and 7 (Sunday).',
      );
    }
    return _CronFrequency('$minute $hour * * ${weekday == 7 ? 0 : weekday}');
  }

  /// Returns occurrences strictly after [from] and no later than [to].
  Iterable<DateTime> occurrencesBetween(
    DateTime from,
    DateTime to, {
    required int limit,
  });
}

final class _IntervalFrequency extends ScheduleFrequency {
  _IntervalFrequency(Duration interval, {DateTime? anchor})
    : interval = interval,
      anchor = (anchor ?? DateTime.utc(1970)).toUtc() {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Schedule intervals must be positive.',
      );
    }
  }

  final Duration interval;
  final DateTime anchor;

  @override
  Iterable<DateTime> occurrencesBetween(
    DateTime from,
    DateTime to, {
    required int limit,
  }) sync* {
    if (limit < 1) return;
    final start = from.toUtc();
    final end = to.toUtc();
    if (end.isBefore(start)) return;

    var candidate = anchor;
    if (candidate.isBefore(start) || candidate.isAtSameMomentAs(start)) {
      final elapsed = start.difference(anchor).inMicroseconds;
      final intervalMicros = interval.inMicroseconds;
      final steps = elapsed < 0 ? 0 : (elapsed ~/ intervalMicros) + 1;
      candidate = anchor.add(interval * steps);
    }
    var emitted = 0;
    while (!candidate.isAfter(end) && emitted < limit) {
      yield candidate;
      emitted += 1;
      candidate = candidate.add(interval);
    }
  }
}

final class _CronFrequency extends ScheduleFrequency {
  _CronFrequency(String expression)
    : expression = expression.trim(),
      _cron = _CronExpression.parse(expression) {
    if (this.expression.isEmpty) {
      throw ArgumentError.value(
        expression,
        'expression',
        'Cron expression must not be empty.',
      );
    }
  }

  final String expression;
  final _CronExpression _cron;

  @override
  Iterable<DateTime> occurrencesBetween(
    DateTime from,
    DateTime to, {
    required int limit,
  }) sync* {
    if (limit < 1) return;
    final start = from.toUtc();
    final end = to.toUtc();
    if (end.isBefore(start)) return;

    var candidate = DateTime.utc(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    );
    if (!candidate.isAfter(start)) {
      candidate = candidate.add(const Duration(minutes: 1));
    }
    var emitted = 0;
    while (!candidate.isAfter(end) && emitted < limit) {
      if (_cron.matches(candidate)) {
        yield candidate;
        emitted += 1;
      }
      candidate = candidate.add(const Duration(minutes: 1));
    }
  }
}

final class _CronExpression {
  _CronExpression({
    required this.minutes,
    required this.hours,
    required this.daysOfMonth,
    required this.months,
    required this.daysOfWeek,
    required this.daysOfMonthAny,
    required this.daysOfWeekAny,
  });

  factory _CronExpression.parse(String expression) {
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw FormatException(
        'Cron expressions must contain five fields: minute hour day month '
        'weekday.',
        expression,
      );
    }
    final dayOfMonth = _CronField.parse(fields[2], 1, 31);
    final dayOfWeek = _CronField.parse(fields[4], 0, 7, normalizeSunday: true);
    return _CronExpression(
      minutes: _CronField.parse(fields[0], 0, 59).values,
      hours: _CronField.parse(fields[1], 0, 23).values,
      daysOfMonth: dayOfMonth.values,
      months: _CronField.parse(fields[3], 1, 12).values,
      daysOfWeek: dayOfWeek.values,
      daysOfMonthAny: dayOfMonth.isAny,
      daysOfWeekAny: dayOfWeek.isAny,
    );
  }

  final Set<int> minutes;
  final Set<int> hours;
  final Set<int> daysOfMonth;
  final Set<int> months;
  final Set<int> daysOfWeek;
  final bool daysOfMonthAny;
  final bool daysOfWeekAny;

  bool matches(DateTime value) {
    final utc = value.toUtc();
    if (!minutes.contains(utc.minute) ||
        !hours.contains(utc.hour) ||
        !months.contains(utc.month)) {
      return false;
    }
    final dayOfMonthMatches = daysOfMonth.contains(utc.day);
    final dayOfWeekMatches = daysOfWeek.contains(utc.weekday % 7);
    if (daysOfMonthAny && daysOfWeekAny) return true;
    if (daysOfMonthAny) return dayOfWeekMatches;
    if (daysOfWeekAny) return dayOfMonthMatches;
    // Standard cron treats two restricted day fields as an inclusive OR.
    return dayOfMonthMatches || dayOfWeekMatches;
  }
}

final class _CronField {
  _CronField(this.values, {required this.isAny});

  factory _CronField.parse(
    String source,
    int minimum,
    int maximum, {
    bool normalizeSunday = false,
  }) {
    final token = source.trim();
    if (token.isEmpty) {
      throw FormatException('Cron field must not be empty.', source);
    }
    final values = <int>{};
    for (final part in token.split(',')) {
      final pieces = part.split('/');
      if (pieces.length > 2) {
        throw FormatException('Invalid cron step.', part);
      }
      final range = pieces[0];
      final step = pieces.length == 2 ? int.tryParse(pieces[1]) : 1;
      if (step == null || step < 1) {
        throw FormatException('Cron step must be positive.', part);
      }

      var start = minimum;
      var end = maximum;
      if (range != '*') {
        final bounds = range.split('-');
        if (bounds.length > 2) {
          throw FormatException('Invalid cron range.', part);
        }
        start = int.tryParse(bounds[0]) ?? -1;
        end = bounds.length == 2 ? int.tryParse(bounds[1]) ?? -1 : start;
      }
      if (start < minimum ||
          start > maximum ||
          end < minimum ||
          end > maximum) {
        throw FormatException('Cron value is outside its allowed range.', part);
      }
      if (end < start) {
        throw FormatException('Cron ranges must increase.', part);
      }
      for (var value = start; value <= end; value += step) {
        values.add(normalizeSunday && value == 7 ? 0 : value);
      }
    }
    if (values.isEmpty) {
      throw FormatException('Cron field contains no values.', source);
    }
    return _CronField(values, isAny: token == '*');
  }

  final Set<int> values;
  final bool isAny;
}

/// In-memory lease and occurrence ledger for local development and tests.
final class InMemoryScheduleStore implements ScheduleStore {
  /// Creates an in-memory store.
  InMemoryScheduleStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _MemoryClaim> _claims = <String, _MemoryClaim>{};
  final Set<String> _completed = <String>{};
  int _sequence = 0;

  /// Occurrences that have been completed by this store.
  Iterable<String> get completedKeys => Set<String>.unmodifiable(_completed);

  @override
  Future<ScheduleClaim?> claim(
    ScheduleOccurrence occurrence, {
    required Duration lease,
  }) async {
    if (lease <= Duration.zero) {
      throw ArgumentError.value(lease, 'lease', 'Lease must be positive.');
    }
    final key = occurrence.key;
    if (_completed.contains(key)) return null;
    final now = _clock().toUtc();
    final current = _claims[key];
    if (current != null && current.expiresAt.isAfter(now)) return null;
    final token = '$key:${now.microsecondsSinceEpoch}:${_sequence++}';
    _claims[key] = _MemoryClaim(token: token, expiresAt: now.add(lease));
    return ScheduleClaim(occurrence: occurrence, token: token);
  }

  @override
  Future<void> complete(ScheduleClaim claim) async {
    if (_completed.contains(claim.occurrence.key)) return;
    _ensureOwner(claim);
    _claims.remove(claim.occurrence.key);
    _completed.add(claim.occurrence.key);
  }

  @override
  Future<void> release(ScheduleClaim claim) async {
    final current = _claims[claim.occurrence.key];
    if (current?.token == claim.token) {
      _claims.remove(claim.occurrence.key);
    }
  }

  void _ensureOwner(ScheduleClaim claim) {
    final current = _claims[claim.occurrence.key];
    if (current?.token != claim.token) {
      throw StateError(
        'Schedule claim is no longer owned by this runtime.',
      );
    }
  }
}

final class _MemoryClaim {
  const _MemoryClaim({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

/// Result of one scheduler tick.
final class ScheduleTickReport {
  /// Creates a tick report.
  const ScheduleTickReport({
    required this.startedAt,
    required this.considered,
    required this.claimed,
    required this.completed,
    required this.skipped,
    required this.failures,
  });

  /// Time at which the tick began.
  final DateTime startedAt;

  /// Number of occurrences examined.
  final int considered;

  /// Number of occurrences claimed by this runtime.
  final int claimed;

  /// Number of actions completed and recorded.
  final int completed;

  /// Number of occurrences already claimed or completed elsewhere.
  final int skipped;

  /// Action or ledger failures observed during the tick.
  final List<ScheduleFailure> failures;

  /// Whether every claimed action completed successfully.
  bool get succeeded => failures.isEmpty;
}

/// Failure captured while running one scheduled occurrence.
final class ScheduleFailure {
  /// Creates a schedule failure.
  const ScheduleFailure({
    required this.occurrence,
    required this.error,
    required this.stackTrace,
  });

  /// Failed occurrence.
  final ScheduleOccurrence occurrence;

  /// Failure value.
  final Object error;

  /// Failure stack trace.
  final StackTrace stackTrace;
}

/// Error thrown when a tick has one or more failed occurrences.
final class ScheduleTickException implements Exception {
  /// Creates a tick exception.
  const ScheduleTickException(this.report);

  /// Report containing all failures from the tick.
  final ScheduleTickReport report;

  @override
  String toString() =>
      'Schedule tick failed for ${report.failures.length} occurrence(s).';
}

/// Runs registered schedules and delegates durable delivery to [JobDispatcher].
final class RoutedScheduler {
  /// Creates a scheduler.
  RoutedScheduler({
    required this.dispatcher,
    Iterable<ScheduleDefinition> schedules = const [],
    ScheduleStore? store,
    this.lookback = const Duration(minutes: 1),
    this.claimLease = const Duration(minutes: 5),
    this.tickInterval = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : schedules = List<ScheduleDefinition>.unmodifiable(schedules),
       store = store ?? InMemoryScheduleStore(clock: clock),
       _clock = clock ?? DateTime.now {
    _validate();
  }

  /// Job dispatcher used by schedule actions.
  final JobDispatcher dispatcher;

  /// Registered application schedules.
  final List<ScheduleDefinition> schedules;

  /// Durable claim and completion ledger.
  final ScheduleStore store;

  /// Window in which missed occurrences are considered.
  final Duration lookback;

  /// Lease held while an action is dispatching.
  final Duration claimLease;

  /// Interval used by the long-running `schedule:work` command.
  ///
  /// Platform-triggered runtimes should use [tick] from their scheduled
  /// event handler instead. The worker loop is intended for a normal
  /// long-lived Routed process.
  final Duration tickInterval;

  _StemBeatRunner? _beatRunner;
  Completer<void>? _workCompleter;

  final DateTime Function() _clock;

  /// Whether the long-running Beat loop is active.
  bool get isRunning => _beatRunner?.isRunning ?? false;

  /// Executes one scheduler tick.
  ///
  /// When [throwOnError] is true, all schedules are attempted but a
  /// [ScheduleTickException] is thrown after the report is assembled. This
  /// lets a host such as Cloudflare retry a failed scheduled invocation.
  Future<ScheduleTickReport> tick({
    DateTime? now,
    bool throwOnError = true,
  }) async {
    final startedAt = (now ?? _clock()).toUtc();
    var considered = 0;
    var claimed = 0;
    var completed = 0;
    var skipped = 0;
    final failures = <ScheduleFailure>[];

    for (final schedule in schedules) {
      if (!schedule.enabled) continue;
      final occurrences = schedule.frequency.occurrencesBetween(
        startedAt.subtract(lookback),
        startedAt,
        limit: schedule.maxCatchUp,
      );
      for (final scheduledAt in occurrences) {
        considered += 1;
        final occurrence = ScheduleOccurrence(
          scheduleName: schedule.name,
          scheduledAt: scheduledAt,
        );
        final claim = await store.claim(occurrence, lease: claimLease);
        if (claim == null) {
          skipped += 1;
          continue;
        }
        claimed += 1;
        try {
          await schedule.action(
            ScheduleContext(
              dispatcher: dispatcher,
              occurrence: occurrence,
              now: startedAt,
            ),
          );
        } on Object catch (error, stackTrace) {
          await store.release(claim);
          failures.add(
            ScheduleFailure(
              occurrence: occurrence,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          continue;
        }

        try {
          await store.complete(claim);
          completed += 1;
        } on Object catch (error, stackTrace) {
          // Keep the claim in place. The lease can expire and replay an
          // uncertain dispatch, which is safer than falsely marking it done.
          failures.add(
            ScheduleFailure(
              occurrence: occurrence,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        }
      }
    }

    final report = ScheduleTickReport(
      startedAt: startedAt,
      considered: considered,
      claimed: claimed,
      completed: completed,
      skipped: skipped,
      failures: List<ScheduleFailure>.unmodifiable(failures),
    );
    if (throwOnError && failures.isNotEmpty) {
      final failure = failures.first;
      Error.throwWithStackTrace(
        ScheduleTickException(report),
        failure.stackTrace,
      );
    }
    return report;
  }

  /// Starts a long-running scheduler loop.
  ///
  /// The loop is backed by Stem's `Beat` and schedule store internally. Stem
  /// remains an implementation detail: application code only deals with
  /// [ScheduleDefinition] and this facade. Use [stop] to end the loop.
  Future<void> start() async {
    final runner = _beatRunner ??= _StemBeatRunner(this);
    if (runner.isRunning) return;
    _workCompleter = Completer<void>();
    await runner.start();
  }

  /// Stops a loop started by [start] or [work].
  Future<void> stop() async {
    final runner = _beatRunner;
    if (runner == null) return;
    await runner.stop();
    final completer = _workCompleter;
    _workCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Runs one Beat-backed scheduling pass.
  ///
  /// This is useful for host runtimes that want Stem's schedule calculator
  /// without starting a timer. [tick] remains available when a host needs its
  /// detailed occurrence report or an explicit event timestamp.
  Future<void> runOnce() async {
    final runner = _beatRunner ??= _StemBeatRunner(this);
    await runner.runOnce();
  }

  /// Runs until [stop] is called.
  ///
  /// This method is used by the `schedule:work` command. A process receives
  /// the usual operating-system termination signal, and its host should call
  /// [stop] during shutdown when it owns the scheduler directly.
  Future<void> work() async {
    await start();
    await _workCompleter!.future;
  }

  /// Releases scheduler timers and other runtime resources.
  Future<void> close() => stop();

  void _validate() {
    if (lookback < Duration.zero) {
      throw ArgumentError.value(
        lookback,
        'lookback',
        'Scheduler lookback must not be negative.',
      );
    }
    if (claimLease <= Duration.zero) {
      throw ArgumentError.value(
        claimLease,
        'claimLease',
        'Scheduler claim lease must be positive.',
      );
    }
    if (tickInterval <= Duration.zero) {
      throw ArgumentError.value(
        tickInterval,
        'tickInterval',
        'Scheduler tick interval must be positive.',
      );
    }
    final names = <String>{};
    for (final schedule in schedules) {
      if (!names.add(schedule.name)) {
        throw ArgumentError(
          'Schedule names must be unique: "${schedule.name}".',
        );
      }
    }
  }
}
