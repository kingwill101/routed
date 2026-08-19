import 'dart:async';

import 'package:routed/routed.dart';

import 'platform_config.dart';
import 'platform_runtime.dart';

/// Registers the platform runtime and declares its typed configuration.
final class PlatformServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<PlatformConfig> {
  PlatformServiceProvider(this.configuration);

  Container? _rootContainer;

  @override
  final PlatformConfig configuration;

  @override
  void register(Container container) {
    _rootContainer = container;
    container.instance<PlatformConfig>(configuration);
    container.singleton<PlatformRuntime>((container) async {
      return PlatformRuntime(container.get<PlatformConfig>());
    });
  }

  @override
  Future<void> boot(Container container) async {
    final runtime = await container.make<PlatformRuntime>();
    await runtime.start();
  }

  @override
  Future<void> cleanup(Container container) async {
    // Routed invokes provider cleanup for request-scoped child containers as
    // well as the application container. The worker belongs to the process,
    // so only close it during application shutdown.
    if (identical(container, _rootContainer) &&
        container.has<PlatformRuntime>()) {
      final runtime = await container.make<PlatformRuntime>();
      await runtime.close();
    }
  }
}
