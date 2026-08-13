import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/netlify.dart';
import 'package:routed_node/vercel.dart';
import 'package:test/test.dart';

void main() {
  test('Fetch host capabilities cover shared deployment targets', () {
    expect(cloudflareCapabilities.streaming, isTrue);
    expect(vercelCapabilities.bufferedResponses, isTrue);
    expect(netlifyCapabilities.fileSystem, isTrue);
    expect(cloudflareCapabilities.webSocket, isTrue);
    expect(vercelCapabilities.webSocket, isFalse);
    expect(netlifyCapabilities.webSocket, isFalse);
  });

  test(
    'portable exchange supports request bodies and multi-value headers',
    () async {
      final engine = Engine(providers: Engine.defaultProviders);
      engine.post('/echo', (ctx) async {
        final body = await ctx.request.body();
        return ctx.json({'body': body});
      });
      await engine.initialize();
      addTearDown(engine.close);

      final response = await engine.handlePortable(
        PortableRequest(
          method: 'POST',
          uri: Uri.parse('https://example.test/echo?mode=full'),
          headers: PortableHeaders({
            'content-type': ['application/json'],
            'x-test': ['one', 'two'],
          }),
          body: Stream.value(utf8.encode('{"ok":true}')),
        ),
      );

      expect(response.statusCode, 200);
      expect(response.bodyText, contains('{"body":"{\\"ok\\":true}"}'));
    },
  );
}
