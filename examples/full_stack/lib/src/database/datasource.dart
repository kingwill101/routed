import 'dart:isolate';
import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:full_stack/orm_registry.g.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';

/// Creates a new DataSource instance using the project configuration.
Future<DataSource> createDataSource() async {
  ensureSqliteDriverRegistration();

  final projectDirectory = await _projectDirectory();
  final config = loadOrmConfig(projectDirectory);
  final configuredDatabase = config.driver.option('database');
  final configuredFile = configuredDatabase == null
      ? null
      : File(configuredDatabase.toString());
  final databasePath = configuredFile == null
      ? null
      : configuredFile.isAbsolute
      ? configuredFile.path
      : File('${projectDirectory.path}/${configuredFile.path}').absolute.path;
  final resolvedConfig = databasePath == null
      ? config
      : config.updateActiveConnection(
          driver: config.driver.copyWith(
            options: {...config.driver.options, 'database': databasePath},
          ),
        );
  return DataSource.fromConfig(resolvedConfig, registry: bootstrapOrm());
}

Future<Directory> _projectDirectory() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:full_stack/src/database/datasource.dart'),
  );
  if (uri != null && uri.scheme == 'file') {
    return File.fromUri(uri).parent.parent.parent.parent;
  }
  return Directory.current;
}
