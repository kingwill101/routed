import 'package:routed/src/utils/request_id.dart';
import 'package:test/test.dart';

void main() {
  test('RequestId.generate uses expected length and charset', () {
    final id = RequestId.generate(24);
    expect(id.length, equals(24));
    expect(RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id), isTrue);
  });

  test('RequestId.generateSecure uses expected length and charset', () {
    final secure = RequestId.generateSecure(24);
    expect(secure.length, equals(24));
    expect(RegExp(r'^[a-zA-Z0-9]+$').hasMatch(secure), isTrue);
  });

  test('secure and fast generators produce different IDs', () {
    final fast = RequestId.generate();
    final secure = RequestId.generateSecure();
    expect(fast, isNot(equals(secure)));
  });
}
