import 'package:routed/routed.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

class StubService {}

class StubProvider extends ServiceProvider {
  bool registered = false;

  @override
  void register(Container container) {
    registered = true;
    container.singleton<StubService>((_) async => StubService());
  }
}

void main() {
  test('Engine constructor registers additional providers', () async {
    final provider = StubProvider();
    final engine = testEngine(providers: [provider]);
    await engine.initialize();

    expect(provider.registered, isTrue);
    expect(await engine.make<StubService>(), isA<StubService>());
  });

  test('Engine.create accepts providers (bare mode)', () async {
    final provider = StubProvider();
    final engine = await Engine.create(providers: [provider]);

    expect(await engine.make<StubService>(), isA<StubService>());
  });
}
