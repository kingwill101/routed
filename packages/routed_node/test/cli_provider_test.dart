import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cli.dart';
import 'package:routed_node/cli_provider.dart';
import 'package:test/test.dart';

void main() {
  test(
    'routed_node contributes its deployment command through the provider',
    () {
      final registry = CliCommandRegistry();
      RoutedNodeCliProvider().registerCliCommands(registry);

      expect(registry.registrations, hasLength(1));
      final registration = registry.registrations.single;
      expect(registration.id, 'routed_node.deploy');
      final command = registration.factory(Container());
      expect(command, isA<RoutedNodeDeployCommand>());
      final deploy = command as RoutedNodeDeployCommand;
      expect(deploy.name, 'deploy');
      expect(
        deploy.argParser.options.keys,
        containsAll(<String>[
          'target',
          'cloudflare-factory',
          'var',
          'd1',
          'r2',
          'queue',
          'service',
          'durable-object',
          'container',
          'workflow',
          'secrets-store',
        ]),
      );
    },
  );

  test('VM CLI provider discovery returns routed_node provider', () {
    expect(routedNodeCliProviders(), hasLength(1));
    expect(routedNodeCliProviders().single, isA<RoutedNodeCliProvider>());
  });
}
