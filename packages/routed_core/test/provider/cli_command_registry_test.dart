import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  test('engine exposes provider CLI command registrations', () {
    final engine = Engine(providers: [_CommandProvider()]);

    final registry = engine.container.get<CliCommandRegistry>();
    expect(registry.registrations.map((entry) => entry.id), contains('test'));
    expect(registry.registrations.single.factory(engine.container), 'command');
  });
}

final class _CommandProvider extends ServiceProvider {
  @override
  void register(Container container) {}

  @override
  void registerCliCommands(CliCommandRegistry registry) {
    registry.register(
      'test',
      factory: (_) => 'command',
    );
  }
}
