import 'package:routed_io/routed_io.dart';
import 'package:test/test.dart';

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
