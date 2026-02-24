import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('resolveAuthProviderById finds provider by exact id', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      AuthProvider(id: 'github', name: 'GitHub', type: AuthProviderType.oauth),
    ];

    expect(resolveAuthProviderById(providers, 'google')?.name, 'Google');
    expect(resolveAuthProviderById(providers, 'missing'), isNull);
    expect(resolveAuthProviderById(providers, '   '), isNull);
  });

  test('authProviderSummaries returns stable provider payloads', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ];

    expect(
      authProviderSummaries(providers),
      equals(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'google', 'name': 'Google', 'type': 'oidc'},
      ]),
    );
  });

  test('mergeAuthProvidersById appends only missing providers', () {
    final base = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ];
    final additional = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google 2', type: AuthProviderType.oidc),
      AuthProvider(id: 'github', name: 'GitHub', type: AuthProviderType.oauth),
    ];

    final merged = mergeAuthProvidersById(base, additional);

    expect(
      merged.map((provider) => provider.id),
      equals(<String>['google', 'github']),
    );
    expect(merged.first.name, equals('Google'));
  });
}
