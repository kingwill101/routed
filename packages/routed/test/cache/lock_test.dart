import 'package:routed/src/cache/array_lock.dart';
import 'package:routed/src/cache/array_store.dart';
import 'package:routed/src/contracts/cache/lock.dart';
import 'package:test/test.dart';

void main() {
  group('Lock Tests', () {
    late Lock lock;
    late ArrayStore store;

    setUp(() {
      store = ArrayStore();
      lock = ArrayLock(store, 'test_lock', 60);
    });

    test('acquire and release lock', () async {
      final acquired = await lock.acquire();
      expect(acquired, isTrue);

      final released = await lock.release();
      expect(released, isTrue);
    });

    test('block lock', () async {
      final result = await lock.block(2, () async {
        return 'locked';
      });
      expect(result, 'locked');
    });

    test('force release lock', () async {
      await lock.acquire();
      lock.forceRelease();
      final owner = await lock.getCurrentOwner();
      expect(owner, isNull);
      });
  });
}
