import 'package:ormed/ormed.dart';

/// Describes and migrates the Ormed organization persistence schema.
final class OrmAuthOrganizationSchema {
  /// Creates a schema using [tablePrefix] for all owned tables.
  const OrmAuthOrganizationSchema({this.tablePrefix = 'routed_auth'});

  /// Prefix applied to every table owned by this adapter.
  final String tablePrefix;

  /// The newest migration version defined by this package.
  static const int currentVersion = 1;

  /// Returns a validated table name for [suffix].
  String table(String suffix) {
    final prefix = tablePrefix.trim();
    final identifier = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
    if (!identifier.hasMatch(prefix)) {
      throw ArgumentError.value(
        tablePrefix,
        'tablePrefix',
        'must start with a letter and contain only letters, digits, or _',
      );
    }
    if (!identifier.hasMatch(suffix)) {
      throw ArgumentError.value(
        suffix,
        'suffix',
        'must start with a letter and contain only letters, digits, or _',
      );
    }
    return '${prefix}_$suffix';
  }

  /// The migration entries to register with an Ormed migration runner.
  ///
  /// The prefix is part of the migration slug so multiple isolated auth
  /// topologies can coexist in one database without sharing a ledger entry.
  List<MigrationEntry> get migrations {
    final prefix = tablePrefix.trim();
    table('organizations'); // Validate before constructing the entry.
    return [
      MigrationEntry.named(
        'm_20260907000000_create_${prefix}_organization_tables',
        _CreateOrganizationTablesMigration(this),
      ),
    ];
  }

  /// Applies this schema through Ormed's migration ledger.
  Future<MigrationReport> migrate(
    OrmDatabase database, {
    String ledgerTable = 'orm_migrations',
    int? limit,
  }) => database.migrate(migrations, ledgerTable: ledgerTable, limit: limit);
}

final class _CreateOrganizationTablesMigration extends Migration {
  const _CreateOrganizationTablesMigration(this.schema);

  final OrmAuthOrganizationSchema schema;

  @override
  void up(SchemaBuilder builder) {
    final organizations = schema.table('organizations');
    final members = schema.table('organization_members');
    final invitations = schema.table('organization_invitations');
    final roles = schema.table('organization_roles');
    final teams = schema.table('organization_teams');
    final teamMembers = schema.table('organization_team_members');
    final idempotency = schema.table('organization_idempotency');
    builder.create(organizations, (table) {
      table.text('id').primaryKey();
      table.text('name');
      table.text('slug').unique();
      table.text('logo').nullable();
      table.text('metadata');
      table.text('created_at');
      table.text('updated_at');
    });
    builder.create(members, (table) {
      table.text('db_key').primaryKey();
      table.text('id');
      table.text('organization_id');
      table.text('user_id');
      table.text('roles');
      table.text('attributes');
      table.text('created_at');
      table.unique(['organization_id', 'user_id']);
      table.index(['user_id']);
    });
    builder.create(invitations, (table) {
      table.text('id').primaryKey();
      table.text('organization_id');
      table.text('email');
      table.text('roles');
      table.text('inviter_id');
      table.text('status');
      table.text('expires_at');
      table.text('created_at');
      table.text('team_id').nullable();
      table.text('attributes');
      table.index(['organization_id', 'email', 'status']);
      table.index(['email']);
    });
    builder.create(roles, (table) {
      table.text('id').primaryKey();
      table.text('organization_id');
      table.text('name');
      table.text('permissions');
      table.boolean('predefined');
      table.text('created_at');
      table.text('updated_at');
      table.unique(['organization_id', 'name']);
    });
    builder.create(teams, (table) {
      table.text('id').primaryKey();
      table.text('organization_id');
      table.text('name');
      table.text('attributes');
      table.text('created_at');
      table.text('updated_at');
      table.unique(['organization_id', 'name']);
    });
    builder.create(teamMembers, (table) {
      table.text('db_key').primaryKey();
      table.text('id');
      table.text('team_id');
      table.text('user_id');
      table.text('created_at');
      table.unique(['team_id', 'user_id']);
      table.index(['user_id']);
    });
    builder.create(idempotency, (table) {
      table.text('key').primaryKey();
      table.text('organization_id');
      table.text('actor_id');
      table.text('operation_id');
      table.text('fingerprint');
      table.text('result_type');
      table.text('result');
      table.text('created_at');
    });
  }

  @override
  void down(SchemaBuilder builder) {
    builder.drop(schema.table('organization_idempotency'), ifExists: true);
    builder.drop(schema.table('organization_team_members'), ifExists: true);
    builder.drop(schema.table('organization_teams'), ifExists: true);
    builder.drop(schema.table('organization_roles'), ifExists: true);
    builder.drop(schema.table('organization_invitations'), ifExists: true);
    builder.drop(schema.table('organization_members'), ifExists: true);
    builder.drop(schema.table('organizations'), ifExists: true);
  }
}
