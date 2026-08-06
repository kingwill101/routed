import 'package:test/test.dart';
import 'package:routed_io/routed_io.dart';

void main() {
  group('RoutedIO', () {
    test('serveIo is exported', () {
      expect(serveIo, isNotNull);
    });

    test('serveSecureIo is exported', () {
      expect(serveSecureIo, isNotNull);
    });
  });
}
