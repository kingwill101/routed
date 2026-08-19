import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

import '../test_engine.dart';

void main() {
  test('duplicate method and path warns and keeps the first route', () {
    final engine = testEngine()
      ..get('/duplicate', (context) => context.string('first'))
      ..get('/duplicate', (context) => context.string('second'));
    final output = <String>[];

    final routes = runZoned(
      engine.getAllRoutes,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => output.add(line),
      ),
    );

    expect(routes, hasLength(1));
    expect(routes.single.method, 'GET');
    expect(routes.single.path, '/duplicate');
    expect(
      output.join('\n'),
      allOf(
        contains('[Routed] WARNING: Duplicate route registered for [GET]'),
        contains('/duplicate'),
        contains('was ignored'),
        contains('remains active'),
      ),
    );
  });

  test('same path with different methods is not a duplicate', () {
    final engine = testEngine()
      ..get('/resource', (context) => context.string('get'))
      ..post('/resource', (context) => context.string('post'));
    final output = <String>[];

    final routes = runZoned(
      engine.getAllRoutes,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => output.add(line),
      ),
    );

    expect(routes, hasLength(2));
    expect(output, isEmpty);
  });
}
