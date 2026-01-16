import 'package:ormed_cli/runtime.dart';
import 'package:ormed/ormed.dart';
import 'package:full_stack/orm_registry.g.dart' as g;

import 'seeders/database_seeder.dart';
// <ORM-SEED-IMPORTS>
// </ORM-SEED-IMPORTS>

/// Registered seeders for this project.
///
/// Used by `ormed seed` command and can be imported for programmatic seeding.
final List<SeederRegistration> seeders = <SeederRegistration>[
  // <ORM-SEED-REGISTRY>
  SeederRegistration(
    name: 'AppDatabaseSeeder',
    factory: (connection) => AppDatabaseSeeder(connection),
  ),
  // </ORM-SEED-REGISTRY>
];

/// Run project seeders on the given connection.
///
/// Example:
/// ```dart
/// await runProjectSeeds(connection);
/// await runProjectSeeds(connection, names: ['UserSeeder']);
/// ```
Future<void> runProjectSeeds(
  OrmConnection connection, {
  List<String>? names,
  bool pretend = false,
}) async {
  g.bootstrapOrm(registry: connection.context.registry);
  await SeederRunner().run(
    connection: connection,
    seeders: seeders,
    names: names,
    pretend: pretend,
  );
}

Future<void> main(List<String> args) => runSeedRegistryEntrypoint(
  args: args,
  seeds: seeders,
  beforeRun: (connection) =>
      g.bootstrapOrm(registry: connection.context.registry),
);
