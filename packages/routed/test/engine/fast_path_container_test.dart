import 'package:routed/routed.dart';
import 'package:routed/src/engine/request_scope.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  test(
    'fast-path mode uses read-only container and stores RequestScope',
    () async {
      final engine = Engine(
        config: EngineConfig(
          features: const EngineFeatures(enableRequestContainerFastPath: true),
        ),
      );

      RequestScope? capturedScope;
      bool? scopeMatches;
      Object? mutationError;

      engine.get('/scope', (ctx) {
        final scope = requestScopeExpando[ctx.request.httpRequest];
        capturedScope = scope;
        scopeMatches = identical(scope?.context, ctx);

        try {
          ctx.container.instance<String>('nope');
        } catch (err) {
          mutationError = err;
        }

        return ctx.string('ok');
      });

      final client = TestClient.inMemory(RoutedRequestHandler(engine));
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get('/scope');
      response
        ..assertStatus(200)
        ..assertBodyEquals('ok');

      expect(capturedScope, isNotNull);
      expect(scopeMatches, isTrue);
      expect(mutationError, isA<StateError>());
    },
  );
}
