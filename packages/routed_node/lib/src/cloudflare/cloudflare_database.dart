import 'package:ormed/ormed.dart';
import 'package:ormed_d1/ormed_d1.dart' show D1Database;

import 'cloudflare_types.dart';

/// Opens an Ormed database from a native Cloudflare D1 binding.
///
/// The binding remains owned by the Worker runtime; the returned
/// [OrmDatabase] is the application-level handle that can be registered with
/// `routed_database`'s `DatabaseManager`. No generated model registry is
/// required, although [registry] can be supplied for codegen-backed models.
Future<OrmDatabase> openCloudflareD1(
  CloudflareEnvironment environment, {
  String binding = 'DB',
  String name = 'default',
  ModelRegistry? registry,
  ScopeRegistry? scopeRegistry,
  Map<String, ValueCodec<dynamic>> codecs = const {},
  bool logging = false,
  String? database,
  String tablePrefix = '',
  String? defaultSchema,
  String carbonTimezone = 'UTC',
  String carbonLocale = 'en_US',
  bool enableNamedTimezones = false,
  List<DriverExtension> driverExtensions = const [],
  List<QueryInterceptor> interceptors = const [],
}) {
  return D1Database.fromBinding(
    binding: environment.d1(binding),
    name: name,
    registry: registry,
    scopeRegistry: scopeRegistry,
    codecs: codecs,
    logging: logging,
    database: database,
    tablePrefix: tablePrefix,
    defaultSchema: defaultSchema,
    carbonTimezone: carbonTimezone,
    carbonLocale: carbonLocale,
    enableNamedTimezones: enableNamedTimezones,
    driverExtensions: driverExtensions,
    interceptors: interceptors,
  );
}
