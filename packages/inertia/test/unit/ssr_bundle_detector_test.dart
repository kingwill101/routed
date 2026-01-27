/// Tests for SSR bundle detection.
library;

import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:test/test.dart';

void main() {
  group('SsrBundleDetector', () {
    test('detects explicit bundle path', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'inertia_bundle_explicit_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final bundle = File('${tempDir.path}/bundle.mjs');
      await bundle.create(recursive: true);

      final detector = SsrBundleDetector(bundle: bundle.path);
      expect(detector.detect(), equals(bundle.path));
    });

    test('detects default bundle in working directory', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'inertia_bundle_default_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final bundle = File('${tempDir.path}/bootstrap/ssr/ssr.mjs');
      await bundle.create(recursive: true);

      final detector = SsrBundleDetector(workingDirectory: tempDir);
      expect(detector.detect(), equals(bundle.path));
    });

    test('detects candidate paths relative to working directory', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'inertia_bundle_candidate_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final bundle = File('${tempDir.path}/custom/ssr.js');
      await bundle.create(recursive: true);

      final detector = SsrBundleDetector(
        workingDirectory: tempDir,
        candidates: [bundle.path],
      );
      expect(detector.detect(), equals(bundle.path));
    });
  });
}
