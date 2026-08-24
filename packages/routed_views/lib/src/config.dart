import 'package:routed_core/routed_core.dart';
import 'package:routed_views/src/translation/resolvers.dart';

/// Immutable startup configuration for `LocalizationServiceProvider`.
///
/// The provider reads this value during its boot phase. Collection arguments
/// are copied into unmodifiable collections, so changing a source list or map
/// after construction does not change the running provider.
class LocalizationConfig implements ValidatableConfiguration {
  /// Creates localization configuration for file-backed translations.
  ///
  /// By default, grouped translations are loaded from `resources/lang`, flat
  /// locale JSON files are not enabled, and the locale resolver chain checks
  /// the `lang` query parameter, `locale` cookie, `locale` session value, and
  /// `Accept-Language` header in that order. Both [defaultLocale] and
  /// [fallbackLocale] default to `en`, with [fallbackLocale] otherwise
  /// defaulting to [defaultLocale]. Supplying [resolvers] replaces the built-in
  /// chain rather than extending it.
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

  /// Ordered directories containing grouped translation files.
  ///
  /// A group is looked up below this directory using the locale and group
  /// name, for example `resources/lang/en/messages.yaml`. Defaults to
  /// `['resources/lang']`.
  final List<String> paths;

  /// Ordered directories containing flat locale JSON files.
  ///
  /// A locale is loaded from a file such as `en.json` in each directory.
  /// Defaults to an empty list, which disables this additional lookup source.
  final List<String> jsonPaths;

  /// Namespace names mapped to their vendor translation directories.
  ///
  /// The map is passed to `FileTranslationLoader` so namespaced translation
  /// lookups can load a package's base files and merge application overrides.
  /// Defaults to an empty map.
  final Map<String, String> namespaces;

  /// Ordered locale resolvers evaluated for each request.
  ///
  /// The first resolver that returns a usable locale wins. This list is an
  /// immutable snapshot; passing a list here replaces the four built-in
  /// resolvers instead of appending to them.
  final List<LocaleResolver> resolvers;

  /// Query parameter used by the default [QueryLocaleResolver].
  ///
  /// Defaults to `lang`. This value is ignored by a custom [resolvers] list.
  final String queryParameter;

  /// Cookie name used by the default [CookieLocaleResolver].
  ///
  /// Defaults to `locale`. This value is ignored by a custom [resolvers] list.
  final String cookieName;

  /// Session key used by the default [SessionLocaleResolver].
  ///
  /// Defaults to `locale`. This value is ignored by a custom [resolvers] list.
  final String sessionKey;

  /// Header name used by the default [HeaderLocaleResolver].
  ///
  /// Defaults to `HttpHeaders.acceptLanguageHeader`. This value is ignored by
  /// a custom [resolvers] list.
  final String headerName;

  /// Locale used when no configured resolver returns a usable locale.
  ///
  /// Defaults to `en`.
  final String defaultLocale;

  /// Locale used when a translation is missing in the selected locale.
  ///
  /// Defaults to [defaultLocale]. The translator, rather than the resolver
  /// chain, uses this value when it looks up a missing translation.
  final String fallbackLocale;

  /// Validates locale sources, resolver configuration, and required names.
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
///
/// The provider consumes this value while the engine boots and writes the
/// resolved view settings into [EngineConfig]. It does not load a YAML file or
/// watch the filesystem for later changes.
class RoutedViewConfig implements ValidatableConfiguration {
  /// Creates view-engine configuration.
  ///
  /// Defaults to the built-in `liquid` engine, the `views` directory, enabled
  /// template caching, and no named storage disk. When [disk] is provided,
  /// [directory] is resolved through that storage disk; otherwise it is
  /// resolved against the engine's configured filesystem.
  RoutedViewConfig({
    this.engine = 'liquid',
    this.directory = 'views',
    this.cache = true,
    this.disk,
  });

  /// Name of the template engine to use.
  ///
  /// `liquid` is the currently supported built-in engine and is the default.
  final String engine;

  /// Directory containing templates, relative to the selected storage disk or
  /// configured filesystem unless it is already absolute.
  ///
  /// Defaults to `views`.
  final String directory;

  /// Whether rendered templates may be cached by the engine.
  ///
  /// Defaults to `true`. This controls the [ViewConfig] installed during
  /// provider boot; it does not change the selected engine implementation.
  final bool cache;

  /// Optional storage disk containing [directory].
  ///
  /// Defaults to `null`. If the name is not configured or cannot be resolved,
  /// the provider uses the filesystem from [EngineConfig].
  final String? disk;

  /// Validates the engine name and configured paths.
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
