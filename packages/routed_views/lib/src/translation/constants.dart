/// Constants shared across request localization utilities.
///
/// The localization middleware stores the resolved locale under
/// [kRequestLocaleAttribute], allowing request helpers and downstream
/// handlers to read the same value:
///
/// ```dart
/// final locale = ctx.get<String>(kRequestLocaleAttribute);
/// ```
library;

/// Request context key containing the locale selected for the current request.
///
/// The value is written by the localization middleware after the configured
/// the locale manager resolves the request. It is not a translation key or a
/// persistent user preference.
const String kRequestLocaleAttribute = 'routed.locale';
