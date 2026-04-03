import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes callback provider success with user and redirect', () {
    final user = AuthUser(id: 'user-1', email: 'user@example.com');
    final outcome = normalizeAuthCallbackProviderResult(
      CallbackResult.success(user, redirect: '/dashboard'),
    );

    expect(outcome.isSuccess, isTrue);
    expect(outcome.user, same(user));
    expect(outcome.redirectUrl, equals('/dashboard'));
    expect(outcome.errorCode, isNull);
  });

  test('normalizes callback provider failure with explicit error', () {
    final outcome = normalizeAuthCallbackProviderResult(
      const CallbackResult.failure('invalid_signature'),
    );

    expect(outcome.isSuccess, isFalse);
    expect(outcome.user, isNull);
    expect(outcome.redirectUrl, isNull);
    expect(outcome.errorCode, equals('invalid_signature'));
  });

  test('normalizes callback provider failure with fallback error', () {
    final outcome = normalizeAuthCallbackProviderResult(
      const CallbackResult(user: null),
      fallbackErrorCode: 'custom_failed',
    );

    expect(outcome.isSuccess, isFalse);
    expect(outcome.errorCode, equals('custom_failed'));
  });

  test('normalization preserves empty error strings', () {
    final outcome = normalizeAuthCallbackProviderResult(
      const CallbackResult.failure(''),
    );

    expect(outcome.isSuccess, isFalse);
    expect(outcome.errorCode, equals(''));
  });
}
