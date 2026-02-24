import 'dart:io';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('authErrorStatusCode maps known auth error codes', () {
    expect(authErrorStatusCode('unknown_provider'), HttpStatus.notFound);
    expect(authErrorStatusCode('invalid_csrf'), HttpStatus.forbidden);
    expect(
      authErrorStatusCode('method_not_allowed'),
      HttpStatus.methodNotAllowed,
    );
  });

  test('authErrorStatusCode defaults to bad request', () {
    expect(authErrorStatusCode('missing_email'), HttpStatus.badRequest);
    expect(authErrorStatusCode('anything_else'), HttpStatus.badRequest);
  });
}
