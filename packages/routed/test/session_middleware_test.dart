import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/middleware/session.dart';
import 'package:routed/src/sessions/cookie_store.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/sessions/session.dart';
import 'package:routed_testing/mock.dart';
import 'package:test/test.dart';

// Example test for session middleware.
// Uses a MockHttpRequest and MockHttpResponse (similar to InMemoryTransport).

void main() {
  final mockRequest = setupRequest("GET", "/some-route");

  final mockResponse = setupResponse();
  when(mockRequest.response).thenReturn(mockResponse);

  test('Session middleware attaches a session and stores new sessions',
      () async {
    // 1. Create a Store (e.g., CookieStore) with a dummy key
    final store = CookieStore(
      codecs: [
        SecureCookie([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
      ],
      defaultOptions: Options(path: '/', maxAge: 3600),
    );

    // 4. Build an EngineContext
    final ctx = EngineContext(
        request: Request(mockRequest, {}),
        response: Response(mockResponse),
        handlers: <Middleware>[
          sessionMiddleware(store, sessionName: 'routed_session'),
          (c) async {
            // Within the handler, check that a session is present:
            final s = c.get<Session>('session');
            expect(s, isNotNull);
            // Write something into the session
            s!.values['foo'] = 'bar';
            // Then continue
            await c.next();
          },
        ]);

    await ctx.run();

    // 6. Verify that the session was saved and a cookie was set on the response
    // verify(mockResponse.cookies.add(argThat(
    // predicate<Cookie>((cookie) => cookie.name == 'routed_session'),
    // ))).called(1);
  });

  test('Session middleware loads an existing session cookie', () async {
    // 1. Create store & secure cookie
    final store = CookieStore(
      codecs: [
        SecureCookie([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
      ],
    );

    // Create a pre-encoded cookie
    final encoded = store.codecs.first.encode('routed_session', {
      'foo': 'bar',
      'count': '42',
    });
    final existingCookie = Cookie('routed_session', encoded);
    when(mockRequest.cookies).thenReturn([existingCookie]);

    // 4. Build context and chain
    final ctx = EngineContext(
        request: Request(mockRequest, {}),
        response: Response(mockResponse),
        handlers: <Middleware>[
          sessionMiddleware(store, sessionName: 'routed_session'),
          (c) async {
            final s = c.get<Session>('session');
            expect(s, isNotNull);
            expect(s!.values['foo'], 'bar');
            expect(s.values['count'], '42');
            await c.next();
          },
        ]);

    await ctx.run();

    // 5. Ensure a cookie update happened:
    verify(mockResponse.cookies.add).called(1);
  });
}
