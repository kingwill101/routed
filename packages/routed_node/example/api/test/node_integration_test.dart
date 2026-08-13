import 'package:test/test.dart';

import 'node_test_platform.dart';

void main() {
  test('example API serves through the Node listener', () async {
    await runNodeExampleIntegration();
  });
}
