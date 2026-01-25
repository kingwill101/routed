/// Tests for testing helpers and extensions.
library;
import 'dart:convert';

import 'package:server_testing/server_testing.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs testing helper unit tests.
void main() {
  group('AssertableInertia', () {
    test('asserts component and props', () {
      final page = {
        'component': 'Home',
        'props': {
          'name': 'Ada',
          'user': {'role': 'Engineer'},
        },
        'url': '/home',
        'version': '1.0',
      };

      final assertable = AssertableInertia(page);
      assertable
          .component('Home')
          .where('name', 'Ada')
          .where('user.role', 'Engineer')
          .has('user')
          .missing('missing');
    });
  });

  group('InertiaTestExtensions', () {
    test('asserts inertia response', () {
      final page = {
        'component': 'Dashboard',
        'props': {'name': 'Ada'},
        'url': '/dashboard',
        'version': '1.0',
      };

      final response = TestResponse(
        statusCode: 200,
        headers: {
          'X-Inertia': ['true'],
          'Content-Type': ['application/json'],
        },
        bodyBytes: utf8.encode(jsonEncode(page)),
        uri: '/dashboard',
      );

      response.assertInertia((inertia) {
        inertia.component('Dashboard').where('name', 'Ada');
      });
    });

    test('fails when missing inertia header', () {
      final response = TestResponse(
        statusCode: 200,
        headers: {
          'Content-Type': ['application/json'],
        },
        bodyBytes: utf8.encode(jsonEncode({'ok': true})),
        uri: '/dashboard',
      );

      expect(() => response.assertInertia(), throwsA(isA<TestFailure>()));
    });
  });
}
