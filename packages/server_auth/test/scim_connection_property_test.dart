import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: '
    '${result.error ?? 'unknown failure'}; input=${result.failingInput}; '
    'seed=${result.seed}';

void main() {
  test(
    'hostile management identifiers fail closed without reflection',
    () async {
      final generator = Gen.frequency<String>([
        (7, Chaos.string(minLength: 0, maxLength: 400)),
        (
          3,
          Gen.oneOf<String>([
            '',
            'valid-identifier',
            'value\r\nset-cookie: leaked=1',
            'value\u0000suffix',
            'a' * 257,
            '   padded   ',
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(generator, (candidate) {
        try {
          final binding = AuthScimConnectionBinding(
            tenantId: candidate,
            organizationId: 'organization-a',
          );
          expect(binding.tenantId, binding.tenantId.trim());
          expect(binding.tenantId.length, lessThanOrEqualTo(256));
          expect(
            binding.tenantId.codeUnits,
            everyElement(allOf(greaterThanOrEqualTo(0x20), isNot(0x7f))),
          );
        } on ArgumentError catch (error) {
          expect(error.toString(), isNot(contains('set-cookie')));
          expect(error.toString(), isNot(contains('leaked')));
        }
      }, PropertyConfig(numTests: 600, seed: 20260824));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test('arbitrary bearer strings cannot cross digest lookup', () async {
    final store = InMemoryAuthScimConnectionStore();
    final created = await store.createConnection(_transaction());
    final generator = Gen.frequency<String>([
      (8, Chaos.string(minLength: 0, maxLength: 600)),
      (
        2,
        Gen.oneOf<String>([
          created.credential.secretDigest,
          'secret',
          'secret\r\nAuthorization: Bearer leaked',
          'a' * 4096,
        ]),
      ),
    ]);
    final runner = PropertyTestRunner<String>(generator, (candidate) async {
      final identity =
          await AuthScimManagedBearerTokenResolver<Object>(
            store: store,
            clock: () => _now,
          ).resolve(
            AuthScimBearerTokenRequest<Object>(
              context: Object(),
              token: candidate,
            ),
          );
      expect(identity, isNull);
    }, PropertyConfig(numTests: 500, seed: 20260825));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test('generated scope subsets never escalate connection grants', () async {
    final generator = Gen.integer(min: 0, max: 31);
    final runner = PropertyTestRunner<int>(generator, (mask) async {
      final requested = <AuthScimScope>{
        for (var index = 0; index < AuthScimScope.values.length; index++)
          if (mask & (1 << index) != 0) AuthScimScope.values[index],
      };
      const granted = <AuthScimScope>{AuthScimScope.usersWrite};
      final allowed = authScimScopesAllow(granted, requested);
      if (allowed) {
        expect(
          requested,
          everyElement(
            anyOf(AuthScimScope.usersRead, AuthScimScope.usersWrite),
          ),
        );
      }
    }, PropertyConfig(numTests: 256, seed: 20260826));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test('catalog page bounds reject unbounded hostile values', () async {
    final generator = Gen.integer(min: -10000000, max: 10000000);
    final runner = PropertyTestRunner<int>(generator, (value) {
      try {
        final query = AuthScimConnectionCatalogQuery(
          binding: AuthScimConnectionBinding(
            tenantId: 'tenant-a',
            organizationId: 'organization-a',
          ),
          limit: value,
          offset: value,
        );
        expect(query.limit, inInclusiveRange(1, 200));
        expect(query.offset, inInclusiveRange(0, 1000000));
      } on ArgumentError {
        expect(value < 1 || value > 200, isTrue);
      }
    }, PropertyConfig(numTests: 500, seed: 20260827));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });
}

final DateTime _now = DateTime.utc(2030);

AuthScimCreateConnectionTransaction _transaction() {
  final connection = AuthScimManagedConnection(
    id: 'connection-a',
    tenantId: 'tenant-a',
    organizationId: 'organization-a',
    provisioningDomainId: 'directory-a',
    subjectId: 'user-a',
    name: 'Directory',
    scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
    createdAt: _now,
    updatedAt: _now,
  );
  return AuthScimCreateConnectionTransaction(
    connection: connection,
    credential: AuthScimCredentialRecord(
      id: 'credential-a',
      connectionId: connection.id,
      tenantId: connection.tenantId,
      organizationId: connection.organizationId,
      name: 'Primary',
      keyPrefix: 'rscim.cred',
      secretDigest: 'a' * 64,
      scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
      createdAt: _now,
      updatedAt: _now,
      expiresAt: _now.add(const Duration(days: 30)),
    ),
    idempotency: AuthScimIdempotencyBinding(
      key: 'create',
      fingerprint: 'fingerprint',
    ),
  );
}
