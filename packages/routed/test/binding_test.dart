import 'dart:convert';
import 'dart:core';
import 'dart:io' show Directory, FileSystemException;

import 'package:routed/routed.dart';
import 'package:routed/src/binding/binding.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  late TestClient client;

  tearDown(() async {
    await client.close();
  });

  group('Binding Tests', () {
    test('JSON Binding', () async {
      final engine = Engine();
      engine.post('/json', (ctx) async {
        final data = <String, dynamic>{};
        await ctx.shouldBindWith(data, jsonBinding);
        ctx.json(data);
      });

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.post('/json', {
        'name': 'test',
        'age': 25,
        'tags': ['one', 'two'],
      });

      response.dump();
      response
        ..assertStatus(200)
        ..assertHasHeader("Content-type")
        ..assertJsonContains({
          'name': 'test',
          'age': 25,
          'tags': ['one', 'two'],
        });
    });

    test('Form URL Encoded Binding', () async {
      final engine = Engine();

      engine.post('/form', (ctx) async {
        final data = <String, dynamic>{};
        await ctx.shouldBindWith(data, formBinding);
        ctx.json(data);
      });

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.post(
        '/form',
        'name=test&age=25',
        headers: {
          'Content-Type': ['application/x-www-form-urlencoded'],
        },
      );

      response
        ..assertStatus(200)
        ..assertJsonContains({'name': 'test', 'age': '25'});
    });

    test('Multipart Form Binding', () async {
      final uploadDir = await Directory.systemTemp.createTemp(
        'routed-binding-upload-',
      );
      addTearDown(() async {
        if (await uploadDir.exists()) {
          try {
            await uploadDir.delete(recursive: true);
          } on FileSystemException {
            // Ignore cleanup errors caused by restrictive permissions.
          }
        }
      });

      final engine = Engine(
        configItems: {
          'uploads': {'directory': uploadDir.path},
        },
      );

      engine.post('/upload', (ctx) async {
        // Test form fields
        final name = await ctx.postForm('name');
        final age = await ctx.defaultPostForm('age', '0');
        final hobby = await ctx.postForm('hobby');
        final tags = await ctx.postFormArray('tags');
        final Map<String, dynamic> prefs = {
          "pref_theme": await ctx.postForm('pref_theme'),
          "pref_lang": await ctx.postForm('pref_lang'),
        };

        // Test file upload
        final file = await ctx.formFile('document');

        ctx.json({
          'name': name,
          'age': age,
          'hobby': hobby,
          'tags': tags,
          'preferences': prefs,
          'hasFile': file != null,
          'fileName': file?.filename,
          'fileSize': file?.size,
        });
      });

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.multipart('/upload', (request) {
        request
          ..addField('name', 'test')
          ..addField('age', '25')
          ..addField('hobby', 'reading')
          ..addField('tags', 'one')
          ..addField('tags', 'two')
          ..addField('pref_theme', 'dark')
          ..addField('pref_lang', 'en')
          ..addFileFromBytes(
            name: 'document',
            filename: 'test.pdf',
            bytes: utf8.encode('Hello World'),
            contentType: MediaType.parse('application/pdf'),
          );
      });

      response
        ..assertStatus(200)
        ..assertJsonContains({
          'name': 'test',
          'age': '25',
          'hobby': 'reading',
          'tags': ['one', 'two'],
          'preferences': {'pref_theme': 'dark', 'pref_lang': 'en'},
          'hasFile': true,
          'fileName': 'test.pdf',
          'fileSize': 11,
        });
    });

    test('Query Binding', () async {
      final engine = Engine();

      engine.get('/search', (ctx) async {
        final Map<String, dynamic> data = {};
        await ctx.shouldBindWith(data, queryBinding);
        ctx.json(data);
      });

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/search?q=test&page=1&sort=desc');

      response
        ..assertStatus(200)
        ..assertJsonContains({'q': 'test', 'page': '1', 'sort': 'desc'});
    });
  });
}
