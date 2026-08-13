import 'package:test/test.dart';

import 'bun_test_platform.dart';

void main() {
  test('example API serves through Bun', () async {
    await runBunExampleIntegration();
  });
}
