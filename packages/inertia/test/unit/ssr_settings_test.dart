/// Tests for Inertia SSR settings.
library;

import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:test/test.dart';

void main() {
  group('InertiaSsrSettings', () {
    test('resolves render endpoints', () {
      final base = InertiaSsrSettings(
        endpoint: Uri.parse('http://localhost:13714'),
      );
      expect(base.resolveRenderEndpoint()?.path, equals('/render'));

      final direct = InertiaSsrSettings(
        endpoint: Uri.parse('http://localhost:13714/render'),
      );
      expect(direct.resolveRenderEndpoint()?.path, equals('/render'));
    });

    test('resolves health and shutdown endpoints', () {
      final base = InertiaSsrSettings(
        endpoint: Uri.parse('http://localhost:13714'),
      );
      expect(base.resolveHealthEndpoint()?.path, equals('/health'));
      expect(base.resolveShutdownEndpoint()?.path, equals('/shutdown'));

      final override = InertiaSsrSettings(
        endpoint: Uri.parse('http://localhost:13714'),
        healthEndpoint: Uri.parse('http://localhost:13714/custom-health'),
        shutdownEndpoint: Uri.parse('http://localhost:13714/custom-shutdown'),
      );
      expect(override.resolveHealthEndpoint()?.path, equals('/custom-health'));
      expect(
        override.resolveShutdownEndpoint()?.path,
        equals('/custom-shutdown'),
      );
    });

    test('copyWith overrides values', () {
      final settings = InertiaSsrSettings();
      final updated = settings.copyWith(
        enabled: true,
        runtime: 'node',
        runtimeArgs: const ['--trace-warnings'],
      );

      expect(updated.enabled, isTrue);
      expect(updated.runtime, equals('node'));
      expect(updated.runtimeArgs, equals(['--trace-warnings']));
    });

    test('bundle detector uses configured paths', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'inertia_ssr_settings_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final bundle = File('${tempDir.path}/bootstrap/ssr/ssr.mjs');
      await bundle.create(recursive: true);

      final settings = InertiaSsrSettings(workingDirectory: tempDir);
      expect(settings.bundleDetector().detect(), equals(bundle.path));
    });
  });
}
