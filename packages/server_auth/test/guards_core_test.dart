import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('GuardResult allow/deny constructors set expected values', () {
    const allowed = GuardResult<String>.allow();
    const denied = GuardResult<String>.deny('blocked');

    expect(allowed.allowed, isTrue);
    expect(allowed.response, isNull);
    expect(denied.allowed, isFalse);
    expect(denied.response, equals('blocked'));
  });

  test('AuthGuard typedef supports async handlers', () async {
    Future<GuardResult<String>> handler(String ctx) async {
      if (ctx == 'ok') return const GuardResult<String>.allow();
      return const GuardResult<String>.deny('unauthorized');
    }

    final AuthGuard<String, String> typed = handler;

    final denied = await typed('nope');
    final allowed = await typed('ok');

    expect(denied.allowed, isFalse);
    expect(denied.response, equals('unauthorized'));
    expect(allowed.allowed, isTrue);
  });
}
