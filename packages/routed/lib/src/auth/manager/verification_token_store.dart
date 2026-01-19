import 'dart:async';

import 'package:routed/src/auth/models.dart';


abstract class AuthVerificationTokenStore {
  FutureOr<void> save(AuthVerificationToken token);

  FutureOr<AuthVerificationToken?> use(String identifier, String token);

  FutureOr<void> delete(String identifier);
}

class InMemoryAuthVerificationTokenStore implements AuthVerificationTokenStore {
  final Map<String, AuthVerificationToken> _tokens =
      <String, AuthVerificationToken>{};

  @override
  Future<void> save(AuthVerificationToken token) async {
    _tokens['${token.identifier}::${token.token}'] = token;
  }

  @override
  Future<AuthVerificationToken?> use(String identifier, String token) async {
    final key = '$identifier::$token';
    final record = _tokens.remove(key);
    if (record == null) return null;
    if (DateTime.now().isAfter(record.expiresAt)) {
      return null;
    }
    return record;
  }

  @override
  Future<void> delete(String identifier) async {
    _tokens.removeWhere((key, _) => key.startsWith('$identifier::'));
  }
}
