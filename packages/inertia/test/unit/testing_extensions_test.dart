/// Tests for testing helpers and extensions.
library;

import 'dart:convert';
import 'dart:io';

import 'package:server_testing/server_testing.dart';
import 'package:inertia_dart/inertia_dart.dart';

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

    test('asserts url and version', () {
      final page = {
        'component': 'Profile',
        'props': {'id': 42},
        'url': '/profile/42',
        'version': 'v2',
      };

      final assertable = AssertableInertia(page);
      assertable.url('/profile/42').version('v2').where('id', 42);
    });

    test('checks component file existence when enabled', () async {
      final tempDir = await Directory.systemTemp.createTemp('inertia_pages');
      addTearDown(() => tempDir.delete(recursive: true));

      final pagesDir = Directory('${tempDir.path}/pages/Stubs');
      await pagesDir.create(recursive: true);
      final file = File('${pagesDir.path}/ExamplePage.vue');
      await file.writeAsString('');

      final settings = AssertableInertia.testing;
      final previousEnsure = settings.ensurePagesExist;
      final previousPaths = List<String>.from(settings.pagePaths);
      final previousExtensions = List<String>.from(settings.pageExtensions);
      addTearDown(() {
        settings.ensurePagesExist = previousEnsure;
        settings.pagePaths = previousPaths;
        settings.pageExtensions = previousExtensions;
      });

      settings.ensurePagesExist = true;
      settings.pagePaths = ['${tempDir.path}/pages'];
      settings.pageExtensions = ['vue'];

      final page = {
        'component': 'Stubs/ExamplePage',
        'props': const {},
        'url': '/',
        'version': '1',
      };

      AssertableInertia(page).component('Stubs/ExamplePage');
    });

    test('fails when component file is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('inertia_pages');
      addTearDown(() => tempDir.delete(recursive: true));

      final settings = AssertableInertia.testing;
      final previousEnsure = settings.ensurePagesExist;
      final previousPaths = List<String>.from(settings.pagePaths);
      final previousExtensions = List<String>.from(settings.pageExtensions);
      addTearDown(() {
        settings.ensurePagesExist = previousEnsure;
        settings.pagePaths = previousPaths;
        settings.pageExtensions = previousExtensions;
      });

      settings.ensurePagesExist = true;
      settings.pagePaths = [tempDir.path];
      settings.pageExtensions = ['vue'];

      final page = {
        'component': 'Foo',
        'props': const {},
        'url': '/',
        'version': '1',
      };

      expect(
        () => AssertableInertia(page).component('Foo'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('can force enable component file existence', () async {
      final settings = AssertableInertia.testing;
      final previousEnsure = settings.ensurePagesExist;
      addTearDown(() {
        settings.ensurePagesExist = previousEnsure;
      });

      settings.ensurePagesExist = false;

      final page = {
        'component': 'Foo',
        'props': const {},
        'url': '/',
        'version': '1',
      };

      expect(
        () => AssertableInertia(page).component('Foo', ensurePageExists: true),
        throwsA(isA<TestFailure>()),
      );
    });

    test('can force disable component file existence', () async {
      final settings = AssertableInertia.testing;
      final previousEnsure = settings.ensurePagesExist;
      addTearDown(() {
        settings.ensurePagesExist = previousEnsure;
      });

      settings.ensurePagesExist = true;

      final page = {
        'component': 'Foo',
        'props': const {},
        'url': '/',
        'version': '1',
      };

      expect(
        () => AssertableInertia(page).component('Foo', ensurePageExists: false),
        returnsNormally,
      );
    });

    test('respects page paths when checking components', () async {
      final tempDir = await Directory.systemTemp.createTemp('inertia_pages');
      addTearDown(() => tempDir.delete(recursive: true));

      final settings = AssertableInertia.testing;
      final previousEnsure = settings.ensurePagesExist;
      final previousPaths = List<String>.from(settings.pagePaths);
      final previousExtensions = List<String>.from(settings.pageExtensions);
      addTearDown(() {
        settings.ensurePagesExist = previousEnsure;
        settings.pagePaths = previousPaths;
        settings.pageExtensions = previousExtensions;
      });

      settings.ensurePagesExist = true;
      settings.pagePaths = [tempDir.path];
      settings.pageExtensions = ['vue'];

      final page = {
        'component': 'fixtures/ExamplePage',
        'props': const {},
        'url': '/',
        'version': '1',
      };

      expect(
        () => AssertableInertia(page).component('fixtures/ExamplePage'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('respects page extensions when checking components', () async {
      final tempDir = await Directory.systemTemp.createTemp('inertia_pages');
      addTearDown(() => tempDir.delete(recursive: true));

      final pagesDir = Directory('${tempDir.path}/pages');
      await pagesDir.create(recursive: true);
      final file = File('${pagesDir.path}/ExamplePage.vue');
      await file.writeAsString('');

      final settings = AssertableInertia.testing;
      final previousEnsure = settings.ensurePagesExist;
      final previousPaths = List<String>.from(settings.pagePaths);
      final previousExtensions = List<String>.from(settings.pageExtensions);
      addTearDown(() {
        settings.ensurePagesExist = previousEnsure;
        settings.pagePaths = previousPaths;
        settings.pageExtensions = previousExtensions;
      });

      settings.ensurePagesExist = true;
      settings.pagePaths = ['${tempDir.path}/pages'];
      settings.pageExtensions = ['bin'];

      final page = {
        'component': 'ExamplePage',
        'props': const {},
        'url': '/',
        'version': '1',
      };

      expect(
        () => AssertableInertia(page).component('ExamplePage'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('reloads with overridden props', () {
      final page = {
        'component': 'Foo',
        'props': {'foo': 0},
        'url': '/foo',
        'version': '1',
      };

      final assertable = AssertableInertia(page);
      assertable.reload(
        (inertia) => inertia.where('foo', 1),
        propsOverride: {'foo': 1},
      );
    });

    test('reloadOnly filters props', () {
      final page = {
        'component': 'Foo',
        'props': {'foo': 'bar'},
        'url': '/foo',
        'version': '1',
      };

      final assertable = AssertableInertia(page);
      final result = assertable.reloadOnly('lazy1', (inertia) {
        inertia.where('lazy1', 'baz').missing('foo');
      }, propsOverride: {'foo': 'bar', 'lazy1': 'baz'});

      expect(result, same(assertable));
    });

    test('reloadOnly accepts key lists', () {
      final page = {
        'component': 'Foo',
        'props': {'foo': 'bar'},
        'url': '/foo',
        'version': '1',
      };

      final assertable = AssertableInertia(page);
      assertable.reloadOnly(['lazy1'], (inertia) {
        inertia.where('lazy1', 'baz');
        inertia.missing('foo');
      }, propsOverride: {'foo': 'bar', 'lazy1': 'baz'});
    });

    test('reloadExcept filters props', () {
      final page = {
        'component': 'Foo',
        'props': {'foo': 'bar'},
        'url': '/foo',
        'version': '1',
      };

      final assertable = AssertableInertia(page);
      assertable.reloadExcept(['lazy1'], (inertia) {
        inertia.where('foo', 'bar').where('lazy2', 'qux');
        inertia.missing('lazy1');
      }, propsOverride: {'foo': 'bar', 'lazy1': 'baz', 'lazy2': 'qux'});
    });

    test('loads deferred props by group', () {
      final page = {
        'component': 'Foo',
        'props': {'foo': 'bar'},
        'deferredProps': {
          'default': ['deferred1'],
          'custom': ['deferred2', 'deferred3'],
        },
        'url': '/foo',
        'version': '1',
      };

      final assertable = AssertableInertia(page);

      assertable.loadDeferredProps(
        (inertia) {
          inertia.where('deferred1', 'baz');
          inertia.where('deferred2', 'qux');
          inertia.where('deferred3', 'quux');
        },
        propsOverride: {
          'foo': 'bar',
          'deferred1': 'baz',
          'deferred2': 'qux',
          'deferred3': 'quux',
        },
      );

      assertable.loadDeferredProps(
        (inertia) {
          inertia.where('deferred1', 'baz');
          inertia.missing('deferred2');
          inertia.missing('deferred3');
        },
        groups: 'default',
        propsOverride: {
          'deferred1': 'baz',
          'deferred2': 'qux',
          'deferred3': 'quux',
        },
      );

      assertable.loadDeferredProps(
        (inertia) {
          inertia.missing('deferred1');
          inertia.where('deferred2', 'qux');
          inertia.where('deferred3', 'quux');
        },
        groups: ['custom'],
        propsOverride: {
          'deferred1': 'baz',
          'deferred2': 'qux',
          'deferred3': 'quux',
        },
      );

      assertable.loadDeferredProps(
        (inertia) {
          inertia.where('deferred1', 'baz');
          inertia.where('deferred2', 'qux');
          inertia.where('deferred3', 'quux');
        },
        groups: ['default', 'custom'],
        propsOverride: {
          'deferred1': 'baz',
          'deferred2': 'qux',
          'deferred3': 'quux',
        },
      );
    });

    test('asserts flash data', () {
      final page = {
        'component': 'Foo',
        'props': const {},
        'url': '/foo',
        'version': '1',
        'flash': {
          'message': 'Hello',
          'notification': {'type': 'success'},
        },
      };

      final assertable = AssertableInertia(page);
      assertable
          .hasFlash('message')
          .hasFlash('message', 'Hello')
          .hasFlash('notification.type', 'success')
          .missingFlash('other')
          .missingFlash('notification.other');
    });

    test('flash assertions fail when missing', () {
      final page = {
        'component': 'Foo',
        'props': const {},
        'url': '/foo',
        'version': '1',
        'flash': const {},
      };

      final assertable = AssertableInertia(page);
      expect(() => assertable.hasFlash('message'), throwsA(isA<TestFailure>()));
    });

    test('flash assertions fail when value mismatches', () {
      final page = {
        'component': 'Foo',
        'props': const {},
        'url': '/foo',
        'version': '1',
        'flash': {'message': 'Hello'},
      };

      final assertable = AssertableInertia(page);
      expect(
        () => assertable.hasFlash('message', 'Different'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('missingFlash fails when key exists', () {
      final page = {
        'component': 'Foo',
        'props': const {},
        'url': '/foo',
        'version': '1',
        'flash': {'message': 'Hello'},
      };

      final assertable = AssertableInertia(page);
      expect(
        () => assertable.missingFlash('message'),
        throwsA(isA<TestFailure>()),
      );
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
