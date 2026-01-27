/// Tests for the Inertia service provider.
library;

import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';
import 'package:routed_inertia/routed_inertia.dart';
import 'package:test/test.dart';

void main() {
  test('InertiaServiceProvider registers config and middleware', () async {
    final engine = Engine(
      providers: [
        CoreServiceProvider(),
        RoutingServiceProvider(),
        InertiaServiceProvider(),
      ],
    );

    await engine.initialize();
    final container = engine.container;

    expect(container.has<InertiaConfig>(), isTrue);
    expect(container.has<InertiaSsrSettings>(), isTrue);

    final registry = container.get<MiddlewareRegistry>();
    expect(registry.has('routed.inertia.middleware'), isTrue);

    await engine.close();
  });
}
