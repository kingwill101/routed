// Client that exercises every error route with different Accept headers to
// show how the framework negotiates the response format.
//
// Start the server first:
//   dart run bin/server.dart
//
// Then run this client:
//   dart run bin/client.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

const _base = 'http://localhost:3000';

/// ANSI colour helpers for readable output.
String _bold(String s) => '\x1B[1m$s\x1B[0m';
String _dim(String s) => '\x1B[2m$s\x1B[0m';
String _cyan(String s) => '\x1B[36m$s\x1B[0m';
String _green(String s) => '\x1B[32m$s\x1B[0m';

void _printHeader(String title) {
  print('');
  print(_bold('═' * 72));
  print(_bold('  $title'));
  print(_bold('═' * 72));
}

void _printResponse(
  String label,
  http.Response response, {
  bool formatJson = false,
}) {
  final ct = response.headers['content-type'] ?? 'unknown';
  print('');
  print('  ${_cyan(label)}');
  print('  ${_dim("Status:")} ${response.statusCode}');
  print('  ${_dim("Content-Type:")} $ct');
  print('  ${_dim("Body:")}');

  if (formatJson && ct.contains('json')) {
    try {
      final pretty = const JsonEncoder.withIndent(
        '    ',
      ).convert(jsonDecode(response.body));
      print(pretty);
    } catch (_) {
      print('    ${response.body}');
    }
  } else {
    // Indent each line for readability
    for (final line in response.body.split('\n')) {
      print('    $line');
    }
  }
}

Future<void> main() async {
  final client = http.Client();

  try {
    // ------------------------------------------------------------------
    _printHeader('1. ValidationError — 422 (POST /register)');
    print(_dim('  Throws ValidationError — error map as JSON, page for HTML'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client (Accept: application/json)',
      await client.post(
        Uri.parse('$_base/register'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client (Accept: text/html)',
      await client.post(
        Uri.parse('$_base/register'),
        headers: {'Accept': 'text/html'},
      ),
    );

    _printResponse(
      'Plain client (no Accept header)',
      await client.post(Uri.parse('$_base/register')),
    );

    // ------------------------------------------------------------------
    _printHeader('2. ConflictError — 409 (POST /resources)');
    print(_dim('  Built-in EngineError subclass'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.post(
        Uri.parse('$_base/resources'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.post(
        Uri.parse('$_base/resources'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('3. ForbiddenError — 403 (GET /forbidden)');
    print(_dim('  Built-in EngineError subclass'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.get(
        Uri.parse('$_base/forbidden'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.get(
        Uri.parse('$_base/forbidden'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('4. NotFoundError — 404 (GET /users/99)');
    print(_dim('  Built-in EngineError subclass'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.get(
        Uri.parse('$_base/users/99'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.get(
        Uri.parse('$_base/users/99'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('5. BadRequestError — 400 (POST /parse)');
    print(_dim('  Built-in EngineError subclass'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.post(
        Uri.parse('$_base/parse'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.post(
        Uri.parse('$_base/parse'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('6. Custom error — 402 Payment Required (GET /premium)');
    print(_dim('  User-defined EngineError subclass'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.get(
        Uri.parse('$_base/premium'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.get(
        Uri.parse('$_base/premium'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('7. Unhandled Exception — 500 (GET /danger/crash)');
    print(_dim('  Caught by recoveryMiddleware (scoped to /danger group)'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.get(
        Uri.parse('$_base/danger/crash'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.get(
        Uri.parse('$_base/danger/crash'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('8. Manual errorResponse() — 404 (GET /items/42)');
    print(_dim('  Handler calls ctx.errorResponse() directly'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.get(
        Uri.parse('$_base/items/42'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.get(
        Uri.parse('$_base/items/42'),
        headers: {'Accept': 'text/html'},
      ),
    );

    _printResponse(
      'Plain client',
      await client.get(Uri.parse('$_base/items/42')),
    );

    // ------------------------------------------------------------------
    _printHeader('9. Custom JSON body — 410 Gone (DELETE /items/7)');
    print(_dim('  errorResponse() with custom jsonBody override'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await http.delete(
        Uri.parse('$_base/items/7'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await http.delete(
        Uri.parse('$_base/items/7'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('10. XHR Detection (GET /forbidden)');
    print(_dim('  X-Requested-With: XMLHttpRequest triggers JSON'));
    // ------------------------------------------------------------------

    _printResponse(
      'XHR client (no Accept, but X-Requested-With: XMLHttpRequest)',
      await client.get(
        Uri.parse('$_base/forbidden'),
        headers: {'X-Requested-With': 'XMLHttpRequest'},
      ),
      formatJson: true,
    );

    // ------------------------------------------------------------------
    _printHeader('11. No matching route — 404');
    print(_dim('  Framework\'s built-in 404 is also content-negotiated'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.get(
        Uri.parse('$_base/no-such-route'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.get(
        Uri.parse('$_base/no-such-route'),
        headers: {'Accept': 'text/html'},
      ),
    );

    // ------------------------------------------------------------------
    _printHeader('12. Negotiation Helpers (GET /inspect)');
    print(_dim('  Shows what wantsJson/acceptsHtml/accepts() return'));
    // ------------------------------------------------------------------

    _printResponse(
      'JSON client',
      await client.get(
        Uri.parse('$_base/inspect'),
        headers: {'Accept': 'application/json'},
      ),
      formatJson: true,
    );

    _printResponse(
      'Browser client',
      await client.get(
        Uri.parse('$_base/inspect'),
        headers: {'Accept': 'text/html, application/xhtml+xml'},
      ),
      formatJson: true,
    );

    _printResponse(
      'XML client',
      await client.get(
        Uri.parse('$_base/inspect'),
        headers: {'Accept': 'application/xml'},
      ),
      formatJson: true,
    );

    // ------------------------------------------------------------------
    print('');
    print(_green('Done! All error scenarios demonstrated.'));
    print('');
  } finally {
    client.close();
  }
}
