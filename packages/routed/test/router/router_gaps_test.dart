import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed/src/router/registered_route.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('MiddlewareReference', () {
    test('create() produces a middleware with a registered name', () {
      final mw = MiddlewareReference.create('auth');
      expect(MiddlewareReference.lookup(mw), 'auth');
    });

    test(
      'placeholder throws UnimplementedError if called without resolution',
      () async {
        final placeholder = MiddlewareReference.create('unresolved');
        final dynamicPlaceholder = placeholder as dynamic;

        expect(
          () => dynamicPlaceholder(
            Object(),
            () => throw UnimplementedError('next'),
          ),
          throwsA(anyOf(isA<UnimplementedError>(), isA<TypeError>())),
        );
      },
    );

    test('clear() removes the name marker', () {
      final mw = MiddlewareReference.create('temp');
      expect(MiddlewareReference.lookup(mw), 'temp');

      MiddlewareReference.clear(mw);
      expect(MiddlewareReference.lookup(mw), isNull);
    });

    test('lookup() returns null for non-reference middleware', () {
      FutureOr<Response> normalMiddleware(EngineContext ctx, Next next) =>
          next();
      expect(MiddlewareReference.lookup(normalMiddleware), isNull);
    });

    test(
      'MiddlewareRef.of() is equivalent to MiddlewareReference.create()',
      () {
        final mw = MiddlewareRef.of('myRef');
        expect(MiddlewareReference.lookup(mw), 'myRef');
      },
    );
  });

  group('RegisteredRoute', () {
    test('constructor defaults constraints to empty map when null', () {
      final route = RegisteredRoute(
        method: 'GET',
        path: '/test',
        handler: (ctx) => ctx.string('ok'),
      );
      expect(route.constraints, isA<Map<String, dynamic>>());
      expect(route.constraints, isEmpty);
    });

    test('constructor preserves provided constraints', () {
      final route = RegisteredRoute(
        method: 'GET',
        path: '/test',
        handler: (ctx) => ctx.string('ok'),
        constraints: {'id': r'\d+'},
      );
      expect(route.constraints, {'id': r'\d+'});
    });

    test('constraints map is mutable (independent copy)', () {
      final original = {'id': r'\d+'};
      final route = RegisteredRoute(
        method: 'GET',
        path: '/test',
        handler: (ctx) => ctx.string('ok'),
        constraints: original,
      );
      // Mutate the route's constraints
      route.constraints['name'] = r'\w+';
      // Original should not be affected
      expect(original.containsKey('name'), isFalse);
    });

    test('toString formats correctly', () {
      final route = RegisteredRoute(
        method: 'GET',
        path: '/users/{id}',
        handler: (ctx) => ctx.string('ok'),
        name: 'users.show',
      );
      // Must set finalMiddlewares before toString
      route.finalMiddlewares = [];
      expect(
        route.toString(),
        '[GET] /users/{id} with name users.show [middlewares: 0]',
      );
    });

    test('toString with middlewares', () {
      FutureOr<Response> mw(EngineContext ctx, Next next) => next();
      final route = RegisteredRoute(
        method: 'POST',
        path: '/items',
        handler: (ctx) => ctx.string('ok'),
      );
      route.finalMiddlewares = [mw, mw];
      expect(
        route.toString(),
        '[POST] /items with name (no name) [middlewares: 2]',
      );
    });

    test('name defaults to null', () {
      final route = RegisteredRoute(
        method: 'GET',
        path: '/',
        handler: (ctx) => ctx.string('ok'),
      );
      expect(route.name, isNull);
    });

    test('routeMiddlewares defaults to empty list', () {
      final route = RegisteredRoute(
        method: 'GET',
        path: '/',
        handler: (ctx) => ctx.string('ok'),
      );
      expect(route.routeMiddlewares, isEmpty);
    });
  });
}
