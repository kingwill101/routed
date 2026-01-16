import 'package:ormed/ormed.dart';
import 'package:full_stack/orm_registry.g.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';

/// Creates a new DataSource instance using the project configuration.
DataSource createDataSource() {
  ensureSqliteDriverRegistration();

  final config = loadOrmConfig();
  return DataSource.fromConfig(config, registry: bootstrapOrm());
}
