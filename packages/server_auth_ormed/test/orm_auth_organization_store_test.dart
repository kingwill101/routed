import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:server_auth/testing.dart';
import 'package:server_auth_ormed/server_auth_ormed.dart';
import 'package:test/test.dart';

void main() {
  late OrmDatabase database;
  late OrmAuthOrganizationSchema schema;
  late OrmAuthOrganizationStore store;

  setUp(() async {
    database = await SqliteDatabase.connect();
    schema = const OrmAuthOrganizationSchema(tablePrefix: 'organization_test');
    store = await OrmAuthOrganizationStore.open(database, schema: schema);
  });

  tearDown(() => database.close());

  test('passes the core auth store conformance suite', () async {
    final suite = AuthStoreConformanceSuite.fromStoreFactory(
      createStore: () async {
        final db = await SqliteDatabase.connect();
        final store = await OrmAuthStore.open(
          db,
          schema: const OrmAuthSchema(tablePrefix: 'core_auth_test'),
        );
        return store;
      },
      disposeStore: (store) => (store as OrmAuthStore).database.close(),
    );
    for (final testCase in suite.cases) {
      final result = await testCase.run();
      if (result.isSkipped) continue;
      expect(result.isSkipped, isFalse, reason: '${testCase.id}: $result');
    }
  });

  test('core records survive reopening the same database', () async {
    final directory = await Directory.systemTemp.createTemp('orm-auth-');
    final path = '${directory.path}/auth.sqlite';
    final db = await SqliteDatabase.connect(path: path);
    const schema = OrmAuthSchema(tablePrefix: 'restart_auth_test');
    final first = await OrmAuthStore.open(db, schema: schema);
    final now = DateTime.utc(2030);
    final user = AuthUser(id: 'restart-user', email: 'restart@example.com');
    final credential = AuthPasswordCredential(
      id: 'restart-credential',
      userId: user.id,
      identifier: user.email!,
      passwordHash: 'encoded-hash',
      createdAt: now,
      updatedAt: now,
    );
    expect(await first.credentials.register(user, credential), user);
    await db.close();

    final reopenedDb = await SqliteDatabase.connect(path: path);
    final reopened = OrmAuthStore(reopenedDb, schema: schema);
    expect((await reopened.users.findByEmail(user.email!))?.id, user.id);
    expect(
      (await reopened.credentials.findByIdentifier(credential.identifier))?.id,
      credential.id,
    );
    await reopenedDb.close();
    await directory.delete(recursive: true);
  });

  test('core and organization adapters share one transaction gate', () async {
    final db = await SqliteDatabase.connect();
    addTearDown(db.close);
    const authSchema = OrmAuthSchema(tablePrefix: 'shared_gate_test');
    const organizationSchema = OrmAuthOrganizationSchema(
      tablePrefix: 'shared_gate_test',
    );
    await db.migrate([
      ...authSchema.migrations,
      ...organizationSchema.migrations,
    ]);
    final auth = OrmAuthStore(db, schema: authSchema);
    final organizations = OrmAuthOrganizationStore(
      db,
      schema: organizationSchema,
    );
    final now = DateTime.utc(2030);
    await Future.wait([
      Future.sync(
        () => auth.users.create(
          AuthUser(id: 'shared-gate-user', email: 'shared@gate.test'),
        ),
      ),
      organizations.createOrganization(
        AuthOrganizationCreateTransaction(
          organization: AuthOrganization(
            id: 'shared-gate-organization',
            name: 'Shared gate',
            slug: 'shared-gate',
            createdAt: now,
            updatedAt: now,
          ),
          creatorMembership: AuthOrganizationMember(
            id: 'shared-gate-member',
            organizationId: 'shared-gate-organization',
            userId: 'shared-gate-user',
            roles: const ['owner'],
            createdAt: now,
          ),
          organizationLimit: null,
        ),
      ),
    ]);
    expect(await auth.users.findById('shared-gate-user'), isNotNull);
    expect(
      await organizations.findOrganization('shared-gate-organization'),
      isNotNull,
    );
  });

  test('composite provider-account identities remain unambiguous', () async {
    final db = await SqliteDatabase.connect();
    addTearDown(db.close);
    final auth = await OrmAuthStore.open(
      db,
      schema: const OrmAuthSchema(tablePrefix: 'composite_key_test'),
    );
    final first = AuthAccount(
      providerId: 'provider:one',
      providerAccountId: 'account',
      userId: 'user-one',
    );
    final second = AuthAccount(
      providerId: 'provider',
      providerAccountId: 'one:account',
      userId: 'user-two',
    );
    await auth.accounts.link(first);
    await auth.accounts.link(second);
    expect(
      (await auth.accounts.find(
        first.providerId,
        first.providerAccountId,
      ))?.userId,
      first.userId,
    );
    expect(
      (await auth.accounts.find(
        second.providerId,
        second.providerAccountId,
      ))?.userId,
      second.userId,
    );
  });

  test('durable organization deletion joins the core transaction', () async {
    final db = await SqliteDatabase.connect();
    const authSchema = OrmAuthSchema(tablePrefix: 'deletion_auth_test');
    const organizationSchema = OrmAuthOrganizationSchema(
      tablePrefix: 'deletion_auth_test',
    );
    await db.migrate([
      ...authSchema.migrations,
      ...organizationSchema.migrations,
    ]);
    final authStore = OrmAuthStore(db, schema: authSchema);
    final organizationStore = OrmAuthOrganizationStore(
      db,
      schema: organizationSchema,
    );
    final plugin = OrganizationPlugin<Object>(store: organizationStore);
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const [],
        store: authStore,
        storeMode: AuthStoreMode.durable,
        runtimeMode: AuthRuntimeMode.localDevelopment,
        plugins: [plugin],
      ),
    );
    final now = DateTime.utc(2030);
    final user = AuthUser(id: 'delete-user', email: 'delete@example.com');
    await authStore.users.create(user);
    await organizationStore.createOrganization(
      AuthOrganizationCreateTransaction(
        organization: AuthOrganization(
          id: 'delete-organization',
          name: 'Delete',
          slug: 'delete',
          createdAt: now,
          updatedAt: now,
        ),
        creatorMembership: AuthOrganizationMember(
          id: 'delete-owner',
          organizationId: 'delete-organization',
          userId: user.id,
          roles: const ['owner'],
          createdAt: now,
        ),
        organizationLimit: null,
      ),
    );
    await organizationStore.addMember(
      AuthOrganizationMember(
        id: 'delete-second-owner',
        organizationId: 'delete-organization',
        userId: 'other-user',
        roles: const ['owner'],
        createdAt: now,
      ),
    );
    await authStore.verificationTokens.save(
      AuthVerificationToken(
        identifier: 'account_deletion:${user.id}',
        token: 'delete-token',
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    final deleted = await authStore.userDeletionCoordinator
        .confirmAndDeleteUser(userId: user.id, token: 'delete-token', now: now);
    expect(deleted, isTrue);
    expect(await authStore.users.findById(user.id), isNull);
    expect(
      await organizationStore.findMember('delete-organization', user.id),
      isNull,
    );
    await db.close();
  });

  test('passes the organization store ownership conformance suite', () async {
    await verifyAuthOrganizationStoreOwnershipConformance(store);
  });

  test(
    'migration entries are ledgered and data survives adapter recreation',
    () async {
      final freshDatabase = await SqliteDatabase.connect();
      final first = await schema.migrate(freshDatabase);
      final second = await schema.migrate(freshDatabase);
      expect(first.actions, hasLength(1));
      expect(second.actions, isEmpty);
      await freshDatabase.close();

      final now = DateTime.utc(2030);
      final organization = AuthOrganization(
        id: 'durable-organization',
        name: 'Durable',
        slug: 'durable',
        createdAt: now,
        updatedAt: now,
      );
      final owner = AuthOrganizationMember(
        id: 'durable-owner',
        organizationId: organization.id,
        userId: 'durable-user',
        roles: const ['owner'],
        createdAt: now,
      );
      await store.createOrganization(
        AuthOrganizationCreateTransaction(
          organization: organization,
          creatorMembership: owner,
          organizationLimit: null,
        ),
      );

      final reopened = OrmAuthOrganizationStore(database, schema: schema);
      expect(
        (await reopened.findOrganization(organization.id))?.id,
        organization.id,
      );
      expect(
        (await reopened.findMember(organization.id, owner.userId))?.id,
        owner.id,
      );
    },
  );

  test('normalizes organization slugs before durable persistence', () async {
    final now = DateTime.utc(2030);
    final organization = AuthOrganization(
      id: 'normalized-organization',
      name: 'Normalized',
      slug: 'Mixed-Case',
      createdAt: now,
      updatedAt: now,
    );
    final owner = AuthOrganizationMember(
      id: 'normalized-owner',
      organizationId: organization.id,
      userId: 'normalized-user',
      roles: const ['owner'],
      createdAt: now,
    );
    final created = await store.createOrganization(
      AuthOrganizationCreateTransaction(
        organization: organization,
        creatorMembership: owner,
        organizationLimit: null,
      ),
    );
    expect(created.organization.slug, 'mixed-case');
    expect(
      (await store.findOrganizationBySlug('MIXED-CASE'))?.id,
      organization.id,
    );

    final updated = await store.updateOrganization(
      organization.copyWith(slug: 'Updated-Slug'),
    );
    expect(updated.slug, 'updated-slug');
    expect(
      (await store.findOrganizationBySlug('UPDATED-SLUG'))?.id,
      organization.id,
    );
  });
}
