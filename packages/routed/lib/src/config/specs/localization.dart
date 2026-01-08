import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';

import '../spec.dart';

const List<String> kLocalizationResolverDefaults = [
  'query',
  'cookie',
  'session',
  'header',
];

class LocalizationConfig {
  const LocalizationConfig({
    required this.paths,
    required this.jsonPaths,
    required this.namespaces,
    required this.resolvers,
    required this.queryParameter,
    required this.cookieName,
    required this.sessionKey,
    required this.headerName,
    required this.resolverOptions,
    required this.defaultLocale,
    required this.fallbackLocale,
  });

  final List<String> paths;
  final List<String> jsonPaths;
  final Map<String, String> namespaces;
  final List<String> resolvers;
  final String queryParameter;
  final String cookieName;
  final String sessionKey;
  final String headerName;
  final Map<String, Map<String, dynamic>> resolverOptions;
  final String defaultLocale;
  final String fallbackLocale;
}

class LocalizationConfigSpec extends ConfigSpec<LocalizationConfig> {
  const LocalizationConfigSpec();

  @override
  String get root => 'translation';

  @override
  Schema? get schema =>
      ConfigSchema.object(
        title: 'Localization Configuration',
        description: 'Internationalization and translation settings.',
        properties: {
          'paths': ConfigSchema.list(
        description:
            'Directories scanned for `locale/group.(yaml|yml|json)` files.',
            items: ConfigSchema.string(),
            defaultValue: const ['resources/lang'],
      ),
          'json_paths': ConfigSchema.list(
            description:
            'Directories containing flat `<locale>.json` dictionaries.',
            items: ConfigSchema.string(),
            defaultValue: const [],
          ),
          'namespaces': ConfigSchema.object(
        description:
            'Vendor namespace hints mapping namespace => absolute directory.',
            additionalProperties: true,
          ).withDefault(const {}),
          'resolvers': ConfigSchema.list(
        description:
            'Ordered locale resolvers (query, cookie, header, session).',
            items: ConfigSchema.string(),
            defaultValue: kLocalizationResolverDefaults,
      ),
          'query': ConfigSchema.object(
            properties: {
              'parameter': ConfigSchema.string(
                description: 'Query parameter consulted for locale overrides.',
                defaultValue: 'locale',
              ),
            },
          ),
          'cookie': ConfigSchema.object(
            properties: {
              'name': ConfigSchema.string(
                description: 'Cookie name consulted for locale overrides.',
                defaultValue: 'locale',
              ),
            },
          ),
          'session': ConfigSchema.object(
            properties: {
              'key': ConfigSchema.string(
                description: 'Session key consulted for locale overrides.',
                defaultValue: 'locale',
              ),
            },
          ),
          'header': ConfigSchema.object(
            properties: {
              'name': ConfigSchema.string(
                description: 'Header inspected for Accept-Language fallbacks.',
                defaultValue: 'Accept-Language',
              ),
            },
          ),
          'resolver_options': ConfigSchema.object(
        description: 'Resolver-specific options keyed by resolver identifier.',
            additionalProperties: true,
          ).withDefault(const {}),
        },
      );

  @override
  LocalizationConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final paths =
        parseStringList(
          map['paths'],
          context: 'translation.paths',
        ) ??
        const ['resources/lang'];
    final jsonPaths =
        parseStringList(
          map['json_paths'],
          context: 'translation.json_paths',
          allowEmptyResult: true,
        ) ??
        const <String>[];
    final namespacesRaw = map['namespaces'];
    final namespaces =
        namespacesRaw == null
            ? const <String, String>{}
            : parseStringMap(
              namespacesRaw as Object,
              context: 'translation.namespaces',
            );
    final resolvers =
        parseStringList(
          map['resolvers'],
          context: 'translation.resolvers',
        ) ??
        List<String>.from(kLocalizationResolverDefaults);

    final queryRaw = map.containsKey('query') ? map['query'] : null;
    final queryMap =
        queryRaw == null
            ? const <String, dynamic>{}
            : stringKeyedMap(queryRaw as Object, 'translation.query');
    final cookieRaw = map.containsKey('cookie') ? map['cookie'] : null;
    final cookieMap =
        cookieRaw == null
            ? const <String, dynamic>{}
            : stringKeyedMap(cookieRaw as Object, 'translation.cookie');
    final sessionRaw = map.containsKey('session') ? map['session'] : null;
    final sessionMap =
        sessionRaw == null
            ? const <String, dynamic>{}
            : stringKeyedMap(sessionRaw as Object, 'translation.session');
    final headerRaw = map.containsKey('header') ? map['header'] : null;
    final headerMap =
        headerRaw == null
            ? const <String, dynamic>{}
            : stringKeyedMap(headerRaw as Object, 'translation.header');

    final queryParameter =
        parseStringLike(
          queryMap['parameter'],
          context: 'translation.query.parameter',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'locale';
    final cookieName =
        parseStringLike(
          cookieMap['name'],
          context: 'translation.cookie.name',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'locale';
    final sessionKey =
        parseStringLike(
          sessionMap['key'],
          context: 'translation.session.key',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'locale';
    final headerName =
        parseStringLike(
          headerMap['name'],
          context: 'translation.header.name',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'Accept-Language';

    final resolverOptions = parseNestedMap(
      map['resolver_options'],
      context: 'translation.resolver_options',
      throwOnInvalid: true,
    );

    var defaultLocale = 'en';
    var fallbackLocale = defaultLocale;
    final config = context?.config;
    if (config != null) {
      final rawDefault =
          parseStringLike(
            config.get<Object?>('app.locale'),
            context: 'app.locale',
            allowEmpty: true,
            throwOnInvalid: true,
          );
      if (rawDefault != null) {
        defaultLocale = rawDefault;
      }
      final rawFallback =
          parseStringLike(
            config.get<Object?>('app.fallback_locale'),
            context: 'app.fallback_locale',
            allowEmpty: true,
            throwOnInvalid: true,
          );
      fallbackLocale = rawFallback ?? defaultLocale;
    }

    return LocalizationConfig(
      paths: paths,
      jsonPaths: jsonPaths,
      namespaces: namespaces,
      resolvers: resolvers,
      queryParameter: queryParameter,
      cookieName: cookieName,
      sessionKey: sessionKey,
      headerName: headerName,
      resolverOptions: resolverOptions,
      defaultLocale: defaultLocale,
      fallbackLocale: fallbackLocale,
    );
  }

  @override
  Map<String, dynamic> toMap(LocalizationConfig value) {
    return {
      'paths': value.paths,
      'json_paths': value.jsonPaths,
      'namespaces': value.namespaces,
      'resolvers': value.resolvers,
      'query': {'parameter': value.queryParameter},
      'cookie': {'name': value.cookieName},
      'session': {'key': value.sessionKey},
      'header': {'name': value.headerName},
      'resolver_options': value.resolverOptions,
    };
  }
}
