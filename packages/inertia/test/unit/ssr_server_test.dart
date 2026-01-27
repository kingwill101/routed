/// Tests for SSR server helpers.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inertia_dart/inertia.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

Future<File> _createScript(Directory dir) async {
  final script = File(path.join(dir.path, 'ssr_bundle.dart'));
  await script.writeAsString('''import 'dart:async';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('ssr stdout');
  stderr.writeln('ssr stderr');
  await Future<void>.delayed(const Duration(milliseconds: 50));
}
''');
  return script;
}

void main() {
  group('SSR server helpers', () {
    test('startSsrServer throws when bundle is missing', () async {
      final config = SsrServerConfig(runtime: 'node', bundle: 'missing.mjs');
      await expectLater(startSsrServer(config), throwsA(isA<StateError>()));
    });

    test('startSsrServer runs bundle and pipes output', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'inertia_ssr_process_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final script = await _createScript(tempDir);
      final config = SsrServerConfig(
        runtime: Platform.resolvedExecutable,
        bundle: script.path,
      );

      final process = await startSsrServer(config);
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final exitCode = await pipeSsrProcess(
        process,
        stdoutSink: stdoutBuffer,
        stderrSink: stderrBuffer,
      );

      expect(exitCode, equals(0));
      expect(stdoutBuffer.toString(), contains('ssr stdout'));
      expect(stderrBuffer.toString(), contains('ssr stderr'));
    });

    test('startSsrServer supports inheritStdio mode', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'inertia_ssr_inherit_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final script = await _createScript(tempDir);
      final config = SsrServerConfig(
        runtime: Platform.resolvedExecutable,
        bundle: script.path,
      );

      final process = await startSsrServer(config, inheritStdio: true);
      final exitCode = await process.exitCode;
      expect(exitCode, equals(0));
    });

    test('checkSsrServer returns true for 2xx status', () async {
      final client = MockClient((request) async {
        expect(request.url.path, equals('/health'));
        return http.Response('', 204);
      });

      final ok = await checkSsrServer(
        endpoint: Uri.parse('http://localhost:13714'),
        client: client,
      );

      expect(ok, isTrue);
    });

    test('checkSsrServer returns false for non-2xx status', () async {
      final client = MockClient((request) async {
        return http.Response('', 500);
      });

      final ok = await checkSsrServer(
        endpoint: Uri.parse('http://localhost:13714'),
        client: client,
      );

      expect(ok, isFalse);
    });

    test('stopSsrServer returns true on success', () async {
      final client = MockClient((request) async {
        expect(request.url.path, equals('/shutdown'));
        return http.Response('', 200);
      });

      final stopped = await stopSsrServer(
        endpoint: Uri.parse('http://localhost:13714'),
        client: client,
      );

      expect(stopped, isTrue);
    });

    test('stopSsrServer returns false on client error', () async {
      final client = MockClient((request) async {
        throw StateError('boom');
      });

      final stopped = await stopSsrServer(
        endpoint: Uri.parse('http://localhost:13714'),
        client: client,
      );

      expect(stopped, isFalse);
    });
  });
}
