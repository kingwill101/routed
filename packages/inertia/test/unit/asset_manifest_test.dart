/// Tests for [InertiaAssetManifest] resolution and tag rendering.
library;

import 'dart:convert';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:test/test.dart';

/// Runs asset manifest unit tests.
void main() {
  group('InertiaAssetManifest', () {
    final manifestJson = jsonEncode({
      'resources/js/app.js': {
        'file': 'assets/app.js',
        'src': 'resources/js/app.js',
        'isEntry': true,
        'css': ['assets/app.css'],
        'imports': ['resources/js/vendor.js'],
      },
      'resources/js/vendor.js': {
        'file': 'assets/vendor.js',
        'src': 'resources/js/vendor.js',
        'css': ['assets/vendor.css'],
      },
    });

    test('resolves entry assets in deterministic order', () {
      final manifest = InertiaAssetManifest.fromJsonString(manifestJson);
      final resolution = manifest.resolve('resources/js/app.js');

      expect(resolution.file, equals('assets/app.js'));
      expect(resolution.imports, equals(['assets/vendor.js']));
      expect(resolution.css, equals(['assets/vendor.css', 'assets/app.css']));
    });

    test('renders tags with base url', () {
      final manifest = InertiaAssetManifest.fromJsonString(manifestJson);
      final tags = manifest.renderTags(
        'resources/js/app.js',
        baseUrl: 'https://cdn.example.com/build',
      );

      expect(tags, contains('https://cdn.example.com/build/assets/app.js'));
      expect(tags, contains('assets/vendor.css'));
      expect(tags, contains('<script type="module"'));
      expect(tags, contains('<link rel="stylesheet"'));
    });
  });
}
