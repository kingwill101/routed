/// Tests for [HttpSsrGateway] behavior.
library;
import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:inertia_dart/inertia.dart';

/// Runs HTTP SSR gateway unit tests.
void main() {
  group('HttpSsrGateway', () {
    test('renders SSR response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'body': '<div>ok</div>', 'head': '<title>Ok</title>'}),
          200,
        );
      });

      final gateway = HttpSsrGateway(
        Uri.parse('http://localhost/render'),
        client: client,
      );

      final response = await gateway.render('{"component":"Home"}');
      expect(response.body, contains('ok'));
      expect(response.head, contains('Ok'));
    });

    test('throws on error status', () async {
      final client = MockClient((request) async {
        return http.Response('fail', 500);
      });

      final gateway = HttpSsrGateway(
        Uri.parse('http://localhost/render'),
        client: client,
      );

      expect(
        () => gateway.render('{"component":"Home"}'),
        throwsA(isA<StateError>()),
      );
    });

    test('health check returns status', () async {
      final client = MockClient((request) async {
        return http.Response('ok', 204);
      });

      final gateway = HttpSsrGateway(
        Uri.parse('http://localhost/render'),
        healthEndpoint: Uri.parse('http://localhost/health'),
        client: client,
      );

      final isHealthy = await gateway.healthCheck();
      expect(isHealthy, isTrue);
    });
  });
}
