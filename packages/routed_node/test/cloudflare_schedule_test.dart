import 'package:routed_node/cloudflare.dart';
import 'package:routed_jobs/routed_jobs.dart';
import 'package:server_contracts/server_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'CloudflareScheduleStore uses owner-aware claims and completion records',
    () async {
      final backend = _FakeStore();
      final locks = _FakeLockProvider();
      final store = CloudflareScheduleStore(
        store: backend,
        locks: locks,
        keyPrefix: 'test:schedule:',
      );
      final occurrence = ScheduleOccurrence(
        scheduleName: 'reports.daily',
        scheduledAt: DateTime.utc(2026, 1, 1, 9),
      );

      final claim = await store.claim(
        occurrence,
        lease: const Duration(minutes: 5),
      );
      expect(claim, isNotNull);
      expect(
        await store.claim(occurrence, lease: const Duration(minutes: 5)),
        isNull,
      );
      await store.complete(claim!);
      expect(
        await store.claim(occurrence, lease: const Duration(minutes: 5)),
        isNull,
      );

      final otherOccurrence = ScheduleOccurrence(
        scheduleName: 'reports.other',
        scheduledAt: occurrence.scheduledAt,
      );
      final otherClaim = await store.claim(
        otherOccurrence,
        lease: const Duration(minutes: 5),
      );
      await store.release(otherClaim!);
      expect(
        await store.claim(otherOccurrence, lease: const Duration(minutes: 5)),
        isNotNull,
      );
      expect(
        backend.values.keys,
        contains('test:schedule:completed:${occurrence.key}'),
      );
    },
  );

  test('a stale claim cannot record completion after lease takeover', () async {
    final backend = _FakeStore();
    final locks = _FakeLockProvider();
    final store = CloudflareScheduleStore(
      store: backend,
      locks: locks,
      keyPrefix: 'test:schedule:',
    );
    final occurrence = ScheduleOccurrence(
      scheduleName: 'reports.daily',
      scheduledAt: DateTime.utc(2026, 1, 1, 9),
    );

    final staleClaim = await store.claim(
      occurrence,
      lease: const Duration(minutes: 5),
    );
    expect(staleClaim, isNotNull);
    locks.forceRelease(occurrence);
    final currentClaim = await store.claim(
      occurrence,
      lease: const Duration(minutes: 5),
    );
    expect(currentClaim, isNotNull);

    await expectLater(store.complete(staleClaim!), throwsStateError);
    expect(
      backend.values,
      isNot(
        containsPair('test:schedule:completed:${occurrence.key}', 'completed'),
      ),
    );

    await store.complete(currentClaim!);
    expect(
      backend.values,
      containsPair('test:schedule:completed:${occurrence.key}', 'completed'),
    );
  });
}

final class _FakeLockProvider implements LockProvider {
  final Map<String, String> owners = <String, String>{};
  int sequence = 0;

  void forceRelease(ScheduleOccurrence occurrence) {
    owners.remove('test:schedule:lock:${occurrence.key}');
  }

  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async {
    return _FakeLock(this, name, owner ?? 'owner-${sequence++}');
  }

  @override
  Future<Lock> restoreLock(String name, String owner) async {
    return _FakeLock(this, name, owner);
  }
}

final class _FakeLock implements Lock {
  _FakeLock(this.provider, this.name, this._owner);

  final _FakeLockProvider provider;
  final String name;
  final String _owner;

  @override
  Future<dynamic> get([Function? callback]) async {
    if (!await acquire()) return false;
    if (callback == null) return true;
    try {
      return await Function.apply(callback, const []);
    } finally {
      await release();
    }
  }

  @override
  Future<bool> acquire() async {
    if (provider.owners.containsKey(name)) return false;
    provider.owners[name] = _owner;
    return true;
  }

  @override
  Future<dynamic> block(int seconds, [Function? callback]) => get(callback);

  @override
  Future<bool> release() async {
    if (provider.owners[name] != _owner) return false;
    provider.owners.remove(name);
    return true;
  }

  @override
  String owner() => _owner;

  @override
  Future<String?> getCurrentOwner() async => provider.owners[name];

  @override
  Future<bool> isOwnedByCurrentProcess() async =>
      provider.owners[name] == _owner;

  @override
  void forceRelease() {
    provider.owners.remove(name);
  }
}

final class _FakeStore implements Store {
  final Map<String, dynamic> values = <String, dynamic>{};

  @override
  Future<dynamic> get(String key) async => values[key];

  @override
  Future<Map<String, dynamic>> many(List<String> keys) async => {
    for (final key in keys)
      if (values.containsKey(key)) key: values[key],
  };

  @override
  Future<bool> put(String key, dynamic value, int seconds) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> add(String key, dynamic value, int seconds) async {
    if (values.containsKey(key)) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    this.values.addAll(values);
    return true;
  }

  @override
  Future<dynamic> increment(String key, [int value = 1]) async {
    final next = (values[key] as num? ?? 0) + value;
    values[key] = next;
    return next;
  }

  @override
  Future<dynamic> decrement(String key, [int value = 1]) =>
      increment(key, -value);

  @override
  Future<bool> forever(String key, dynamic value) => put(key, value, 0);

  @override
  Future<bool> forget(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> flush() async {
    values.clear();
    return true;
  }

  @override
  String getPrefix() => '';

  @override
  Future<List<String>> getAllKeys() async => values.keys.toList();
}
