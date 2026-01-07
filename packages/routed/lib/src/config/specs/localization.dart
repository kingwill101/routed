import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

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
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'paths': const ['resources/lang'],
      'json_paths': const <String>[],
      'namespaces': const <String, String>{},
      'resolvers': kLocalizationResolverDefaults,
      'query': {'parameter': 'locale'},
      'cookie': {'name': 'locale'},
      'session': {'key': 'locale'},
      'header': {'name': 'Accept-Language'},
      'resolver_options': const <String, Object?>{},
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('paths'),
        type: 'list<string>',
        description:
            'Directories scanned for `locale/group.(yaml|yml|json)` files.',
        defaultValue: ['resources/lang'],
      ),
      ConfigDocEntry(
        path: path('json_paths'),
        type: 'list<string>',
        description: 'Directories containing flat `<locale>.json` dictionaries.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: path('namespaces'),
        type: 'map<string,string>',
        description:
            'Vendor namespace hints mapping namespace => absolute directory.',
        defaultValue: <String, String>{},
      ),
      ConfigDocEntry(
        path: path('resolvers'),
        type: 'list<string>',
        description:
            'Ordered locale resolvers (query, cookie, header, session).',
        defaultValueBuilder: () =>
            List<String>.from(kLocalizationResolverDefaults),
      ),
      ConfigDocEntry(
        path: path('query.parameter'),
        type: 'string',
        description: 'Query parameter consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      ConfigDocEntry(
        path: path('cookie.name'),
        type: 'string',
        description: 'Cookie name consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      ConfigDocEntry(
        path: path('session.key'),
        type: 'string',
        description: 'Session key consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      ConfigDocEntry(
        path: path('header.name'),
        type: 'string',
        description: 'Header inspected for Accept-Language fallbacks.',
        defaultValue: 'Accept-Language',
      ),
      ConfigDocEntry(
        path: path('resolver_options'),
        type: 'map',
        description: 'Resolver-specific options keyed by resolver identifier.',
        defaultValue: <String, Object?>{},
      ),
    ];
  }

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
