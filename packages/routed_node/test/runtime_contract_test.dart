import 'package:routed_core/routed_core.dart';
import 'package:routed_node/routed_node.dart';
import 'package:test/test.dart';

void main() {
  test('runtime capabilities distinguish listener and fetch hosts', () {
    expect(nodeCapabilities.entryModel, RoutedNodeEntryModel.listener);
    expect(cloudflareCapabilities.entryModel, RoutedNodeEntryModel.fetchExport);
    expect(nodeCapabilities.streaming, isTrue);
    expect(cloudflareCapabilities.bufferedResponses, isTrue);
    expect(cloudflareCapabilities.fileSystem, isFalse);
    expect(cloudflareCapabilities.webSocket, isFalse);
    expect(bunCapabilities.webSocket, isFalse);
    expect(denoCapabilities.webSocket, isFalse);
    expect(vercelCapabilities.webSocket, isFalse);
    expect(netlifyCapabilities.webSocket, isFalse);
  });

  test('host lifecycle events use EventManager', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    await engine.initialize();
    addTearDown(engine.close);

    final manager = engine.container.get<EventManager>();
    final event = RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.ready,
      info: const RoutedNodeRuntimeInfo(
        runtime: RoutedNodeRuntime.node,
        capabilities: nodeCapabilities,
      ),
    );
    final future = manager.on<RoutedNodeLifecycleEvent>().first;

    publishRoutedNodeLifecycle(engine, event);

    expect(await future, same(event));
  });
}
