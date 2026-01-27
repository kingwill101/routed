import 'dart:async';

import 'package:routed/routed.dart';
import 'package:test/test.dart';

class _TestService {
  _TestService(this.value);

  final String value;
}

void main() {
  test('when runs immediately for available types', () async {
    final container = Container();
    final service = _TestService('ready');
    container.instance<_TestService>(service);

    final completer = Completer<void>();
    container.when<_TestService>((instance, _) {
      expect(instance, same(service));
      completer.complete();
    });

    await completer.future;
  });

  test('when runs after type registration', () async {
    final container = Container();
    final completer = Completer<_TestService>();

    container.when<_TestService>((instance, _) {
      completer.complete(instance);
    });

    container.instance<_TestService>(_TestService('late'));

    final resolved = await completer.future;
    expect(resolved.value, equals('late'));
  });

  test('resolved reflects instance availability', () async {
    final container = Container();
    container.singleton<_TestService>((_) async => _TestService('value'));

    expect(container.resolved<_TestService>(), isFalse);

    await container.make<_TestService>();
    expect(container.resolved<_TestService>(), isTrue);

    final second = Container();
    second.instance<_TestService>(_TestService('instance'));
    expect(second.resolved<_TestService>(), isTrue);
  });
}
