import 'package:routed_core/routed_core.dart';
import 'package:routed_jobs/routed_jobs.dart';
import 'package:test/test.dart';

void main() {
  group('ScheduleFrequency', () {
    test('supports interval and convenience frequencies', () {
      final from = DateTime.utc(2026, 1, 1, 8, 59);
      final to = DateTime.utc(2026, 1, 1, 9, 1);

      expect(
        ScheduleFrequency.everyMinute()
            .occurrencesBetween(from, to, limit: 10)
            .toList(),
        <DateTime>[
          DateTime.utc(2026, 1, 1, 9),
          DateTime.utc(2026, 1, 1, 9, 1),
        ],
      );
      expect(
        ScheduleFrequency.dailyAt(
          hour: 9,
        ).occurrencesBetween(from, to, limit: 10).toList(),
        <DateTime>[DateTime.utc(2026, 1, 1, 9)],
      );
      expect(
        ScheduleFrequency.every(const Duration(minutes: 5))
            .occurrencesBetween(
              DateTime.utc(2026),
              DateTime.utc(2026, 1, 1, 0, 11),
              limit: 10,
            )
            .toList(),
        <DateTime>[
          DateTime.utc(2026, 1, 1, 0, 5),
          DateTime.utc(2026, 1, 1, 0, 10),
        ],
      );
    });

    test(
      'parses lists, ranges, steps, and standard day-field OR semantics',
      () {
        final frequency = ScheduleFrequency.cron('0 9 1,15 * 1-5');

        expect(
          frequency
              .occurrencesBetween(
                DateTime.utc(2026),
                DateTime.utc(2026, 1, 16, 9),
                limit: 10,
              )
              .toList(),
          <DateTime>[
            DateTime.utc(2026, 1, 1, 9),
            DateTime.utc(2026, 1, 2, 9),
            DateTime.utc(2026, 1, 5, 9),
            DateTime.utc(2026, 1, 6, 9),
            DateTime.utc(2026, 1, 7, 9),
            DateTime.utc(2026, 1, 8, 9),
            DateTime.utc(2026, 1, 9, 9),
            DateTime.utc(2026, 1, 12, 9),
            DateTime.utc(2026, 1, 13, 9),
            DateTime.utc(2026, 1, 14, 9),
          ],
        );
      },
    );

    test('rejects malformed expressions', () {
      expect(
        () => ScheduleFrequency.cron('* * * *'),
        throwsFormatException,
      );
      expect(
        () => ScheduleFrequency.cron('61 * * * *'),
        throwsFormatException,
      );
      expect(
        () => ScheduleFrequency.every(Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('RoutedScheduler', () {
    test('claims an occurrence once and dispatches a typed job', () async {
      final queue = InMemoryJobQueue();
      final job = JobDefinition<String, String>(
        name: 'reports.daily',
        encode: (value) => {'value': value},
        decode: (payload) => payload['value']! as String,
        handle: (_, value) async => value,
      );
      final jobs = RoutedJobs(queue: queue, definitions: [job]);
      final scheduler = RoutedScheduler(
        dispatcher: jobs,
        schedules: [
          ScheduleDefinition.job(
            name: 'reports.daily.schedule',
            frequency: ScheduleFrequency.dailyAt(hour: 9),
            job: job,
            args: 'hello',
          ),
        ],
      );
      final now = DateTime.utc(2026, 1, 1, 9);

      final first = await scheduler.tick(now: now);
      final second = await scheduler.tick(now: now);

      expect(first.considered, 1);
      expect(first.claimed, 1);
      expect(first.completed, 1);
      expect(second.skipped, 1);
      expect(queue.messages, hasLength(1));
      expect(queue.messages.single.args, {'value': 'hello'});
      expect(queue.messages.single.headers, isEmpty);
      expect(queue.messages.single.meta['schedule'], 'reports.daily.schedule');
      expect(queue.messages.single.meta['scheduledAt'], now.toIso8601String());
      expect(queue.messages.single.id, contains('reports.daily.schedule'));

      await jobs.close();
    });

    test('releases a failed action and can report without throwing', () async {
      final store = InMemoryScheduleStore();
      var attempts = 0;
      final scheduler = RoutedScheduler(
        dispatcher: RoutedJobs(queue: InMemoryJobQueue()),
        store: store,
        schedules: [
          ScheduleDefinition(
            name: 'unstable',
            frequency: ScheduleFrequency.everyMinute(),
            action: (_) async {
              attempts += 1;
              throw StateError('not yet');
            },
          ),
        ],
      );

      final first = await scheduler.tick(
        now: DateTime.utc(2026, 1, 1, 0, 1),
        throwOnError: false,
      );
      final second = await scheduler.tick(
        now: DateTime.utc(2026, 1, 1, 0, 1),
        throwOnError: false,
      );

      expect(first.failures, hasLength(1));
      expect(second.claimed, 1);
      expect(attempts, 2);
    });

    test('completed occurrences do not consume the catch-up budget', () async {
      final now = DateTime.utc(2026, 1, 1, 0, 3);
      final store = InMemoryScheduleStore(clock: () => now);
      final oldest = ScheduleOccurrence(
        scheduleName: 'backfill',
        scheduledAt: DateTime.utc(2026, 1, 1, 0, 1),
      );
      final completedClaim = await store.claim(
        oldest,
        lease: const Duration(minutes: 1),
      );
      await store.complete(completedClaim!);

      DateTime? dispatchedAt;
      final scheduler = RoutedScheduler(
        dispatcher: RoutedJobs(queue: InMemoryJobQueue()),
        store: store,
        lookback: const Duration(minutes: 3),
        schedules: [
          ScheduleDefinition(
            name: 'backfill',
            frequency: ScheduleFrequency.everyMinute(),
            action: (context) async {
              dispatchedAt = context.occurrence.scheduledAt;
            },
          ),
        ],
      );

      final report = await scheduler.tick(now: now);

      expect(report.skipped, 1);
      expect(report.claimed, 1);
      expect(report.completed, 1);
      expect(dispatchedAt, DateTime.utc(2026, 1, 1, 0, 2));
      await scheduler.close();
    });

    test(
      "does not let an expired claim complete another runtime's lease",
      () async {
        var now = DateTime.utc(2026);
        final store = InMemoryScheduleStore(clock: () => now);
        final occurrence = ScheduleOccurrence(
          scheduleName: 'slow',
          scheduledAt: now,
        );

        final first = await store.claim(
          occurrence,
          lease: const Duration(minutes: 1),
        );
        now = now.add(const Duration(minutes: 2));
        final second = await store.claim(
          occurrence,
          lease: const Duration(minutes: 1),
        );

        expect(first, isNotNull);
        expect(second, isNotNull);
        await expectLater(store.complete(first!), throwsStateError);
        await store.complete(second!);
      },
    );

    test('throws after running all failed schedules by default', () async {
      final scheduler = RoutedScheduler(
        dispatcher: RoutedJobs(queue: InMemoryJobQueue()),
        schedules: [
          ScheduleDefinition(
            name: 'broken',
            frequency: ScheduleFrequency.everyMinute(),
            action: (_) => throw StateError('broken'),
          ),
        ],
      );

      await expectLater(
        scheduler.tick(now: DateTime.utc(2026, 1, 1, 0, 1)),
        throwsA(isA<ScheduleTickException>()),
      );
    });

    test('runOnce uses Stem Beat for a long-lived scheduler pass', () async {
      final queue = InMemoryJobQueue();
      final jobs = RoutedJobs(queue: queue);
      var calls = 0;
      var now = DateTime.utc(2026);
      final scheduler = RoutedScheduler(
        dispatcher: jobs,
        clock: () => now,
        schedules: [
          ScheduleDefinition(
            name: 'heartbeat',
            frequency: ScheduleFrequency.every(const Duration(minutes: 1)),
            action: (_) async => calls += 1,
          ),
        ],
      );

      await scheduler.runOnce();
      expect(calls, 1);

      // The Stem-backed store advances the recurring entry after the first
      // publication, so the same instant cannot run it twice.
      await scheduler.runOnce();
      expect(calls, 1);

      now = now.add(const Duration(minutes: 1));
      await scheduler.runOnce();
      expect(calls, 2);

      await scheduler.close();
      await jobs.close();
    });

    test(
      'Stem Beat retries a failed occurrence instead of advancing it',
      () async {
        final jobs = RoutedJobs(queue: InMemoryJobQueue());
        var attempts = 0;
        final now = DateTime.utc(2026);
        final scheduler = RoutedScheduler(
          dispatcher: jobs,
          clock: () => now,
          schedules: [
            ScheduleDefinition(
              name: 'transient',
              frequency: ScheduleFrequency.every(const Duration(minutes: 1)),
              action: (_) async {
                attempts += 1;
                if (attempts == 1) throw StateError('temporary');
              },
            ),
          ],
        );

        await scheduler.runOnce();
        expect(attempts, 1);

        // The failed occurrence remains due at the same instant and is retried.
        await scheduler.runOnce();
        expect(attempts, 2);

        // A successful retry advances to the next interval.
        await scheduler.runOnce();
        expect(attempts, 2);

        await scheduler.close();
        await jobs.close();
      },
    );

    test('Stem Beat retries when durable completion fails', () async {
      final jobs = RoutedJobs(queue: InMemoryJobQueue());
      final store = _FailingCompletionStore();
      var attempts = 0;
      final now = DateTime.utc(2026);
      final scheduler = RoutedScheduler(
        dispatcher: jobs,
        store: store,
        clock: () => now,
        schedules: [
          ScheduleDefinition(
            name: 'completion-transient',
            frequency: ScheduleFrequency.every(const Duration(minutes: 1)),
            action: (_) async => attempts += 1,
          ),
        ],
      );

      await scheduler.runOnce();
      expect(attempts, 1);
      await scheduler.runOnce();
      expect(attempts, 2);

      await scheduler.close();
      await jobs.close();
    });

    test('work keeps a normal process alive until stopped', () async {
      final jobs = RoutedJobs(queue: InMemoryJobQueue());
      final scheduler = RoutedScheduler(
        dispatcher: jobs,
        tickInterval: const Duration(milliseconds: 10),
      );
      final work = scheduler.work();
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.isRunning, isTrue);

      await scheduler.stop();
      await work;
      expect(scheduler.isRunning, isFalse);
      await jobs.close();
    });

    test('provider wires the scheduler after the jobs dispatcher', () async {
      final container = Container();
      final jobsProvider = RoutedJobsProvider(
        JobsConfig(queue: InMemoryJobQueue()),
      )..register(container);

      final schedulerProvider = RoutedSchedulerProvider(SchedulerConfig())
        ..register(container);
      await schedulerProvider.boot(container);

      expect(
        container.get<RoutedScheduler>().dispatcher,
        same(container.get<JobDispatcher>()),
      );
      await jobsProvider.cleanup(container);
    });

    test('request cleanup does not stop the root scheduler', () async {
      final engine = await Engine.create(
        providers: [RoutedJobsProvider(), RoutedSchedulerProvider()],
      );
      addTearDown(engine.close);
      final scheduler = engine.container.get<RoutedScheduler>();
      await scheduler.start();

      await engine.cleanupRequestContainer(engine.container.createChild());
      expect(scheduler.isRunning, isTrue);

      await engine.close();
      expect(scheduler.isRunning, isFalse);
    });

    test('request cleanup does not close shared jobs', () async {
      final queue = InMemoryJobQueue();
      final job = JobDefinition<String, String>(
        name: 'request-safe',
        encode: (value) => {'value': value},
        decode: (payload) => payload['value']! as String,
        handle: (_, value) async => value,
      );
      final engine = await Engine.create(
        providers: [
          RoutedJobsProvider(
            JobsConfig(queue: queue, definitions: [job]),
          ),
        ],
      );
      addTearDown(engine.close);

      await engine.cleanupRequestContainer(engine.container.createChild());
      final receipt = await engine.container.get<JobDispatcher>().dispatch(
        job,
        'still-open',
      );

      expect(receipt.name, job.name);
      expect(queue.messages, hasLength(1));
    });

    test('provider registers its schedule command on the engine', () async {
      final engine = await Engine.create(
        providers: [RoutedJobsProvider(), RoutedSchedulerProvider()],
      );
      addTearDown(engine.close);

      final registry = engine.container.get<CliCommandRegistry>();
      final registration = registry.registrations.singleWhere(
        (entry) => entry.id == 'routed.jobs.schedule',
      );
      final command = registration.factory(engine.container);

      expect(command, isA<RoutedJobsScheduleCommand>());
      expect(
        (command as RoutedJobsScheduleCommand).scheduler,
        same(engine.container.get<RoutedScheduler>()),
      );

      final workRegistration = registry.registrations.singleWhere(
        (entry) => entry.id == 'routed.jobs.schedule-work',
      );
      expect(
        workRegistration.factory(engine.container),
        isA<RoutedJobsScheduleWorkCommand>(),
      );
    });

    test('withScheduler contributes the same schedule command', () {
      final scheduler = RoutedScheduler(
        dispatcher: RoutedJobs(queue: InMemoryJobQueue()),
      );
      final engine = Engine(options: [withScheduler(scheduler)]);
      addTearDown(engine.close);

      final registration = engine.cliCommandRegistry.registrations.singleWhere(
        (entry) => entry.id == 'routed.jobs.schedule',
      );
      expect(
        (registration.factory(engine.container) as RoutedJobsScheduleCommand)
            .scheduler,
        same(scheduler),
      );
    });
  });
}

final class _FailingCompletionStore implements ScheduleStore {
  final InMemoryScheduleStore delegate = InMemoryScheduleStore();
  bool failNextCompletion = true;

  @override
  Future<ScheduleClaim?> claim(
    ScheduleOccurrence occurrence, {
    required Duration lease,
  }) => delegate.claim(occurrence, lease: lease);

  @override
  Future<void> complete(ScheduleClaim claim) async {
    if (failNextCompletion) {
      failNextCompletion = false;
      throw StateError('temporary completion failure');
    }
    await delegate.complete(claim);
  }

  @override
  Future<void> release(ScheduleClaim claim) => delegate.release(claim);
}
