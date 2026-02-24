import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('resolveAuthAccountId prefers profile then user fields', () {
    final user = AuthUser(id: 'user-id', email: 'user@test.dev');
    expect(
      resolveAuthAccountId(
        {'sub': 'subject-id', 'id': 'profile-id'},
        user,
        fallbackId: () => 'fallback',
      ),
      equals('subject-id'),
    );
    expect(
      resolveAuthAccountId(
        {'id': 'profile-id'},
        user,
        fallbackId: () => 'fallback',
      ),
      equals('profile-id'),
    );
    expect(
      resolveAuthAccountId(
        <String, dynamic>{},
        user,
        fallbackId: () => 'fallback',
      ),
      equals('user-id'),
    );
  });

  test(
    'resolveAuthAccountId falls back when profile and user fields are empty',
    () {
      final user = AuthUser(id: '', email: null);
      expect(
        resolveAuthAccountId(
          <String, dynamic>{},
          user,
          fallbackId: () => 'fallback',
        ),
        equals('fallback'),
      );
    },
  );

  test('mergeAuthUser merges nullable fields, roles and attributes', () {
    final existing = AuthUser(
      id: 'u1',
      email: 'old@test.dev',
      name: 'Old',
      image: 'old.png',
      roles: const <String>['member'],
      attributes: const <String, dynamic>{'team': 'a', 'active': true},
    );
    final incoming = AuthUser(
      id: 'different-id-ignored',
      email: null,
      name: 'New',
      image: null,
      roles: const <String>['admin'],
      attributes: const <String, dynamic>{'active': false, 'locale': 'en'},
    );

    final merged = mergeAuthUser(existing, incoming);
    expect(merged.id, equals('u1'));
    expect(merged.email, equals('old@test.dev'));
    expect(merged.name, equals('New'));
    expect(merged.image, equals('old.png'));
    expect(merged.roles, equals(const <String>['admin']));
    expect(
      merged.attributes,
      equals(const <String, dynamic>{
        'team': 'a',
        'active': false,
        'locale': 'en',
      }),
    );
  });

  test('authUsersDiffer compares user identity payloads', () {
    final left = AuthUser(
      id: 'u1',
      email: 'user@test.dev',
      name: 'User',
      image: 'img.png',
      roles: const <String>['member'],
      attributes: const <String, dynamic>{'team': 'a'},
    );

    final same = AuthUser(
      id: 'u1',
      email: 'user@test.dev',
      name: 'User',
      image: 'img.png',
      roles: const <String>['member'],
      attributes: const <String, dynamic>{'team': 'a'},
    );

    final changed = AuthUser(
      id: 'u1',
      email: 'user@test.dev',
      name: 'User 2',
      image: 'img.png',
      roles: const <String>['member'],
      attributes: const <String, dynamic>{'team': 'a'},
    );

    expect(authUsersDiffer(left, same), isFalse);
    expect(authUsersDiffer(left, changed), isTrue);
  });

  test('authJwtClaimsForUser maps user fields to standard auth claims', () {
    final user = AuthUser(
      id: 'u1',
      email: 'user@test.dev',
      name: 'User',
      image: 'avatar.png',
      roles: const <String>['admin'],
      attributes: const <String, dynamic>{'team': 'core'},
    );

    expect(
      authJwtClaimsForUser(user),
      equals(<String, dynamic>{
        'sub': 'u1',
        'email': 'user@test.dev',
        'name': 'User',
        'image': 'avatar.png',
        'roles': <String>['admin'],
        'attributes': <String, dynamic>{'team': 'core'},
      }),
    );
  });

  test('authUserFromJwtClaims maps standard auth claims to user', () {
    final user = authUserFromJwtClaims(<String, dynamic>{
      'sub': 'u1',
      'email': 'user@test.dev',
      'name': 'User',
      'image': 'avatar.png',
      'roles': <String>['admin'],
      'attributes': <String, dynamic>{'team': 'core'},
    });

    expect(user.id, equals('u1'));
    expect(user.email, equals('user@test.dev'));
    expect(user.name, equals('User'));
    expect(user.image, equals('avatar.png'));
    expect(user.roles, equals(<String>['admin']));
    expect(user.attributes, equals(<String, dynamic>{'team': 'core'}));
  });
}
