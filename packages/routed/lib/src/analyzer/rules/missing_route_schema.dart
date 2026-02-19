/// Lint rule that warns when a route registration call lacks a `schema:`
/// argument, which means the route will not appear in generated OpenAPI specs.
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:routed/src/analyzer/utils.dart';

/// Reports a warning when a route registration call (e.g. `router.get(...)`)
/// does not include a `schema:` named argument.
///
/// Without `schema:`, the route will have no OpenAPI metadata and will be
/// excluded from generated specifications.
///
/// **Bad:**
/// ```dart
/// router.get('/users', handler);
/// ```
///
/// **Good:**
/// ```dart
/// router.get('/users', handler, schema: RouteSchema(summary: 'List users'));
/// ```
class MissingRouteSchemaRule extends AnalysisRule {
  static const _code = LintCode(
    'missing_route_schema',
    'Route registration is missing a schema: argument.',
    correctionMessage:
        'Add a schema: RouteSchema(...) argument to include this route in '
        'the OpenAPI specification.',
  );

  MissingRouteSchemaRule()
    : super(
        name: 'missing_route_schema',
        description: 'Warn when a route is registered without schema metadata.',
      );

  @override
  DiagnosticCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addMethodInvocation(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final MissingRouteSchemaRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!isRouteRegistration(node)) return;

    final schemaArg = getSchemaArgument(node);
    if (schemaArg == null) {
      rule.reportAtNode(node.methodName);
    }
  }
}
