import 'package:auth_demo/app.dart' show createEngine;
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test('local HTTP demo uses a non-secure session cookie', () async {
    final engine = await createEngine();
    addTearDown(engine.close);

    final config = engine.container.get<SessionConfig>();
    expect(config.secure, isFalse);
    expect(config.defaultOptions.secure, isFalse);
  });
}
