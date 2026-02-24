import 'package:server_data/server_data.dart';
import 'package:server_contracts/server_contracts.dart' show Lock;
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
