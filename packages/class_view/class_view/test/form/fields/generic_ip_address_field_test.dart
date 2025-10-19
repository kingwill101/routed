import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

void main() {
  // Debug test to help diagnose issues
  test('debug test', () {
    final f = GenericIPAddressField(required: false);

    // Test empty input for optional field
    final emptyResult = f.toDart('');
    print('Debug - Empty string result: $emptyResult');

    final nullResult = f.toDart(null);
    print('Debug - Null result: $nullResult');

    // Test invalid input
    try {
      f.toDart('invalid-ip');
      fail('Expected ValidationError');
    } catch (e) {
      print('Debug - Error for invalid IP: $e');
    }
  });

  test('invalid arguments', () {
    expect(
      () => GenericIPAddressField(protocol: 'hamster'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('generic ip address validation', () {
    final f = GenericIPAddressField();

    // Test required validation
    expect(
      () => f.toDart(''),
      throwsA(containsErrorMessage('This field is required')),
    );

    expect(
      () => f.toDart(null),
      throwsA(containsErrorMessage('This field is required')),
    );

    // Test valid values
    expect(f.toDart(' 127.0.0.1 '), equals('127.0.0.1'));
    expect(
      f.toDart(' fe80::223:6cff:fe8a:2e8a '),
      equals('fe80::223:6cff:fe8a:2e8a'),
    );
    expect(
      f.toDart(' 2a02::223:6cff:fe8a:2e8a '),
      equals('2a02::223:6cff:fe8a:2e8a'),
    );

    // Test invalid values
    expect(
      () => f.toDart('foo'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    expect(
      () => f.toDart('127.0.0.'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    expect(
      () => f.toDart('1.2.3.4.5'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    expect(
      () => f.toDart('256.125.1.5'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    // Test invalid IPv6 addresses
    expect(
      () => f.toDart('12345:2:3:4'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    expect(
      () => f.toDart('1::2:3::4'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    expect(
      () => f.toDart('foo::223:6cff:fe8a:2e8a'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    expect(
      () => f.toDart('1::2:3:4:5:6:7:8'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );

    expect(
      () => f.toDart('1:2'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );
  });

  test('ipv4 only validation', () {
    final f = GenericIPAddressField(protocol: 'IPv4');

    // Test required validation
    expect(
      () => f.toDart(''),
      throwsA(containsErrorMessage('This field is required')),
    );

    expect(
      () => f.toDart(null),
      throwsA(containsErrorMessage('This field is required')),
    );

    // Test valid IPv4
    expect(f.toDart(' 127.0.0.1 '), equals('127.0.0.1'));

    // Test invalid values
    expect(
      () => f.toDart('foo'),
      throwsA(containsErrorMessage('Enter a valid IPv4 address')),
    );

    expect(
      () => f.toDart('127.0.0.'),
      throwsA(containsErrorMessage('Enter a valid IPv4 address')),
    );

    expect(
      () => f.toDart('1.2.3.4.5'),
      throwsA(containsErrorMessage('Enter a valid IPv4 address')),
    );

    expect(
      () => f.toDart('256.125.1.5'),
      throwsA(containsErrorMessage('Enter a valid IPv4 address')),
    );

    expect(
      () => f.toDart('fe80::223:6cff:fe8a:2e8a'),
      throwsA(containsErrorMessage('Enter a valid IPv4 address')),
    );

    expect(
      () => f.toDart('2a02::223:6cff:fe8a:2e8a'),
      throwsA(containsErrorMessage('Enter a valid IPv4 address')),
    );
  });

  test('ipv6 only validation', () {
    final f = GenericIPAddressField(protocol: 'IPv6');

    // Test required validation
    expect(
      () => f.toDart(''),
      throwsA(containsErrorMessage('This field is required')),
    );

    expect(
      () => f.toDart(null),
      throwsA(containsErrorMessage('This field is required')),
    );

    // Test valid IPv6
    expect(
      f.toDart(' fe80::223:6cff:fe8a:2e8a '),
      equals('fe80::223:6cff:fe8a:2e8a'),
    );
    expect(
      f.toDart(' 2a02::223:6cff:fe8a:2e8a '),
      equals('2a02::223:6cff:fe8a:2e8a'),
    );

    // Test invalid values
    expect(
      () => f.toDart('127.0.0.1'),
      throwsA(containsErrorMessage('This is not a valid IPv6 address')),
    );

    expect(
      () => f.toDart('foo'),
      throwsA(containsErrorMessage('This is not a valid IPv6 address')),
    );

    expect(
      () => f.toDart('127.0.0.'),
      throwsA(containsErrorMessage('This is not a valid IPv6 address')),
    );

    expect(
      () => f.toDart('1.2.3.4.5'),
      throwsA(containsErrorMessage('This is not a valid IPv6 address')),
    );

    expect(
      () => f.toDart('256.125.1.5'),
      throwsA(containsErrorMessage('This is not a valid IPv6 address')),
    );

    expect(
      () => f.toDart('12345:2:3:4'),
      throwsA(containsErrorMessage('This is not a valid IPv6 address')),
    );
  });

  test('max length validation', () {
    // Valid IPv4-mapped IPv6 address, len 45
    const addr = '0000:0000:0000:0000:0000:ffff:192.168.100.228';
    final f = GenericIPAddressField(maxLength: addr.length);
    expect(f.toDart(addr), isNotNull);

    // Test max length validation
    final f2 = GenericIPAddressField(maxLength: addr.length - 1);
    expect(() => f2.toDart('x' * addr.length), throwsA(isA<ValidationError>()));
  });

  test('optional field validation', () {
    final f = GenericIPAddressField(required: false);

    // Optional fields can be empty
    expect(f.toDart(''), isNull);
    expect(f.toDart(null), isNull);

    // But still need to be valid if provided
    expect(
      () => f.toDart('foo'),
      throwsA(containsErrorMessage('Enter a valid IPv4 or IPv6 address')),
    );
  });
}
