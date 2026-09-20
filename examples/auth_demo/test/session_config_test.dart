import 'package:auth_demo/app.dart' show createEngine;
import 'package:auth_demo/jwt_app.dart' show createJwtEngine;
import 'package:routed/routed.dart';
import 'package:server_auth_ormed/server_auth_ormed.dart';
import 'package:test/test.dart';

void main() {
  test('local HTTP demo uses a non-secure session cookie', () async {
    final engine = await createEngine();
    addTearDown(engine.close);

    final config = engine.container.get<SessionConfig>();
    expect(config.secure, isFalse);
    expect(config.defaultOptions.secure, isFalse);
    expect(engine.container.get<AuthOptions>().store, isA<OrmAuthStore>());
  });

  test('JWT demo starts with the Ormed auth store', () async {
    final engine = await createJwtEngine();
    addTearDown(engine.close);

    expect(engine.container.get<AuthOptions>().store, isA<OrmAuthStore>());
  });
}
