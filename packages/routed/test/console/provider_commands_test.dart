import 'package:artisanal/args.dart';
import 'package:routed/console.dart';
import 'package:test/test.dart';

class _DemoCommand extends Command<void> {
  @override
  String get name => 'demo:run';

  @override
  String get description => 'Runs a demo command.';
}

class _ConflictCommand extends Command<void> {
  @override
  String get name => 'dev';

  @override
  String get description => 'Conflicts with built-in dev.';
}

class _NamedCommand extends Command<void> {
  _NamedCommand(this._name, {List<String> aliases = const []})
    : _aliases = List<String>.from(aliases);

  final String _name;
  final List<String> _aliases;

  @override
  String get name => _name;

  @override
  List<String> get aliases => _aliases;

  @override
  String get description => 'Named command $_name.';
}

class _ArtisanalCommand extends Command<void> {
  @override
  String get name => 'artisan:run';

  @override
  String get description => 'Runs an artisanal command.';
}

void main() {
  test('registerProviderCommands adds provider commands to runner', () {
    final registry = ProviderCommandRegistry.instance;
    registry.register('demo', factory: () => _DemoCommand());
    addTearDown(() => registry.unregister('demo'));

    final runner = CommandRunner<void>('routed', 'desc');

    registerProviderCommands(runner, registry.registrations, runner.usage);

    expect(runner.commands.containsKey('demo:run'), isTrue);
  });

  test('registerProviderCommands detects name conflicts', () {
    final registry = ProviderCommandRegistry.instance;
    registry.register('conflict', factory: () => _ConflictCommand());
    addTearDown(() => registry.unregister('conflict'));

    final runner = CommandRunner<void>('routed', 'desc');
    runner.addCommand(_ConflictCommand());

    expect(
      () => registerProviderCommands(
        runner,
        registry.registrations,
        runner.usage,
      ),
      throwsA(isA<UsageException>()),
    );
  });

  test('registerProviderCommands detects alias conflicts', () {
    final registry = ProviderCommandRegistry.instance;
    registry.register('alias-conflict', factory: () => _NamedCommand('ship'));
    addTearDown(() => registry.unregister('alias-conflict'));

    final runner = CommandRunner<void>('routed', 'desc')
      ..addCommand(_NamedCommand('existing:cmd', aliases: ['ship']));

    expect(
      () => registerProviderCommands(
        runner,
        registry.registrations,
        runner.usage,
      ),
      throwsA(isA<UsageException>()),
    );
  });

  test('registerProviderCommands detects alias collisions from providers', () {
    final registry = ProviderCommandRegistry.instance;
    registry.register(
      'alias-provider',
      factory: () => _NamedCommand('maintenance:run', aliases: ['deploy']),
    );
    addTearDown(() => registry.unregister('alias-provider'));

    final runner = CommandRunner<void>('routed', 'desc')
      ..addCommand(_NamedCommand('deploy'));

    expect(
      () => registerProviderCommands(
        runner,
        registry.registrations,
        runner.usage,
      ),
      throwsA(isA<UsageException>()),
    );
  });

  test('registerProviderCommands throws when factory fails', () {
    final registry = ProviderCommandRegistry.instance;
    registry.register('factory-fails', factory: () => throw StateError('boom'));
    addTearDown(() => registry.unregister('factory-fails'));

    final runner = CommandRunner<void>('routed', 'desc');

    expect(
      () => registerProviderCommands(
        runner,
        registry.registrations,
        runner.usage,
      ),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('Failed to load provider command'),
        ),
      ),
    );
  });

  test('registerProviderCommands detects provider-to-provider conflicts', () {
    final registry = ProviderCommandRegistry.instance;
    registry.register(
      'first',
      factory: () => _NamedCommand('alpha', aliases: ['shared']),
    );
    registry.register('second', factory: () => _NamedCommand('shared'));
    addTearDown(() {
      registry.unregister('first');
      registry.unregister('second');
    });

    final runner = CommandRunner<void>('routed', 'desc');

    expect(
      () => registerProviderCommands(
        runner,
        registry.registrations,
        runner.usage,
      ),
      throwsA(isA<UsageException>()),
    );
  });

  test('provider registry honors overrideExisting flag', () {
    final registry = ProviderCommandRegistry.instance;
    registry.register('override', factory: () => _DemoCommand());
    addTearDown(() => registry.unregister('override'));

    final didOverride = registry.register(
      'override',
      factory: () => _ConflictCommand(),
      overrideExisting: false,
    );

    expect(didOverride, isFalse);
    final registration = registry.registrations.firstWhere(
      (entry) => entry.id == 'override',
    );
    expect(registration.factory(), isA<_DemoCommand>());
  });

  test('artisanal command registry tracks registrations', () {
    final registry = ProviderArtisanalCommandRegistry.instance;
    registry.register('artisan', factory: () => _ArtisanalCommand());
    addTearDown(() => registry.unregister('artisan'));

    final registrations = registry.registrations.toList();
    expect(registrations, hasLength(1));
    expect(registrations.first.id, equals('artisan'));
  });

  test(
    'registerProviderArtisanalCommands adds provider commands to runner',
    () {
      final registry = ProviderArtisanalCommandRegistry.instance;
      registry.register('artisan', factory: () => _ArtisanalCommand());
      addTearDown(() => registry.unregister('artisan'));

      final runner = CommandRunner<void>('routed', 'desc');

      registerProviderArtisanalCommands(
        runner,
        registry.registrations,
        runner.usage,
      );

      expect(runner.commands.containsKey('artisan:run'), isTrue);
    },
  );
}
