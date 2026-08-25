/// Lint rule that warns when a `RouteSchema` constructor call is missing a
/// `summary` argument, which is the primary human-readable description in
/// OpenAPI output.
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:routed_analyzer/src/analyzer/utils.dart';

/// Reports a warning when a `RouteSchema` is constructed without a `summary`
/// argument.
///
/// The `summary` field is the primary human-readable description of an endpoint
/// in OpenAPI specs and is essential for good API documentation.
///
/// **Bad:**
/// ```dart
/// schema: RouteSchema(tags: ['users'])
/// ```
///
/// **Good:**
/// ```dart
/// schema: RouteSchema(summary: 'List all users', tags: ['users'])
/// ```
class MissingSchemaSummaryRule extends AnalysisRule {
  /// Creates the missing schema summary analyzer rule.
  MissingSchemaSummaryRule()
    : super(
        name: 'missing_schema_summary',
        description:
            'Warn when a RouteSchema lacks a summary for OpenAPI output.',
      );

  static const _code = LintCode(
    'missing_schema_summary',
    "RouteSchema is missing a 'summary' argument.",
    correctionMessage:
        "Add a summary: 'Description of this endpoint' argument to provide "
        'human-readable API documentation.',
  );

  /// The diagnostic code reported for a schema without a summary.
  @override
  DiagnosticCode get diagnosticCode => _code;

  /// Registers the AST visitor that checks `RouteSchema` constructors.
  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addInstanceCreationExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final MissingSchemaSummaryRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isRouteSchemaCreation(node)) return;

    final summaryArg = getNamedArgument(node.argumentList, 'summary');
    if (summaryArg == null) {
      rule.reportAtNode(node.constructorName);
    }
  }
}
