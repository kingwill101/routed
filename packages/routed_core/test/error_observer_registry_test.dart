import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  group('ErrorObserverRegistry', () {
    test('notifies observers and swallows observer exceptions', () async {
      final registry = ErrorObserverRegistry<String>();
      final called = <String>[];

      registry.addObserver(_RecordingObserver(called));
      registry.addObserver(_ThrowingObserver());
      registry.addObserver(_RecordingObserver(called));

      await registry.notify('ctx', StateError('boom'), StackTrace.current);

      expect(called, equals(['ctx', 'ctx']));
      expect(registry.hasObservers, isTrue);
    });
  });
}

class _RecordingObserver extends ErrorObserver<String> {
  _RecordingObserver(this._called);

  final List<String> _called;

  @override
  void onError(String context, Object error, StackTrace stackTrace) {
    _called.add(context);
  }
}

class _ThrowingObserver extends ErrorObserver<String> {
  @override
  void onError(String context, Object error, StackTrace stackTrace) {
    throw StateError('observer failed');
  }
}
