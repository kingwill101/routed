import 'package:routed_database/routed_database.dart';

/// Creates the table used by the live D1 binding smoke route.
final class CreateRoutedLiveChecksTable extends Migration {
  /// Creates the migration.
  const CreateRoutedLiveChecksTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('routed_live_checks', (table) {
      table
        ..increments('id')
        ..string('marker');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('routed_live_checks', ifExists: true);
  }
}

/// Migration entries applied by the environment-aware Cloudflare demo.
final List<MigrationEntry> routedLiveMigrations =
    List<MigrationEntry>.unmodifiable([
      MigrationEntry.named(
        'm_20260829000100_create_routed_live_checks',
        const CreateRoutedLiveChecksTable(),
      ),
    ]);
