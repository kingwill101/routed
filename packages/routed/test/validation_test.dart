import 'dart:convert';
import 'dart:io';

import 'package:http_parser/http_parser.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

TestClient useClient(Engine engine) =>
    TestClient(RoutedRequestHandler(engine), mode: TransportMode.inMemory);

void main() {
  group('Validation Tests', () {
    test('JSON Binding Validation', () async {
      final engine = Engine();

      engine.post('/json', (ctx) async {
        final data = <String, dynamic>{};

        await ctx.validate({
          'name': 'required',
          'age': 'required|numeric',
          'tags': 'required|array'
        });

        await ctx.bind(data);
        ctx.json(data);
      });

      final client = useClient(engine);

      final response = await client.postJson('/json', {
        'name': 'test',
        'age': 2511,
        'tags': ['one', 'two']
      });

      response.assertStatus(200);
    });

    test('Form URL Encoded Binding Validation', () async {
      final engine = Engine();
      engine.post('/form', (ctx) async {
        final data = <String, dynamic>{};

        await ctx.validate({
          'name': 'required',
          'age': 'required|numeric',
        });

        await ctx.bind(data);
        ctx.json(data);
      });

      final client = useClient(engine);

      final response = await client.post(
        '/form',
        'name=test&age=25',
        headers: {
          'Content-Type': ['application/x-www-form-urlencoded']
        },
      );

      response
        ..assertStatus(200)
        ..assertJsonContains({
          'name': 'test',
          'age': '25',
        });
    });

    test('Query Binding Validation', () async {
      final engine = Engine();

      engine.get('/search', (ctx) async {
        final data = <String, dynamic>{};

        await ctx.validate({
          'q': 'required',
          'page': 'required|numeric',
          'sort': 'required',
        });

        await ctx.bind(data);
        ctx.json(data);
      });

      final client = useClient(engine);

      final response = await client.get('/search?q=test&page=1&sort=desc');

      response
        ..assertStatus(200)
        ..assertJsonContains({'q': 'test', 'page': '1', 'sort': 'desc'});
    });

    test('Multipart Form Binding Validation',
        timeout: const Timeout(Duration(seconds: 100)), () async {
      final engine = Engine();

      engine.post('/upload', (ctx) async {
        final data = <String, dynamic>{};

        await ctx.validate({
          'name': 'required',
          'age': 'required|numeric',
          'tags': 'required|array',
          'document': 'required|file'
        });

        await ctx.bind(data);
        ctx.json(data);
      });

      final client = useClient(engine);

      final response = await client.multipart('/upload', (request) {
        request
          ..addField('name', 'test')
          ..addField('age', '255')
          ..addField('tags', 'one')
          ..addField('tags', 'two')
          ..addFileFromBytes(
              name: 'document',
              filename: 'test.txt',
              bytes: utf8.encode('Hello World'),
              contentType: MediaType.parse(ContentType.text.value));
      });

      response
        ..assertStatus(200)
        ..assertJsonContains({
          'name': 'test',
          'age': '255',
          'tags': ['one', 'two']
        });
    });

    test('Validation Error Handling', () async {
      final engine = Engine();

      engine.post('/json2', (ctx) async {
        final data = <String, dynamic>{};

        try {
          await ctx.validate({
            'name': 'required',
            'age': 'required|numeric',
            'tags': 'required|array'
          });

          await ctx.bind(data);
          ctx.json(data);
        } on ValidationError catch (e) {
          ctx.json({'errors': e.errors});
        }
      });

      final TestClient client = useClient(engine);

      final response = await client.postJson('/json2', {
        'name': 'test',
        'age': 'invalid', // Invalid age (not numeric)
        'tags': 'not an array' // Invalid tags (not an array)
      });

      response
        ..assertStatus(200)
        ..assertJsonContains({
          'errors': {
            'age': ['This field must be a number.'],
            'tags': ['This field must be an array.']
          }
        });
    });
  });
}
