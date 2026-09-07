part of '../routed_jobs.dart';

/// Typed configuration for [RoutedJobsProvider].
final class JobsConfig implements ValidatableConfiguration {
  /// Creates a jobs configuration.
  JobsConfig({
    JobQueue? queue,
    Iterable<JobDefinitionBase> definitions = const [],
  }) : queue = queue ?? InMemoryJobQueue(),
       definitions = List<JobDefinitionBase>.unmodifiable(definitions);

  /// Queue transport used to publish messages.
  final JobQueue queue;

  /// Manually registered application job definitions.
  final List<JobDefinitionBase> definitions;

  /// Creates the jobs facade represented by this configuration.
  RoutedJobs create() => RoutedJobs(queue: queue, definitions: definitions);

  /// Validates job names and queue defaults before provider registration.
  @override
  void validate(ConfigValidationContext context) {
    final names = <String>{};
    for (var index = 0; index < definitions.length; index += 1) {
      final definition = definitions[index];
      try {
        definition.options.validate(definition.name);
      } on Object catch (error) {
        context.error(
          'definitions[$index]',
          error.toString(),
        );
      }
      if (!names.add(definition.name)) {
        context.error(
          'definitions[$index].name',
          'job names must be unique',
        );
      }
    }
  }
}

/// Registers a configured [RoutedJobs] facade in the application container.
final class RoutedJobsProvider extends ServiceProvider
    with ProvidesTypedConfiguration<JobsConfig> {
  /// Creates a provider using [configuration].
  RoutedJobsProvider([JobsConfig? configuration])
    : configuration = configuration ?? JobsConfig();

  /// Configuration used to construct the jobs facade.
  @override
  final JobsConfig configuration;

  late RoutedJobs _jobs;

  @override
  void register(Container container) {
    _jobs = configuration.create();
    container
      ..instance<RoutedJobs>(_jobs)
      ..instance<JobDispatcher>(_jobs)
      ..instance<JobConsumer>(_jobs);
  }

  @override
  Future<void> cleanup(Container container) => _jobs.close();
}

/// Typed configuration for [RoutedSchedulerProvider].
final class SchedulerConfig implements ValidatableConfiguration {
  /// Creates a scheduler configuration.
  SchedulerConfig({
    Iterable<ScheduleDefinition> schedules = const [],
    ScheduleStore? store,
    this.lookback = const Duration(minutes: 1),
    this.claimLease = const Duration(minutes: 5),
    this.tickInterval = const Duration(seconds: 1),
  }) : schedules = List<ScheduleDefinition>.unmodifiable(schedules),
       store = store ?? InMemoryScheduleStore();

  /// Schedules evaluated by each scheduler tick.
  final List<ScheduleDefinition> schedules;

  /// Durable occurrence ledger.
  final ScheduleStore store;

  /// Window in which missed occurrences are considered.
  final Duration lookback;

  /// Lease held while a scheduled action is dispatching.
  final Duration claimLease;

  /// Polling interval for the long-running `schedule:work` command.
  final Duration tickInterval;

  /// Creates a scheduler using [dispatcher].
  RoutedScheduler create(JobDispatcher dispatcher) => RoutedScheduler(
    dispatcher: dispatcher,
    schedules: schedules,
    store: store,
    lookback: lookback,
    claimLease: claimLease,
    tickInterval: tickInterval,
  );

  @override
  void validate(ConfigValidationContext context) {
    if (lookback < Duration.zero) {
      context.error('lookback', 'Scheduler lookback must not be negative.');
    }
    if (claimLease <= Duration.zero) {
      context.error('claimLease', 'Scheduler claim lease must be positive.');
    }
    if (tickInterval <= Duration.zero) {
      context.error(
        'tickInterval',
        'Scheduler tick interval must be positive.',
      );
    }
    final names = <String>{};
    for (var index = 0; index < schedules.length; index += 1) {
      final schedule = schedules[index];
      if (!names.add(schedule.name)) {
        context.error(
          'schedules[$index].name',
          'schedule names must be unique',
        );
      }
    }
  }
}

