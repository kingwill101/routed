import 'package:artisanal/args.dart';
import 'package:routed/console.dart';
import 'package:routed/routed.dart';
import 'package:test/test.dart';

class _TestCommand extends Command<void> {
  _TestCommand(this._name);

  final String _name;

  @override
  String get name => _name;

  @override
  String get description => 'Test command $_name.';
}

class _CommandProvider extends ServiceProvider {
  _CommandProvider(this.id);

  final String id;

  @override
  void register(Container container) {
    ProviderCommandRegistry.instance.register(
      'provider.$id',
      factory: () => _TestCommand('provider:$id'),
    );
    ProviderArtisanalCommandRegistry.instance.register(
      'artisan.$id',
      factory: () => _TestCommand('artisan:$id'),
    );
  }
}

void main() {
  test('provider-registered commands are added to runners', () {
    const id = 'cli-flow';
    addTearDown(() {
      ProviderCommandRegistry.instance.unregister('provider.$id');
      ProviderArtisanalCommandRegistry.instance.unregister('artisan.$id');
    });

    Engine(providers: [_CommandProvider(id)]);

    final runner = CommandRunner<void>('app', 'desc');

    registerProviderCommands(
      runner,
      ProviderCommandRegistry.instance.registrations,
      runner.usage,
    );
    registerProviderArtisanalCommands(
      runner,
      ProviderArtisanalCommandRegistry.instance.registrations,
      runner.usage,
    );

    expect(runner.commands.containsKey('provider:$id'), isTrue);
    expect(runner.commands.containsKey('artisan:$id'), isTrue);
  });
}
