import 'dart:convert';

import 'package:file/local.dart';
import 'package:kitchen_sink_example/app.dart';
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  late Engine engine;
  final fs = const LocalFileSystem();

  setUp(() {
    engine = buildApp(
      viewsPath: fs.path.join(
        fs.currentDirectory.path,
        'examples',
        'kitchen_sink',
        'templates',
      ),
    );
  });

  tearDown(() => engine.close());

  Future<PortableResponse> request(
    String method,
    String path, {
    Map<String, List<String>> headers = const {},
    Object? body,
  }) {
    final requestHeaders = PortableHeaders(headers);
    final encoded = body == null
        ? null
        : utf8.encode(body is String ? body : jsonEncode(body));
    if (encoded != null && !requestHeaders.contains('content-type')) {
      requestHeaders.set('content-type', 'application/json');
    }
    return engine.handlePortable(
      PortableRequest(
        method: method,
        uri: Uri.parse('http://kitchen.test$path'),
        headers: requestHeaders,
        body: encoded == null ? null : Stream.value(encoded),
      ),
    );
  }

  Future<String> responseBody(PortableResponse response) async {
    final bytes =
        response.bodyBytes ??
        await response.body.fold<List<int>>(
          <int>[],
          (result, chunk) => result..addAll(chunk),
        );
    return utf8.decode(bytes);
  }

  test(
    'portable API path exercises auth, validation, binding, routing, and JSON',
    () async {
      final unauthorized = await request('GET', '/api/recipes');
      expect(unauthorized.statusCode, 401);
      expect(await responseBody(unauthorized), 'Unauthorized');

      final response = await request(
        'POST',
        '/api/recipes',
        headers: {
          'X-API-Key': ['YOUR_API_KEY'],
        },
        body: {
          'name': 'Portable Pasta',
          'description': 'A portable recipe',
          'ingredients': ['pasta', 'tomato'],
          'instructions': 'Cook and serve.',
          'prepTime': 10,
          'cookTime': 20,
          'category': 'dinner',
        },
      );
      expect(response.statusCode, 201);
      final created = jsonDecode(await responseBody(response)) as Map;
      final id = created['id'] as String;
      expect(created['name'], 'Portable Pasta');

      final fetched = await request(
        'GET',
        '/api/recipes/$id',
        headers: {
          'X-API-Key': ['YOUR_API_KEY'],
        },
      );
      expect(fetched.statusCode, 200);
      expect((jsonDecode(await responseBody(fetched)) as Map)['id'], id);

      final updated = await request(
        'PUT',
        '/api/recipes/$id',
        headers: {
          'X-API-Key': ['YOUR_API_KEY'],
        },
        body: {
          'name': 'Updated Pasta',
          'description': 'Updated portable recipe',
          'ingredients': ['pasta', 'basil'],
          'category': 'lunch',
        },
      );
      expect(updated.statusCode, 200);
      expect(
        (jsonDecode(await responseBody(updated)) as Map)['name'],
        'Updated Pasta',
      );
    },
  );

  test('portable session path persists cookies between requests', () async {
    final set = await request('GET', '/set');
    expect(set.statusCode, 200);
    final cookie = set.headers['set-cookie']!.first.split(';').first;

    final read = await request(
      'GET',
      '/test',
      headers: {
        'cookie': [cookie],
      },
    );
    expect(read.statusCode, 200);
    expect(await responseBody(read), 'it worked!');
  });

  test('portable view and fallback paths are wired', () async {
    final page = await request('GET', '/');
    expect(page.statusCode, 200);
    expect(await responseBody(page), contains('Recipes'));

    final fallback = await request('GET', '/does-not-exist');
    expect(fallback.statusCode, 200);
    expect(await responseBody(fallback), 'fallback');
  });
}
