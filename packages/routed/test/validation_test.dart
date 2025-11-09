import 'dart:convert';

import 'package:file/memory.dart';
import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

TestClient useClient(Engine engine) =>
    TestClient(RoutedRequestHandler(engine), mode: TransportMode.inMemory);

String synthUsername(
  int length, {
  required bool alphaOnly,
  bool allowEmpty = false,
}) {
  if (length <= 0) {
    return allowEmpty ? '' : 'a';
  }
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    if (alphaOnly) {
      buffer.writeCharCode('a'.codeUnitAt(0) + (i % 26));
    } else {
      buffer.write(i == 0 ? '1' : 'a');
    }
  }
  return buffer.toString();
}

void main() {
  group('Validation Tests', () {
    test('JSON Binding Validation', () async {
      final engine = Engine();

      engine.post('/json', (ctx) async {
        final data = <String, dynamic>{};

        await ctx.validate({
          'name': 'required',
          'age': 'required|numeric',
          'tags': 'required|array',
        });

        await ctx.bind(data);
        ctx.json(data);
      });

      final client = useClient(engine);

      final response = await client.postJson('/json', {
        'name': 'test',
        'age': 2511,
        'tags': ['one', 'two'],
      });

      response.assertStatus(200);
    });

    test('Form URL Encoded Binding Validation', () async {
      final engine = Engine();
      engine.post('/form', (ctx) async {
        final data = <String, dynamic>{};

        await ctx.validate({'name': 'required', 'age': 'required|numeric'});

        await ctx.bind(data);
        ctx.json(data);
      });

      final client = useClient(engine);

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

    test('Form validation handles varied payloads (property)', () async {
      String encodeForm(Map<String, String> fields) => fields.entries
          .map(
            (entry) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
          )
          .join('&');

      final generator = Gen.boolean().flatMap(
        (validName) => Gen.boolean().map(
          (validAge) => (nameValid: validName, ageValid: validAge),
        ),
      );

      final runner = PropertyTestRunner<({bool nameValid, bool ageValid})>(
        generator,
        (sample) async {
          final engine = Engine();
          engine.post('/form-prop', (ctx) async {
            final data = <String, dynamic>{};
            try {
              await ctx.validate({
                'name': 'required',
                'age': 'required|numeric',
              });
              await ctx.bind(data);
              ctx.json({'ok': true});
            } on ValidationError catch (e) {
              ctx.json({'errors': e.errors}, statusCode: HttpStatus.badRequest);
            }
          });

          final client = useClient(engine);
          final fields = <String, String>{};
          fields['name'] = sample.nameValid ? 'tester' : '';
          fields['age'] = sample.ageValid ? '36' : 'not-a-number';

          final response = await client.post(
            '/form-prop',
            encodeForm(fields),
            headers: {
              'Content-Type': ['application/x-www-form-urlencoded'],
            },
          );

          final expectSuccess = sample.nameValid && sample.ageValid;
          if (expectSuccess) {
            response
              ..assertStatus(HttpStatus.ok)
              ..assertJsonContains({'ok': true});
          } else {
            if (response.statusCode == HttpStatus.internalServerError) {
              fail('Unexpected 500 response: ${response.body}');
            }
            response.assertStatus(HttpStatus.badRequest);
            final json = response.json() as Map<String, dynamic>;
            final errors = (json['errors'] as Map).cast<String, dynamic>();
            if (!sample.nameValid) {
              expect(errors.keys, contains('name'));
            }
            if (!sample.ageValid) {
              expect(errors.keys, contains('age'));
            }
          }

          await client.close();
          await engine.close();
        },
        PropertyConfig(numTests: 30, seed: 20250304),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
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

    test('Query validation handles varied payloads (property)', () async {
      final generator = Gen.boolean().flatMap(
        (validQ) => Gen.boolean().flatMap(
          (validPage) => Gen.boolean().map(
            (validSort) =>
                (qValid: validQ, pageValid: validPage, sortValid: validSort),
          ),
        ),
      );

      final runner =
          PropertyTestRunner<({bool qValid, bool pageValid, bool sortValid})>(
            generator,
            (sample) async {
              final engine = Engine();
              engine.get('/search-prop', (ctx) async {
                final data = <String, dynamic>{};
                try {
                  await ctx.validate({
                    'q': 'required',
                    'page': 'required|numeric',
                    'sort': 'required',
                  });
                  await ctx.bind(data);
                  ctx.json({'ok': true});
                } on ValidationError catch (e) {
                  ctx.json({
                    'errors': e.errors,
                  }, statusCode: HttpStatus.badRequest);
                }
              });

              final client = useClient(engine);
              final query = <String, String>{};
              query['q'] = sample.qValid ? 'widgets' : '';
              query['page'] = sample.pageValid ? '2' : 'invalid';
              if (sample.sortValid) {
                query['sort'] = 'desc';
              }

              final uri = Uri(path: '/search-prop', queryParameters: query);
              final response = await client.get(uri.toString());

              final expectSuccess =
                  sample.qValid && sample.pageValid && sample.sortValid;
              if (expectSuccess) {
                response
                  ..assertStatus(HttpStatus.ok)
                  ..assertJsonContains({'ok': true});
              } else {
                if (response.statusCode == HttpStatus.internalServerError) {
                  fail('Unexpected 500 response: ${response.body}');
                }
                response.assertStatus(HttpStatus.badRequest);
                final errors = (response.json()['errors'] as Map)
                    .cast<String, dynamic>();
                if (!sample.qValid) {
                  expect(errors.keys, contains('q'));
                }
                if (!sample.pageValid) {
                  expect(errors.keys, contains('page'));
                }
                if (!sample.sortValid) {
                  expect(errors.keys, contains('sort'));
                }
              }

              await client.close();
              await engine.close();
            },
            PropertyConfig(numTests: 30, seed: 20250305),
          );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });

    test(
      'Multipart Form Binding Validation',
      timeout: const Timeout(Duration(seconds: 100)),
      () async {
        final fs = MemoryFileSystem();
        final engine = Engine(
          config: EngineConfig(
            fileSystem: fs,
            multipart: MultipartConfig(uploadDirectory: '/uploads'),
          ),
        );

        engine.post('/upload', (ctx) async {
          final data = <String, dynamic>{};

          await ctx.validate({
            'name': 'required',
            'age': 'required|numeric',
            'tags': 'required|array',
            'document': 'required|file',
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
              filename: 'test.pdf',
              bytes: utf8.encode('Hello World'),
              contentType: MediaType.parse('application/pdf'),
            );
        });

        response
          ..assertStatus(200)
          ..assertJsonContains({
            'name': 'test',
            'age': '255',
            'tags': ['one', 'two'],
          });
      },
    );

    test('Multipart validation handles varied payloads (property)', () async {
      final generator = Gen.boolean().flatMap(
        (validAge) => Gen.boolean().flatMap(
          (validTags) => Gen.boolean().map(
            (hasFile) =>
                (ageValid: validAge, tagsValid: validTags, hasFile: hasFile),
          ),
        ),
      );

      final runner =
          PropertyTestRunner<({bool ageValid, bool tagsValid, bool hasFile})>(
            generator,
            (sample) async {
              final engine = Engine(
                config: EngineConfig(
                  fileSystem: MemoryFileSystem(),
                  multipart: MultipartConfig(uploadDirectory: '/uploads'),
                ),
              );
              engine.post('/upload-prop', (ctx) async {
                final data = <String, dynamic>{};
                try {
                  await ctx.validate({
                    'name': 'required',
                    'age': 'required|numeric',
                    'tags': 'required|array',
                    'document': 'required|file',
                  });
                  await ctx.bind(data);
                  ctx.json({'ok': true});
                } on ValidationError catch (e) {
                  ctx.json({
                    'errors': e.errors,
                  }, statusCode: HttpStatus.badRequest);
                } catch (e) {
                  ctx.json({
                    'errors': {
                      '_': ['Unexpected: ${e.toString()}'],
                    },
                  }, statusCode: HttpStatus.badRequest);
                }
              });

              final client = useClient(engine);
              final response = await client.multipart('/upload-prop', (
                request,
              ) {
                request.addField('name', 'tester');
                request.addField('age', sample.ageValid ? '45' : 'wrong');
                if (sample.tagsValid) {
                  request
                    ..addField('tags', 'one')
                    ..addField('tags', 'two');
                } else {
                  request.addField('tags', 'oops');
                }
                if (sample.hasFile) {
                  request.addFileFromBytes(
                    name: 'document',
                    filename: 'contract.pdf',
                    bytes: utf8.encode('hello'),
                    contentType: MediaType.parse('application/pdf'),
                  );
                }
              });

              final expectSuccess =
                  sample.ageValid && sample.tagsValid && sample.hasFile;
              if (expectSuccess) {
                response
                  ..assertStatus(HttpStatus.ok)
                  ..assertJsonContains({'ok': true});
              } else {
                if (response.statusCode == HttpStatus.internalServerError) {
                  fail('Unexpected 500 response: ${response.body}');
                }
                response.assertStatus(HttpStatus.badRequest);
                final errors = (response.json()['errors'] as Map)
                    .cast<String, dynamic>();
                if (!sample.ageValid) {
                  expect(
                    errors.keys,
                    contains('age'),
                    reason: 'Errors: $errors',
                  );
                }
                if (!sample.tagsValid) {
                  expect(
                    errors.keys,
                    contains('tags'),
                    reason: 'Errors: $errors',
                  );
                }
                if (!sample.hasFile) {
                  expect(
                    errors.keys,
                    contains('document'),
                    reason: 'Errors: $errors',
                  );
                }
              }

              await client.close();
              await engine.close();
            },
            PropertyConfig(numTests: 25, seed: 20250306),
          );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });

    test('Validation Error Handling', () async {
      final engine = Engine();

      engine.post('/json2', (ctx) async {
        final data = <String, dynamic>{};

        try {
          await ctx.validate({
            'name': 'required',
            'age': 'required|numeric',
            'tags': 'required|array',
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
        'tags': 'not an array', // Invalid tags (not an array)
      });

      response
        ..assertStatus(200)
        ..assertJsonContains({
          'errors': {
            'age': ['This field must be a number.'],
            'tags': ['This field must be an array.'],
          },
        });
    });

    test(
      'Validation accumulates errors and supports custom messages',
      () async {
        final engine = Engine();

        engine.post('/multi', (ctx) async {
          try {
            await ctx.validate(
              {'username': 'required|min:5|alpha'},
              messages: {
                'username.min': 'Username must be at least five characters.',
                'username.alpha': 'Username may only contain letters.',
              },
            );
            ctx.string('ok');
          } on ValidationError catch (e) {
            ctx.json({'errors': e.errors});
          }
        });

        final client = useClient(engine);
        final response = await client.postJson('/multi', {'username': '12'});

        response
          ..assertStatus(200)
          ..assertJsonContains({
            'errors': {
              'username': [
                'Username must be at least five characters.',
                'Username may only contain letters.',
              ],
            },
          });
      },
    );

    test('Validation custom messages align with failures (property)', () async {
      final generator = Gen.integer(min: 1, max: 8).flatMap(
        (length) => Gen.boolean().map(
          (alphaOnly) => (length: length, alphaOnly: alphaOnly),
        ),
      );

      final runner = PropertyTestRunner<({int length, bool alphaOnly})>(
        generator,
        (sample) async {
          final engine = Engine();
          engine.post('/multi-prop', (ctx) async {
            try {
              await ctx.validate(
                {'username': 'required|min:5|alpha'},
                messages: {
                  'username.min': 'Username must be at least five characters.',
                  'username.alpha': 'Username may only contain letters.',
                },
              );
              ctx.string('ok');
            } on ValidationError catch (e) {
              ctx.json({'errors': e.errors});
            }
          });

          final client = useClient(engine);
          final value = synthUsername(
            sample.length,
            alphaOnly: sample.alphaOnly,
          );
          final response = await client.postJson('/multi-prop', {
            'username': value,
          });

          final meetsMin = value.length >= 5;
          final isAlpha = sample.alphaOnly;
          final shouldPass = meetsMin && isAlpha;

          if (shouldPass) {
            response
              ..assertStatus(HttpStatus.ok)
              ..assertBodyEquals('ok');
          } else {
            if (response.statusCode == HttpStatus.internalServerError) {
              fail('Unexpected 500 response: ${response.body}');
            }
            response.assertStatus(HttpStatus.ok);
            final json = response.json() as Map<String, dynamic>;
            final errors = (json['errors'] as Map).cast<String, dynamic>();
            expect(errors.keys, contains('username'));
            final messages = (errors['username'] as List).cast<String>();
            final expected = <String>{};
            if (!meetsMin) {
              expected.add('Username must be at least five characters.');
            }
            if (!isAlpha) {
              expected.add('Username may only contain letters.');
            }
            expect(messages.toSet(), equals(expected));
            expect(messages.length, equals(expected.length));
          }

          await client.close();
          await engine.close();
        },
        PropertyConfig(numTests: 35, seed: 20250307),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });

    test('Validation bail stops after first failure', () async {
      final engine = Engine();

      engine.post('/bail', (ctx) async {
        try {
          await ctx.validate(
            {'username': 'required|min:5|alpha'},
            bail: true,
            messages: {
              'username.min': 'Too short',
              'username.alpha': 'Letters only',
            },
          );
          ctx.string('ok');
        } on ValidationError catch (e) {
          ctx.json({'errors': e.errors});
        }
      });

      final client = useClient(engine);
      final response = await client.postJson('/bail', {'username': '12'});

      response
        ..assertStatus(200)
        ..assertJsonContains({
          'errors': {
            'username': ['Too short'],
          },
        });
    });

    test('Validation bail reports only first error (property)', () async {
      final generator = Gen.integer(min: 0, max: 8).flatMap(
        (length) => Gen.boolean().map(
          (alphaOnly) => (length: length, alphaOnly: alphaOnly),
        ),
      );

      final runner = PropertyTestRunner<({int length, bool alphaOnly})>(
        generator,
        (sample) async {
          final engine = Engine();
          engine.post('/bail-prop', (ctx) async {
            try {
              await ctx.validate(
                {'username': 'required|min:5|alpha'},
                bail: true,
                messages: {
                  'username.min': 'Too short',
                  'username.alpha': 'Letters only',
                },
              );
              ctx.string('ok');
            } on ValidationError catch (e) {
              ctx.json({'errors': e.errors});
            }
          });

          final client = useClient(engine);
          final value = synthUsername(
            sample.length,
            alphaOnly: sample.alphaOnly,
            allowEmpty: true,
          );

          final response = await client.postJson('/bail-prop', {
            'username': value,
          });

          final isRequiredValid = value.isNotEmpty;
          final meetsMin = value.length >= 5;
          final isAlpha = value.isEmpty ? true : sample.alphaOnly;

          if (isRequiredValid && meetsMin && isAlpha) {
            response
              ..assertStatus(HttpStatus.ok)
              ..assertBodyEquals('ok');
          } else {
            if (response.statusCode == HttpStatus.internalServerError) {
              fail('Unexpected 500 response: ${response.body}');
            }
            response.assertStatus(HttpStatus.ok);
            final json = response.json() as Map<String, dynamic>;
            final errors = (json['errors'] as Map).cast<String, dynamic>();
            expect(errors.keys, contains('username'));
            final messages = (errors['username'] as List).cast<String>();

            expect(messages.length, equals(1));

            final expectedMessage = !isRequiredValid
                ? 'This field is required.'
                : (!meetsMin ? 'Too short' : 'Letters only');

            expect(messages.single, equals(expectedMessage));
          }

          await client.close();
          await engine.close();
        },
        PropertyConfig(numTests: 40, seed: 20250308),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });

    test('JSON validation handles varied payloads (property)', () async {
      final generator = Gen.boolean().flatMap(
        (validName) => Gen.boolean().flatMap(
          (validAge) => Gen.boolean().map(
            (validTags) => (
              nameValid: validName,
              ageValid: validAge,
              tagsValid: validTags,
            ),
          ),
        ),
      );

      final runner =
          PropertyTestRunner<({bool nameValid, bool ageValid, bool tagsValid})>(
            generator,
            (sample) async {
              final engine = Engine();
              engine.post('/json-prop', (ctx) async {
                final data = <String, dynamic>{};
                try {
                  await ctx.validate({
                    'name': 'required',
                    'age': 'required|numeric',
                    'tags': 'required|array',
                  });
                  await ctx.bind(data);
                  ctx.json({'ok': true});
                } on ValidationError catch (e) {
                  ctx.json({
                    'errors': e.errors,
                  }, statusCode: HttpStatus.badRequest);
                }
              });

              final client = useClient(engine);
              final payload = <String, dynamic>{};
              if (sample.nameValid) {
                payload['name'] = 'test-user';
              }
              if (sample.ageValid) {
                payload['age'] = 42;
              } else {
                payload['age'] = 'invalid';
              }
              if (sample.tagsValid) {
                payload['tags'] = ['one', 'two'];
              } else {
                payload['tags'] = 'oops';
              }

              final response = await client.postJson('/json-prop', payload);

              final expectSuccess =
                  sample.nameValid && sample.ageValid && sample.tagsValid;

              if (expectSuccess) {
                response
                  ..assertStatus(HttpStatus.ok)
                  ..assertJsonContains({'ok': true});
              } else {
                response.assertStatus(HttpStatus.badRequest);
                final json = response.json() as Map<String, dynamic>;
                final errors = (json['errors'] as Map).cast<String, dynamic>();
                if (!sample.nameValid) {
                  expect(errors.keys, contains('name'));
                }
                if (!sample.ageValid) {
                  expect(errors.keys, contains('age'));
                }
                if (!sample.tagsValid) {
                  expect(errors.keys, contains('tags'));
                }
              }

              await client.close();
              await engine.close();
            },
            PropertyConfig(numTests: 40, seed: 20250302),
          );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });
  });
}