/// Registers a configured [RoutedScheduler] after jobs are available.
final class RoutedSchedulerProvider extends ServiceProvider
    with ProvidesDependencies, ProvidesTypedConfiguration<SchedulerConfig> {
  /// Creates a scheduler provider using [configuration].
  RoutedSchedulerProvider([SchedulerConfig? configuration])
    : configuration = configuration ?? SchedulerConfig();

  /// Configuration used to construct the scheduler.
  @override
  final SchedulerConfig configuration;

  RoutedScheduler? _scheduler;
  Container? _rootContainer;

  /// Schedulers require the jobs dispatcher registered by
  /// [RoutedJobsProvider] or [withJobs].
  @override
  List<Type> get dependencies => const <Type>[JobDispatcher];

  @override
  void register(Container container) {}

  @override
  void registerCliCommands(CliCommandRegistry registry) {
    _registerSchedulerCommand(registry);
  }

  @override
  Future<void> boot(Container container) async {
    _rootContainer = container;
    _scheduler = configuration.create(container.get<JobDispatcher>());
    container.instance<RoutedScheduler>(_scheduler!);
  }

  @override
  Future<void> cleanup(Container container) async {
    // Engine request teardown passes a child container through every
    // provider. The scheduler belongs to the root engine and must only stop
    // when that root container is being shut down.
    if (!identical(container, _rootContainer)) return;
    await _scheduler?.close();
    _scheduler = null;
  }
}

/// Registers the jobs provider factory in the shared provider registry.
void registerRoutedJobsProviders() {
  ProviderRegistry.instance.register(
    'routed.jobs',
    factory: RoutedJobsProvider.new,
    description: 'Routed jobs and queue dispatch facade.',
  );
  ProviderRegistry.instance.register(
    'routed.scheduler',
    factory: RoutedSchedulerProvider.new,
    description: 'Routed schedule tick and occurrence ledger.',
  );
}

/// Adds [jobs] to an engine container as a dispatcher and consumer.
EngineOpt withJobs(RoutedJobs jobs) {
  return (Engine engine) {
    engine.container
      ..instance<RoutedJobs>(jobs)
      ..instance<JobDispatcher>(jobs)
      ..instance<JobConsumer>(jobs);
  };
}

/// Adds [scheduler] to an engine container.
EngineOpt withScheduler(RoutedScheduler scheduler) {
  return (Engine engine) {
    engine.container.instance<RoutedScheduler>(scheduler);
    _registerSchedulerCommand(engine.cliCommandRegistry);
  };
}

void _registerSchedulerCommand(CliCommandRegistry registry) {
  registry
    ..register(
      'routed.jobs.schedule',
      description: 'Evaluate due Routed schedules once.',
      factory: (container) =>
          RoutedJobsScheduleCommand(container.get<RoutedScheduler>()),
    )
    ..register(
      'routed.jobs.schedule-work',
      description: 'Run application schedules continuously.',
      factory: (container) =>
          RoutedJobsScheduleWorkCommand(container.get<RoutedScheduler>()),
    );
}

/// Access to the configured jobs dispatcher from a request context.
extension JobsEngineContext on EngineContext {
  /// Returns the configured jobs dispatcher.
  JobDispatcher get jobs {
    if (!container.has<JobDispatcher>()) {
      throw StateError('Routed jobs are not configured');
    }
    return container.get<JobDispatcher>();
  }

  /// Whether this context has a configured jobs dispatcher.
  bool get hasJobs => container.has<JobDispatcher>();

  /// Returns the configured scheduler.
  RoutedScheduler get scheduler {
    if (!container.has<RoutedScheduler>()) {
      throw StateError('Routed scheduler is not configured');
    }
    return container.get<RoutedScheduler>();
  }

  /// Whether this context has a configured scheduler.
  bool get hasScheduler => container.has<RoutedScheduler>();
}
