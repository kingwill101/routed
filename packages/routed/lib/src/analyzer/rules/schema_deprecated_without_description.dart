/// Lint rule that warns when a `RouteSchema` has `deprecated: true` but no
/// `description` explaining why the route is deprecated or what to use instead.
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:routed/src/analyzer/utils.dart';

/// Reports a warning when a `RouteSchema` has `deprecated: true` but does not
/// include a `description` explaining the deprecation.
///
/// When a route is marked as deprecated, consumers need to know why it was
/// deprecated and what to use instead.
///
/// **Bad:**
/// ```dart
/// schema: RouteSchema(summary: 'Old endpoint', deprecated: true)
/// ```
///
/// **Good:**
/// ```dart
/// schema: RouteSchema(
///   summary: 'Old endpoint',
///   deprecated: true,
///   description: 'Use /v2/users instead. Will be removed in v4.0.',
/// )
/// ```
class SchemaDeprecatedWithoutDescriptionRule extends AnalysisRule {
  static const _code = LintCode(
    'schema_deprecated_without_description',
    "Deprecated RouteSchema is missing a 'description' explaining why.",
    correctionMessage:
        'Add a description explaining why the route is deprecated and what '
        'to use instead.',
  );

  SchemaDeprecatedWithoutDescriptionRule()
    : super(
        name: 'schema_deprecated_without_description',
        description:
            'Warn when a deprecated route lacks a deprecation description.',
      );

  @override
  DiagnosticCode get diagnosticCode => _code;

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
  final SchemaDeprecatedWithoutDescriptionRule rule;
  _Visitor(this.rule);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isRouteSchemaCreation(node)) return;

    final deprecatedArg = getNamedArgument(node.argumentList, 'deprecated');
    if (deprecatedArg == null) return;

    // Check if deprecated: true (must be a boolean literal `true`).
    final value = deprecatedArg.expression;
    if (value is! BooleanLiteral || !value.value) return;

    // Now check if there's a description argument.
    final descriptionArg = getNamedArgument(node.argumentList, 'description');
    if (descriptionArg == null) {
      rule.reportAtNode(deprecatedArg);
    }
  }
}
