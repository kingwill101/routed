import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthGateRegistrationException exposes message', () {
    final error = AuthGateRegistrationException('duplicate');
    expect(error.message, equals('duplicate'));
    expect(error.toString(), contains('duplicate'));
  });

  test('AuthGateViolation stores ability/context payload', () {
    final violation = AuthGateViolation<String>(
      ability: 'posts.publish',
      context: 'ctx-1',
      message: 'denied',
      payload: {'id': 1},
    );

    expect(violation.ability, equals('posts.publish'));
    expect(violation.context, equals('ctx-1'));
    expect(violation.message, equals('denied'));
    expect(violation.payload, isA<Map<String, Object>>());
  });

  test(
    'AuthGateEvaluationContext and AuthGateEvaluation are constructible',
    () {
      final principal = AuthPrincipal(id: 'u1', roles: const ['admin']);
      final ctx = AuthGateEvaluationContext<String>(
        context: 'context',
        principal: principal,
        payload: 7,
      );
      final eval = AuthGateEvaluation<String>(
        ability: 'posts.publish',
        allowed: true,
        context: ctx.context,
        principal: ctx.principal,
        payload: ctx.payload,
      );

      expect(eval.allowed, isTrue);
      expect(eval.principal?.id, equals('u1'));
      expect(eval.payload, equals(7));
    },
  );
}
