import 'dart:async';

import 'package:routed_runtime/routed_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('debugPrintWarning', () {
    tearDown(() {
      env.remove('ROUTED_MODE');
    });

    test('suppresses output in release mode', () {
      env['ROUTED_MODE'] = 'release';
      final output = _capturePrint(() {
        debugPrintWarning('hidden warning');
      });

      expect(output, isEmpty);
    });

    test('prints warning when not in release mode', () {
      final output = _capturePrint(() {
        debugPrintWarning('visible warning');
      });

      expect(output, contains('[Routed] WARNING: visible warning'));
      expect(
        output,
        contains('To disable this warning set the ROUTED_MODE environment variable to "release"'),
      );
    });
  });
}

String _capturePrint(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, String line) {
        lines.add(line);
      },
    ),
  );
  return lines.join('\n');
}
