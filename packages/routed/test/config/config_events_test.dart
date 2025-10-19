import 'dart:async';

import 'package:routed/src/config/config.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/engine/events/config.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

void main() {
  engineTest('ConfigLoadedEvent fires on engine initialize', (
    engine,
    client,
  ) async {
    final eventManager = await engine.make<EventManager>();
    final events = <ConfigLoadedEvent>[];
    final sub = eventManager.on<ConfigLoadedEvent>().listen(events.add);

    await engine.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final event = events.first;
    expect(event.config.get('app.name'), equals('Test App'));

    await sub.cancel();
  });

  engineTest('replaceConfig publishes ConfigReloadedEvent and updates scope', (
    engine,
    client,
  ) async {
    final eventManager = await engine.make<EventManager>();
    final reloads = <ConfigReloadedEvent>[];
    final sub = eventManager.on<ConfigReloadedEvent>().listen(reloads.add);

    await engine.initialize();

    final override = ConfigImpl({
      'app.name': 'Reloaded App',
      'app.env': 'testing',
    });

    await engine.replaceConfig(override, metadata: {'source': 'test'});
    await Future<void>.delayed(Duration.zero);

    expect(reloads, hasLength(1));
    final event = reloads.first;
    expect(event.config, same(override));
    expect(event.metadata['source'], equals('test'));
    expect(Config.current, same(override));

    await sub.cancel();
  });
}
