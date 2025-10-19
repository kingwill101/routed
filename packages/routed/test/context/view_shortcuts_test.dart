import 'dart:async';

import 'package:routed/routed.dart';
import 'package:server_testing/mock.dart';
import 'package:test/test.dart';

EngineContext _context() {
  final mockRequest = setupRequest('GET', '/shortcut');
  final mockResponse = setupResponse();
  when(mockResponse.flush()).thenAnswer((_) async {});
  when(mockResponse.close()).thenAnswer((_) async {});
  when(mockResponse.done).thenAnswer((_) => Future.value());

  final request = Request(mockRequest, const {}, EngineConfig());
  final response = Response(mockResponse);
  return EngineContext(
    request: request,
    response: response,
    container: Container(),
  );
}

void main() {
  group('requireFound', () {
    test('returns value when present', () {
      final ctx = _context();
      final result = ctx.requireFound<int>(42);

      expect(result, equals(42));
      expect(ctx.errors, isEmpty);
    });

    test('throws NotFoundError and records error when null', () {
      final ctx = _context();

      expect(
        () => ctx.requireFound<Object?>(null, message: 'user missing'),
        throwsA(
          isA<NotFoundError>().having(
            (e) => e.message,
            'message',
            'user missing',
          ),
        ),
      );

      expect(ctx.errors, hasLength(1));
      expect(ctx.errors.first, isA<NotFoundError>());
      expect(ctx.errors.first.message, equals('user missing'));
    });
  });

  group('fetchOr404', () {
    test('awaits callback and returns value', () async {
      final ctx = _context();

      final result = await ctx.fetchOr404(() async => 'item');
      expect(result, equals('item'));
      expect(ctx.errors, isEmpty);
    });

    test('awaits callback and throws NotFoundError', () async {
      final ctx = _context();

      await expectLater(
        ctx.fetchOr404(() async => null, message: 'not here'),
        throwsA(
          isA<NotFoundError>().having((e) => e.message, 'message', 'not here'),
        ),
      );

      expect(ctx.errors, hasLength(1));
      expect(ctx.errors.first.message, equals('not here'));
    });
  });
}
