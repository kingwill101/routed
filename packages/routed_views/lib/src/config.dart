import 'package:routed_core/routed_core.dart';
import 'package:routed_views/src/translation/resolvers.dart';

/// Immutable startup configuration for `LocalizationServiceProvider`.
class LocalizationConfig implements ValidatableConfiguration {
  /// Creates localization configuration for file-backed translations.
  ///
  /// [resolvers] defaults to query, cookie, session, and
  /// `Accept-Language` resolution in that order.
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

  /// Directories containing grouped translation files.
  final List<String> paths;

  /// Directories containing locale JSON files.
  final List<String> jsonPaths;

  /// Namespace names mapped to their vendor translation directories.
  final Map<String, String> namespaces;

  /// Ordered locale resolvers evaluated for each request.
  final List<LocaleResolver> resolvers;

  /// Query parameter used by the default query resolver.
  final String queryParameter;

  /// Cookie name used by the default cookie resolver.
  final String cookieName;

  /// Session key used by the default session resolver.
  final String sessionKey;

  /// Header name used by the default header resolver.
  final String headerName;

  /// Locale used when no resolver returns a locale.
  final String defaultLocale;

  /// Locale used when a translation is missing in the selected locale.
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

/// Immutable startup configuration for `ViewServiceProvider`.
class RoutedViewConfig implements ValidatableConfiguration {
  /// Creates view-engine configuration.
  ///
  /// The current built-in engine is `liquid`; [directory] is resolved against
  /// the configured storage disk when [disk] is provided.
  RoutedViewConfig({
    this.engine = 'liquid',
    this.directory = 'views',
    this.cache = true,
    this.disk,
  });

  /// Name of the template engine to use.
  final String engine;

  /// Directory containing templates.
  final String directory;

  /// Whether rendered templates may be cached by the engine.
  final bool cache;

  /// Optional storage disk containing [directory].
  final String? disk;

  @override
  void validate(ConfigValidationContext context) {
    context
      ..require(
        engine.trim().isNotEmpty,
        'engine',
        'view engine cannot be empty',
      )
      ..require(
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
