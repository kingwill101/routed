import 'package:routed_core/routed_core.dart';

import 'deploy.dart';

/// Registers CLI commands owned by the routed_node runtime package.
final class RoutedNodeCliProvider extends ServiceProvider {
  /// Creates the routed_node CLI provider.
  RoutedNodeCliProvider();

  @override
  void register(Container container) {}

  @override
  void registerCliCommands(CliCommandRegistry registry) {
    registry.register(
      'routed_node.deploy',
      factory: (_) => RoutedNodeDeployCommand(),
      description: 'Build and deploy a Routed application to a supported host.',
    );
  }
}
