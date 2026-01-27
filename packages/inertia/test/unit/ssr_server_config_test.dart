/// Tests for SSR server configuration.
library;

import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:test/test.dart';

void main() {
  group('SsrServerConfig', () {
    test('fromSettings copies settings values', () {
      final workingDirectory = Directory.current;
      final settings = InertiaSsrSettings(
        runtime: 'node',
        bundle: 'bundle.mjs',
        runtimeArgs: const ['--trace-warnings'],
        bundleCandidates: const ['alt.mjs'],
        workingDirectory: workingDirectory,
        environment: const {'FOO': 'bar'},
      );

      final config = SsrServerConfig.fromSettings(settings);
      expect(config.runtime, equals('node'));
      expect(config.bundle, equals('bundle.mjs'));
      expect(config.runtimeArgs, equals(['--trace-warnings']));
      expect(config.bundleCandidates, equals(['alt.mjs']));
      expect(config.workingDirectory?.path, equals(workingDirectory.path));
      expect(config.environment, equals({'FOO': 'bar'}));
    });

    test('resolveBundle uses bundle candidates', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'inertia_ssr_config_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final bundle = File('${tempDir.path}/bundle.mjs');
      await bundle.create(recursive: true);

      final config = SsrServerConfig(
        runtime: 'node',
        workingDirectory: tempDir,
        bundleCandidates: [bundle.path],
      );

      expect(config.resolveBundle(), equals(bundle.path));
    });
  });
}
