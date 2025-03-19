import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/sessions/cookie_store.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('Session Tests', () {
    engineGroup(
      'Session operations',
      options: [
        withSessionConfig(SessionConfig(
          store: CookieStore(
            codecs: [
              SecureCookie(
                useEncryption: true,
                useSigning: true,
                key:
                    'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
              ),
            ],
          ),
          cookieName: 'routed_session',
        )),
        (engine) {
          engine.get('/session-test', (ctx) async {
            await ctx.setSession('test', 'value');
            ctx.string('ok');
          });

          engine.get('/write', (ctx) {
            ctx.setSession('key', 'persisted');
            ctx.string('written');
          });

          engine.get('/read', (ctx) async {
            final value = ctx.getSession<String>('key');
            ctx.string(value ?? '');
          });

          engine.get('/create-session', (ctx) {
            ctx.setSession('foo', 'bar');
            ctx.string('ok');
          });

          engine.get('/initial', (ctx) async {
            await ctx.setSession('foo', 'bar');
            await ctx.setSession('count', '42');
            ctx.string('ok');
          });

          engine.get('/verify', (ctx) async {
            assert(ctx.getSession<String>('foo') == "bar");
            print(ctx.getSession<String>('count'));
            assert(ctx.getSession<String>('count') == "42");
            ctx.string('ok');
          });

          engine.get('/regenerate', (ctx) {
            ctx.setSession('before', 'old');
            ctx.regenerateSession();
            ctx.setSession('after', 'new');
            ctx.string('regenerated');
          });

          engine.get('/destroy', (ctx) {
            ctx.setSession('data', 'secret');
            ctx.destroySession();
            ctx.string('destroyed');
          });

          engine.get('/session-utils', (ctx) async {
            await ctx.setSession('key1', 'value1');
            await ctx.setSession('key2', 'value2');

            assert(ctx.hasSession('key1') == true);
            assert(ctx.hasSession('nonexistent') == false);

            assert(ctx.getSessionOrDefault('key1', 'default') == 'value1');
            assert(
                ctx.getSessionOrDefault('nonexistent', 'default') == 'default');

            await ctx.removeSession('key1');
            assert(ctx.hasSession('key1') == false);

            expect(ctx.sessionData, containsPair('key2', 'value2'));

            await ctx.clearSession();
            assert(ctx.sessionData.isEmpty);

            assert(ctx.sessionAge >= 0);
            assert(ctx.sessionIdleTime >= 0);
            assert(ctx.sessionId.isNotEmpty);
            ctx.string('ok');
          });
        },
      ],
      define: (engine, client) {
        test('Session is available when configured in engine', () async {
          final response = await client.get('/session-test');
          response
            ..assertStatus(200)
            ..assertHasHeader(HttpHeaders.setCookieHeader)
            ..assertBodyEquals('ok');

          final cookie = response.headers[HttpHeaders.setCookieHeader]?.first;
          expect(cookie, isNotNull);
          expect(cookie, contains('routed_session='));
          expect(cookie, isNot(contains('"test":"value"')));
        });

        test('Session persists between requests', () async {
          final writeResponse = await client.get('/write');
          final cookie =
              writeResponse.headers[HttpHeaders.setCookieHeader]?.first;

          final readResponse = await client.get('/read', headers: {
            HttpHeaders.cookieHeader: [cookie!]
          });

          readResponse
            ..assertStatus(200)
            ..assertBodyEquals('persisted');
        });

        test('Session creation and storage', () async {
          final response = await client.get('/create-session');
          response.assertStatus(200);

          final cookie = response.headers[HttpHeaders.setCookieHeader]?.first;
          expect(cookie, isNotNull);
          expect(cookie, contains('routed_session='));
        });

        test('Session loading from cookie', () async {
          final initialResponse = await client.get('/initial');
          final cookie =
              initialResponse.headers[HttpHeaders.setCookieHeader]?.first;

          final verifyResponse = await client.get('/verify', headers: {
            HttpHeaders.cookieHeader: [cookie!]
          });
          verifyResponse.assertStatus(200);
        });

        test('Session can be regenerated', () async {
          final response = await client.get('/regenerate');
          response.assertStatus(200);

          final cookie = response.headers[HttpHeaders.setCookieHeader]?.first;
          expect(cookie, isNotNull);
          expect(cookie,
              isNot(contains('"id":"${engine.config.sessionConfig!.store}"')));
        });

        test('Session can be destroyed', () async {
          final response = await client.get('/destroy');
          response.assertStatus(200);

          final cookie = response.headers[HttpHeaders.setCookieHeader]?.first;
          expect(cookie, contains('Max-Age=0'));
        });

        test('Session utility methods work correctly', () async {
          final response = await client.get('/session-utils');
          response.assertStatus(200);
        });
      },
    );
  });
}
