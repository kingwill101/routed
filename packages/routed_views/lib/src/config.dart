import 'package:routed_core/routed_core.dart';
import 'package:routed_views/src/translation/resolvers.dart';

/// Immutable startup configuration for [LocalizationServiceProvider].
class LocalizationConfig implements ValidatableConfiguration {
  LocalizationConfig({
    List<String>? paths,
    List<String>? jsonPaths,
    Map<String, String>? namespaces,
    List<LocaleResolver>? resolvers,
    this.queryParameter = 'lang',
    this.cookieName = 'locale',
    this.sessionKey = 'locale',
    this.headerName = HttpHeaders.acceptLanguageHeader,
    this.defaultLocale = 'en',
    String? fallbackLocale,
  }) : paths = List<String>.unmodifiable(paths ?? const ['resources/lang']),
       jsonPaths = List<String>.unmodifiable(jsonPaths ?? const []),
       namespaces = Map<String, String>.unmodifiable(namespaces ?? const {}),
       resolvers = List<LocaleResolver>.unmodifiable(
         resolvers ??
             [
               QueryLocaleResolver(parameter: queryParameter),
               CookieLocaleResolver(cookieName: cookieName),
               SessionLocaleResolver(sessionKey: sessionKey),
               HeaderLocaleResolver(headerName: headerName),
             ],
       ),
       fallbackLocale = fallbackLocale ?? defaultLocale;

  final List<String> paths;
  final List<String> jsonPaths;
  final Map<String, String> namespaces;
  final List<LocaleResolver> resolvers;
  final String queryParameter;
  final String cookieName;
  final String sessionKey;
  final String headerName;
  final String defaultLocale;
  final String fallbackLocale;

  @override
  void validate(ConfigValidationContext context) {
    _requireNonEmptyList(context, paths, 'paths');
    context.require(resolvers.isNotEmpty, 'resolvers', 'cannot be empty');
    for (final entry in <String, String>{
      'queryParameter': queryParameter,
      'cookieName': cookieName,
      'sessionKey': sessionKey,
      'headerName': headerName,
      'defaultLocale': defaultLocale,
      'fallbackLocale': fallbackLocale,
    }.entries) {
      context.require(
        entry.value.trim().isNotEmpty,
        entry.key,
        '${entry.key} cannot be empty',
      );
    }
  }

  static void _requireNonEmptyList(
    ConfigValidationContext context,
    List<String> values,
    String path,
  ) {
    context.require(values.isNotEmpty, path, '$path cannot be empty');
    for (var index = 0; index < values.length; index++) {
      context.require(
        values[index].trim().isNotEmpty,
        '$path[$index]',
        'values cannot be empty',
      );
    }
  }
}

/// Immutable startup configuration for [ViewServiceProvider].
class RoutedViewConfig implements ValidatableConfiguration {
  RoutedViewConfig({
    this.engine = 'liquid',
    this.directory = 'views',
    this.cache = true,
    this.disk,
  });

  final String engine;
  final String directory;
  final bool cache;
  final String? disk;

  @override
  void validate(ConfigValidationContext context) {
    context.require(
      engine.trim().isNotEmpty,
      'engine',
      'view engine cannot be empty',
    );
    context.require(
      engine.toLowerCase() == 'liquid',
      'engine',
      'only the liquid view engine is currently supported',
    );
    if (disk != null) {
      context.require(
        disk!.trim().isNotEmpty,
        'disk',
        'view disk cannot be empty',
      );
    }
  }
}
