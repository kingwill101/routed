import 'package:routed/routed.dart';
import 'package:test/test.dart';

class _DependencyService {}

class _DependentProvider extends ServiceProvider with ProvidesDependencies {
  int bootCalls = 0;

  @override
  List<Type> get dependencies => [_DependencyService];

  @override
  void register(Container container) {}

  @override
  Future<void> boot(Container container) async {
    bootCalls++;
  }
}

class _DeltaReady {}

class _BetaReady {}

class _GammaReady {}

class _BetaProvider extends ServiceProvider with ProvidesDependencies {
  _BetaProvider(this.order);

  final List<String> order;
  bool deltaReadyAtBoot = false;

  @override
  List<Type> get dependencies => [_DeltaReady];

  @override
  void register(Container container) {}

  @override
  Future<void> boot(Container container) async {
    deltaReadyAtBoot = container.hasType(_DeltaReady);
    container.instance<_BetaReady>(_BetaReady());
    order.add('beta');
  }
}

class _GammaProvider extends ServiceProvider {
  _GammaProvider(this.order);

  final List<String> order;

  @override
  void register(Container container) {}

  @override
  Future<void> boot(Container container) async {
    container.instance<_GammaReady>(_GammaReady());
    order.add('gamma');
  }
}

class _AlphaProvider extends ServiceProvider with ProvidesDependencies {
  _AlphaProvider(this.order);

  final List<String> order;
  bool dependenciesReadyAtBoot = false;

  @override
  List<Type> get dependencies => [_BetaReady, _GammaReady];

  @override
  void register(Container container) {}

  @override
  Future<void> boot(Container container) async {
    dependenciesReadyAtBoot =
        container.hasType(_BetaReady) && container.hasType(_GammaReady);
    order.add('alpha');
  }
}

void main() {
  test('providers boot when dependencies are already registered', () async {
    final provider = _DependentProvider();
    final engine = Engine(providers: [provider]);

    engine.container.instance<_DependencyService>(_DependencyService());

    await engine.bootProviders();

    expect(provider.bootCalls, equals(1));
  });

  test('providers boot after dependencies become available', () async {
    final provider = _DependentProvider();
    final engine = Engine(providers: [provider]);

    await engine.bootProviders();
    expect(provider.bootCalls, equals(0));

    engine.container.instance<_DependencyService>(_DependencyService());
    await Future<void>.delayed(Duration.zero);

    expect(provider.bootCalls, equals(1));
  });

  test('boots providers with complex dependency graph', () async {
    final order = <String>[];
    final alpha = _AlphaProvider(order);
    final beta = _BetaProvider(order);
    final gamma = _GammaProvider(order);
    final engine = Engine(providers: [alpha, beta, gamma]);

    await engine.bootProviders();
    expect(order.contains('alpha'), isFalse);
    expect(order.contains('beta'), isFalse);
    expect(alpha.dependenciesReadyAtBoot, isFalse);
    expect(beta.deltaReadyAtBoot, isFalse);

    engine.container.instance<_DeltaReady>(_DeltaReady());
    await Future<void>.delayed(Duration.zero);

    expect(order.contains('beta'), isTrue);
    expect(order.contains('alpha'), isTrue);
    expect(alpha.dependenciesReadyAtBoot, isTrue);
    expect(beta.deltaReadyAtBoot, isTrue);
  });
}
