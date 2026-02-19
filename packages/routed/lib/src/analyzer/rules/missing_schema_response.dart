/// Lint rule that warns when a `RouteSchema` constructor call is missing a
/// `responses` argument, leaving the endpoint's response contract undocumented.
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:routed/src/analyzer/utils.dart';

/// Reports a warning when a `RouteSchema` is constructed without a `responses`
/// argument.
///
/// Without `responses`, the endpoint's response contract is undocumented in the
/// OpenAPI specification, making it harder for consumers to understand what the
/// endpoint returns.
///
/// **Bad:**
/// ```dart
/// schema: RouteSchema(summary: 'Get user')
/// ```
///
/// **Good:**
/// ```dart
/// schema: RouteSchema(
///   summary: 'Get user',
///   responses: {200: ResponseSchema(description: 'The user')},
/// )
/// ```
class MissingSchemaResponseRule extends AnalysisRule {
  static const _code = LintCode(
    'missing_schema_response',
    "RouteSchema is missing a 'responses' argument.",
    correctionMessage:
        'Add a responses: {200: ResponseSchema(description: ...)} argument '
        'to document the response contract.',
  );

  MissingSchemaResponseRule()
    : super(
        name: 'missing_schema_response',
        description: 'Warn when a RouteSchema lacks response documentation.',
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
  final MissingSchemaResponseRule rule;
  _Visitor(this.rule);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isRouteSchemaCreation(node)) return;

    final responsesArg = getNamedArgument(node.argumentList, 'responses');
    if (responsesArg == null) {
      rule.reportAtNode(node.constructorName);
    }
  }
}
