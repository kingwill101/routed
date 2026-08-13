import 'package:test/test.dart';

import 'node_fetch.dart';

void main() {
  test('Node HTTP listener serves a real request', () async {
    await runNodeFetchIntegration();
  });
}
