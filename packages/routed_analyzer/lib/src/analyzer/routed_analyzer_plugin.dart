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
class RoutedAnalyzerPlugin extends Plugin {
  /// Creates the Routed analyzer plugin.
  RoutedAnalyzerPlugin();

  /// The name used to identify this plugin in analyzer diagnostics.
  @override
  String get name => 'routed';

  /// Registers Routed's built-in analyzer rules.
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
