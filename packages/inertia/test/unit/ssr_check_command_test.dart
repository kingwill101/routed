/// Tests for the `inertia ssr:check` command.
library;

import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:inertia_dart/src/cli/ssr_check_command.dart';
import 'package:test/test.dart';

void main() {
  group('InertiaSsrCheckCommand', () {
    test('returns success when health endpoint is ok', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/health') {
          request.response.statusCode = 204;
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final runner = CommandRunner<int>('inertia', 'Inertia CLI')
        ..addCommand(InertiaSsrCheckCommand());

      final result = await runner.run([
        'ssr:check',
        '--url',
        'http://127.0.0.1:${server.port}',
      ]);

      expect(result, equals(0));
    });

    test('returns failure when health endpoint is down', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final runner = CommandRunner<int>('inertia', 'Inertia CLI')
        ..addCommand(InertiaSsrCheckCommand());

      final result = await runner.run([
        'ssr:check',
        '--url',
        'http://127.0.0.1:${server.port}',
      ]);

      expect(result, equals(1));
    });

    test('uses override health endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/custom-health') {
          request.response.statusCode = 200;
        } else {
          request.response.statusCode = 500;
        }
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final runner = CommandRunner<int>('inertia', 'Inertia CLI')
        ..addCommand(InertiaSsrCheckCommand());

      final result = await runner.run([
        'ssr:check',
        '--url',
        'http://127.0.0.1:${server.port}',
        '--health',
        'http://127.0.0.1:${server.port}/custom-health',
      ]);

      expect(result, equals(0));
    });

    test('returns failure for unsupported health scheme', () async {
      final runner = CommandRunner<int>('inertia', 'Inertia CLI')
        ..addCommand(InertiaSsrCheckCommand());

      final result = await runner.run([
        'ssr:check',
        '--url',
        'file:///tmp/ssr',
      ]);

      expect(result, equals(1));
    });
  });
}
