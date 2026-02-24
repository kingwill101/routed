import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('public routed entrypoints do not re-export server_* packages', () {
    final prohibitedReExport = RegExp(
      r"^export\s+'package:server_(auth|contracts|data)/",
      multiLine: true,
    );

    final publicEntries = Directory('lib')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in publicEntries) {
      final content = file.readAsStringSync();
      expect(
        prohibitedReExport.hasMatch(content),
        isFalse,
        reason: 'Forbidden server_* re-export in ${file.path}',
      );
    }
  });

  test('routed barrel keeps only Config contract exposure', () {
    final routedBarrel = File('lib/routed.dart').readAsStringSync();

    expect(
      routedBarrel.contains("export 'src/contracts/contracts.dart';"),
      isFalse,
      reason: 'routed.dart must not re-export internal contracts barrel',
    );

    final configExport = RegExp(
      r"^export\s+'src/contracts/config/config\.dart'\s+show\s+Config;",
      multiLine: true,
    );

    expect(
      configExport.hasMatch(routedBarrel),
      isTrue,
      reason: 'routed.dart should expose Config for routed runtime consumers',
    );
  });
}
