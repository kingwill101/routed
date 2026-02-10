import 'dart:convert';

import 'package:routed/routed.dart';
import 'package:routed/src/sessions/cookie_store.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  const cookieName = 'flash_session';

  SessionConfig makeSessionConfig() => SessionConfig(
    cookieName: cookieName,
    store: CookieStore(
      codecs: [
        SecureCookie(
          useEncryption: true,
          useSigning: true,
          key: SecureCookie.generateKey(),
        ),
      ],
    ),
  );

  String? cookieVal(TestResponse res, String key) => res.cookie(key)?.value;

  Future<TestResponse> withCookie(
    TestClient client,
    String path,
    TestResponse previous,
  ) async {
    final cookie = cookieVal(previous, cookieName);
    return client.get(
      path,
      headers: {
        if (cookie != null) HttpHeaders.cookieHeader: ['$cookieName=$cookie'],
      },
    );
  }

  group('FlashMessages', () {
    late Engine engine;
    late TestClient client;

    setUp(() {
      engine = testEngine(options: [withSessionConfig(makeSessionConfig())])
        ..get('/flash-single', (ctx) {
          ctx.flash('Hello!');
          return ctx.string('ok');
        })
        ..get('/flash-multiple', (ctx) {
          ctx.flash('First message');
          ctx.flash('Second message');
          ctx.flash('Error occurred', 'error');
          return ctx.string('ok');
        })
        ..get('/has-flash', (ctx) {
          final has = ctx.hasFlashMessages();
          return ctx.json({'has': has});
        })
        ..get('/get-flash', (ctx) {
          final messages = ctx.getFlashMessages();
          return ctx.json({'messages': messages});
        })
        ..get('/get-flash-with-categories', (ctx) {
          final messages = ctx.getFlashMessages(withCategories: true);
          return ctx.json({'messages': messages});
        })
        ..get('/get-flash-filtered', (ctx) {
          final messages = ctx.getFlashMessages(categoryFilter: ['error']);
          return ctx.json({'messages': messages});
        })
        ..get('/get-flash-filtered-with-categories', (ctx) {
          final messages = ctx.getFlashMessages(
            withCategories: true,
            categoryFilter: ['error'],
          );
          return ctx.json({'messages': messages});
        });
      client = TestClient(RoutedRequestHandler(engine));
    });

    tearDown(() => client.close());

    test('flash() stores a message that can be retrieved', () async {
      final flashRes = await client.get('/flash-single');
      flashRes.assertStatus(200);

      // Check flashes exist
      final hasRes = await withCookie(client, '/has-flash', flashRes);
      hasRes.assertStatus(200);
      hasRes.assertJsonPath('has', true);

      // Retrieve them
      final getRes = await withCookie(client, '/get-flash', flashRes);
      getRes.assertStatus(200);
      final getBody = jsonDecode(getRes.body);
      expect(getBody['messages'], ['Hello!']);
    });

    test(
      'getFlashMessages() retrieval removes flashes from session in same request',
      () async {
        // This test uses a single request to flash + retrieve, avoiding
        // cookie propagation issues with CookieStore.
        engine.get('/flash-and-check', (ctx) {
          ctx.flash('Temp message');
          expect(ctx.hasFlashMessages(), isTrue);

          final messages = ctx.getFlashMessages();
          // After retrieval, flashes should be removed from session
          expect(ctx.hasFlashMessages(), isFalse);
          return ctx.json({'messages': messages});
        });

        final res = await client.get('/flash-and-check');
        res.assertStatus(200);
        final body = jsonDecode(res.body);
        expect(body['messages'], ['Temp message']);
      },
    );

    test('flash() with default category', () async {
      final flashRes = await client.get('/flash-single');
      final catRes = await withCookie(
        client,
        '/get-flash-with-categories',
        flashRes,
      );
      catRes.assertStatus(200);
      // Should be [['message', 'Hello!']]
      final body = jsonDecode(catRes.body);
      expect(body['messages'], [
        ['message', 'Hello!'],
      ]);
    });

    test('multiple flash messages with mixed categories', () async {
      final flashRes = await client.get('/flash-multiple');

      // Get all without category filter
      final getRes = await withCookie(client, '/get-flash', flashRes);
      getRes.assertStatus(200);
      final body = jsonDecode(getRes.body);
      expect(body['messages'], [
        'First message',
        'Second message',
        'Error occurred',
      ]);
    });

    test('category filter returns only matching messages', () async {
      final flashRes = await client.get('/flash-multiple');

      final getRes = await withCookie(client, '/get-flash-filtered', flashRes);
      getRes.assertStatus(200);
      final body = jsonDecode(getRes.body);
      expect(body['messages'], ['Error occurred']);
    });

    test('category filter with categories returns tuples', () async {
      final flashRes = await client.get('/flash-multiple');

      final getRes = await withCookie(
        client,
        '/get-flash-filtered-with-categories',
        flashRes,
      );
      getRes.assertStatus(200);
      final body = jsonDecode(getRes.body);
      expect(body['messages'], [
        ['error', 'Error occurred'],
      ]);
    });

    test('hasFlashMessages() returns false when no flashes', () async {
      // Don't flash anything first — just check
      final hasRes = await client.get('/has-flash');
      hasRes.assertStatus(200);
      hasRes.assertJsonPath('has', false);
    });
  });
}
