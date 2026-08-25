/// Analyzer plugin and provider metadata inspection APIs for Routed.
///
/// Enable the package from the root `analysis_options.yaml` of an application
/// or workspace:
///
/// ```yaml
/// plugins:
///   routed_analyzer: ^0.1.1
/// ```
///
/// The plugin reports documentation warnings for route registrations and
/// `RouteSchema` values. The `ProviderMetadata` and `inspectProviders` APIs
/// are available when tooling needs to inspect the providers registered by a
/// Routed application.
library;

export 'src/analyzer/routed_analyzer_plugin.dart' show RoutedAnalyzerPlugin;
export 'src/inspection/metadata.dart' show ProviderMetadata, inspectProviders;
