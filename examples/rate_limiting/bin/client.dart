// Rate Limiting Client
//
// Exercises the rate-limited endpoints to demonstrate how the framework
// responds when limits are exceeded.
//
// Start the server first:
//   dart run bin/server.dart
//
// Then run this client:
//   dart run bin/client.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _base = 'http://localhost:3000';

/// ANSI colour helpers for readable output.
String _bold(String s) => '\x1B[1m$s\x1B[0m';
String _dim(String s) => '\x1B[2m$s\x1B[0m';
String _cyan(String s) => '\x1B[36m$s\x1B[0m';
String _green(String s) => '\x1B[32m$s\x1B[0m';
String _red(String s) => '\x1B[31m$s\x1B[0m';

void _printHeader(String title) {
  print('');
  print(_bold('=' * 64));
  print(_bold('  $title'));
  print(_bold('=' * 64));
}

void _printResponse(int index, http.Response response) {
  final status = response.statusCode;
  final colour = status == 429 ? _red : _green;
  final retryAfter = response.headers['retry-after'];

  final parts = <String>[
    '  ${_dim("#${index.toString().padLeft(2, "0")}")}',
    colour('$status'),
  ];

  if (retryAfter != null) {
    parts.add('${_dim("Retry-After:")} ${retryAfter}s');
  }

  // Show body snippet for 429 responses
  if (status == 429) {
    try {
      final body = jsonDecode(response.body);
      parts.add(_dim(jsonEncode(body)));
    } catch (_) {
      parts.add(_dim(response.body.substring(0, 80)));
    }
  }

  print(parts.join('  '));
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Future<void> _fireRequests(
  http.Client client,
  String method,
  String path, {
  int count = 12,
  Map<String, String> headers = const {},
  Duration delay = const Duration(milliseconds: 50),
}) async {
  final uri = Uri.parse('$_base$path');
  for (var i = 1; i <= count; i++) {
    final response = method == 'POST'
        ? await client.post(
            uri,
            headers: {'Accept': 'application/json', ...headers},
          )
        : await client.get(
            uri,
            headers: {'Accept': 'application/json', ...headers},
          );
    _printResponse(i, response);
    if (i < count) await Future.delayed(delay);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main() async {
  final client = http.Client();

  try {
    // ------------------------------------------------------------------
    _printHeader('1. Global Policy — Token Bucket (10 req / 30s)');
    print(_dim('  Sending 12 rapid GET /health requests'));
    print(_dim('  Expect: first ~10 succeed, then 429s'));
    // ------------------------------------------------------------------

    await _fireRequests(client, 'GET', '/health');

    // ------------------------------------------------------------------
    _printHeader('2. Auth Policy — Sliding Window (5 req / 1m)');
    print(_dim('  Sending 8 rapid POST /auth/login requests'));
    print(_dim('  Expect: first 5 succeed, then 429s'));
    // ------------------------------------------------------------------

    await _fireRequests(client, 'POST', '/auth/login', count: 8);

    // ------------------------------------------------------------------
    _printHeader('3. API Key Policy — Header-Keyed (3 req / 1m)');
    print(_dim('  Sending 5 requests with X-API-Key: demo-key'));
    print(_dim('  Expect: first 3 succeed, then 429s'));
    // ------------------------------------------------------------------

    await _fireRequests(
      client,
      'GET',
      '/api/data',
      count: 5,
      headers: {'X-API-Key': 'demo-key'},
    );

    // ------------------------------------------------------------------
    _printHeader('4. API Key Policy — Different Keys Are Independent');
    print(_dim('  Sending 2 requests each with different API keys'));
    print(_dim('  Expect: all succeed (each key has its own counter)'));
    // ------------------------------------------------------------------

    for (final key in ['alpha', 'beta']) {
      print('  ${_cyan("Key: $key")}');
      await _fireRequests(
        client,
        'GET',
        '/api/data',
        count: 2,
        headers: {'X-API-Key': key},
      );
    }

    // ------------------------------------------------------------------
    _printHeader('5. Quota Policy — Daily Limit (100 req / 1d)');
    print(_dim('  Sending 3 GET /quota requests'));
    print(_dim('  Expect: all succeed (well within daily limit)'));
    // ------------------------------------------------------------------

    await _fireRequests(client, 'GET', '/quota', count: 3);

    // ------------------------------------------------------------------
    print('');
    print(_green('Done! All rate limiting scenarios demonstrated.'));
    print('');
  } catch (e) {
    print('Error: $e');
    print('Make sure the server is running: dart run bin/server.dart');
    exit(1);
  } finally {
    client.close();
  }
}
