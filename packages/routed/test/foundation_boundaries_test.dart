import 'dart:io';
import 'package:test/test.dart';
import 'package:routed/routed.dart';

void main() {
  group('PR A: foundation boundaries', () {
    test('Engine and EngineContext remain', () {
      final engine = Engine();
      expect(engine, isA<Engine>());
      // handler signature still valid
      Handler h = (ctx) => ctx.string('ok');
      expect(h, isA<Handler>());
      Middleware m = (ctx, next) async => await next();
      expect(m, isA<Middleware>());
    });

    test('typed ContextKey read/write', () async {
      // RouteMetadata and ServiceResolver smoke tests
      final meta = RouteMetadata();
      const rk = RouteMetadataKey<String>('routed.test');
      meta.set(rk, 'hello');
      expect(meta.get(rk), 'hello');
      expect(meta.contains(rk), isTrue);
      meta.remove(rk);
      expect(meta.contains(rk), isFalse);

      final resolver = Container();
      expect(resolver, isA<ServiceResolver>());
      resolver.singleton<String>((_) async => 'hello');
      expect(resolver.has<String>(), isTrue);
      expect(await resolver.make<String>(), 'hello');
      // sync get after singleton cached? Need instance path via make then get
      // get requires instance binding - make caches instance for singleton
      expect(resolver.get<String>(), 'hello');
    });

    test('transport abstractions are importable', () {
      // just ensure types exist
      expect(ServerOptions, isNotNull);
    });

    test('routed barrel does not re-export server_* packages', () {
      // when running from workspace root, path is packages/routed/lib/routed.dart
      final candidates = [File('lib/routed.dart'), File('packages/routed/lib/routed.dart')];
      File? barrel;
      for (final f in candidates) {
        if (f.existsSync()) barrel = f;
      }
      expect(barrel, isNotNull);
      final content = barrel!.readAsStringSync();
      expect(content.contains("package:server_"), isFalse);
    });
  });
}
