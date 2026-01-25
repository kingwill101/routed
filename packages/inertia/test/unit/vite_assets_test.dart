/// Tests for [InertiaViteAssets] resolution.
library;
import 'dart:io';

import 'package:inertia_dart/inertia.dart';
import 'package:test/test.dart';

/// Runs Vite asset helper unit tests.
void main() {
  group('InertiaViteAssets', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('inertia_vite_assets');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('uses hot file for dev tags', () async {
      final hotFile = File('${tempDir.path}/public/hot');
      await hotFile.create(recursive: true);
      await hotFile.writeAsString('http://localhost:5173');

      final assets = InertiaViteAssets(
        entry: 'src/main.jsx',
        hotFile: hotFile.path,
        includeReactRefresh: true,
      );

      final tags = await assets.resolve();
      expect(tags.devServerUrl, equals('http://localhost:5173'));
      expect(
        tags.renderScripts(),
        contains('http://localhost:5173/src/main.jsx'),
      );
      expect(tags.renderScripts(), contains('@react-refresh'));
    });

    test('uses manifest for production tags', () async {
      final manifestFile = File('${tempDir.path}/manifest.json');
      await manifestFile.writeAsString('''{
  "src/main.jsx": {
    "file": "assets/main.js",
    "src": "src/main.jsx",
    "css": ["assets/main.css"]
  }
}''');

      final assets = InertiaViteAssets(
        entry: 'src/main.jsx',
        manifestPath: manifestFile.path,
      );

      final tags = await assets.resolve();
      expect(tags.renderScripts(), contains('assets/main.js'));
      expect(tags.renderStyles(), contains('assets/main.css'));
    });
  });
}
