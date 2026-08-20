import 'package:property_testing/property_testing.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

const _hashKey = '0123456789abcdef0123456789abcdef';

void main() {
  test('hostile phone payloads stay inside bounded JSON errors', () async {
    final plugin = PhoneNumberPlugin<EngineContext>(
      store: InMemoryAuthPhoneNumberStore(),
      codeHashKey: _hashKey,
      generateCode: (_) => '123456',
      sendCode: (_) {},
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const <AuthProvider>[],
        plugins: <AuthServerPlugin<EngineContext>>[plugin],
      ),
    );
    final engine = testEngine(
      config: EngineConfig(
        security: const EngineSecurityFeatures(csrfProtection: false),
      ),
    );
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    final inputs = Gen.frequency<String>(<(int, Generator<String>)>[
      (7, Chaos.string(minLength: 0, maxLength: 1024)),
      (
        3,
        Gen.oneOf<String>(<String>[
          '+1\r\nSet-Cookie: auth=attacker',
          '+1\u0000Authorization: Bearer token',
          '<script>alert(1)</script>',
          "' OR '1'='1",
          '+${'9' * 8192}',
        ]),
      ),
    ]);
    final runner = PropertyTestRunner<String>(inputs, (input) async {
      if (const AuthE164PhoneNumberPolicy().normalize(input) != null) return;
      final response = await client.postJson(
        '/auth/phone-number/send-code',
        <String, dynamic>{'phoneNumber': input},
      );
      response.assertStatus(HttpStatus.badRequest);
      expect(response.body.length, lessThan(256));
      if (input.isNotEmpty && input.length < 128) {
        expect(response.body, isNot(contains(input)));
      }
      expect(response.body, contains('invalid_phone_number'));
    }, PropertyConfig(numTests: 500, seed: 20260822));

    final result = await runner.run();
    expect(result.success, isTrue, reason: '${result.error}');
  });
}
