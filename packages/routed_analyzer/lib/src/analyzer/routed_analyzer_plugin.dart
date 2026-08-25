/// The routed analyzer plugin implementation.
///
/// Registers all lint rules that provide IDE feedback for route definitions,
/// schema metadata, and validation rules.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:routed_analyzer/src/analyzer/rules/invalid_validation_rule.dart';
import 'package:routed_analyzer/src/analyzer/rules/missing_route_schema.dart';
import 'package:routed_analyzer/src/analyzer/rules/missing_schema_response.dart';
import 'package:routed_analyzer/src/analyzer/rules/missing_schema_summary.dart';
import 'package:routed_analyzer/src/analyzer/rules/schema_deprecated_without_description.dart';

/// Analyzer plugin for the routed framework.
///
/// Provides lint rules that help developers write well-documented APIs:
///
/// - `missing_route_schema` — route registered without `schema:` metadata
/// - `missing_schema_summary` — `RouteSchema` without a `summary`
/// - `missing_schema_response` — `RouteSchema` without any `responses`
/// - `invalid_validation_rule` — unrecognized pipe rule in `validationRules`
/// - `schema_deprecated_without_description` — deprecated route without
///   explaining why
///
/// All five rules are registered as analyzer warnings, so they are enabled
/// when the plugin is enabled. Suppress an individual diagnostic with a
/// `routed/`-qualified ignore comment, for example:
///
/// ```dart
/// // ignore: routed/missing_schema_summary
/// final schema = RouteSchema(
///   responses: [ResponseSchema(200, description: 'OK')],
/// );
/// ```
class RoutedAnalyzerPlugin extends Plugin {
  /// Creates the Routed analyzer plugin.
  RoutedAnalyzerPlugin();

  /// The name used to identify this plugin in analyzer diagnostics.
  @override
  String get name => 'routed';

  /// Registers Routed's built-in analyzer rules.
  ///
  /// The rules are warnings rather than opt-in lints, which lets them provide
  /// feedback immediately after the plugin is enabled.
  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(MissingRouteSchemaRule())
      ..registerWarningRule(MissingSchemaSummaryRule())
      ..registerWarningRule(MissingSchemaResponseRule())
      ..registerWarningRule(InvalidValidationRuleRule())
      ..registerWarningRule(SchemaDeprecatedWithoutDescriptionRule());
  }
}
