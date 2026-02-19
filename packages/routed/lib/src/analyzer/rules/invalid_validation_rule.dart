/// Lint rule that warns when a `RouteSchema.validationRules` map contains
/// unrecognized pipe rule names that won't match any registered validator.
library;

import 'dart:convert';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:routed/src/analyzer/utils.dart';

const _manifestPath = '.dart_tool/routed/route_manifest.json';

/// Pipe-rule aliases accepted by the OpenAPI converter but not registered as
/// validation rules.
const _aliasRuleNames = <String>{'integer', 'min_length', 'maxLength', 'regex'};

/// Reports a warning when a pipe rule string in `validationRules` contains an
/// unrecognized rule name.
///
/// **Bad:**
/// ```dart
/// schema: RouteSchema(
///   validationRules: {'name': 'required|strin|min:2'},  // 'strin' is invalid
/// )
/// ```
///
/// **Good:**
/// ```dart
/// schema: RouteSchema(
///   validationRules: {'name': 'required|string|min:2'},
/// )
/// ```
class InvalidValidationRuleRule extends AnalysisRule {
  static const _code = LintCode(
    'invalid_validation_rule',
    "Unknown validation rule '{0}' in pipe string.",
    correctionMessage:
        'Check the spelling. See the routed validation docs for the list '
        'of supported rules.',
  );

  InvalidValidationRuleRule()
    : super(
        name: 'invalid_validation_rule',
        description:
            'Warn when a validationRules pipe string contains an '
            'unrecognized rule name.',
      );

  @override
  DiagnosticCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final knownRules = _ValidationRuleCache.forContext(context);
    final visitor = _Visitor(this, knownRules);
    registry.addInstanceCreationExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final InvalidValidationRuleRule rule;
  final Set<String>? knownRuleNames;
  _Visitor(this.rule, this.knownRuleNames);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (knownRuleNames == null) return;
    if (!isRouteSchemaCreation(node)) return;

    final validationRulesArg = getNamedArgument(
      node.argumentList,
      'validationRules',
    );
    if (validationRulesArg == null) return;

    // The value should be a map literal: {'field': 'rules|here', ...}
    final mapExpr = validationRulesArg.expression;
    if (mapExpr is! SetOrMapLiteral) return;

    for (final element in mapExpr.elements) {
      if (element is! MapLiteralEntry) continue;

      // The value of each entry is a pipe string like 'required|string|min:2'
      final valueExpr = element.value;
      if (valueExpr is! SimpleStringLiteral) continue;

      final pipeString = valueExpr.value;
      final segments = pipeString.split('|');

      for (final segment in segments) {
        if (segment.isEmpty) continue;

        // Extract rule name (part before ':' for parameterized rules)
        final ruleName = segment.contains(':')
            ? segment.substring(0, segment.indexOf(':'))
            : segment;

        if (!knownRuleNames!.contains(ruleName)) {
          rule.reportAtNode(valueExpr, arguments: [ruleName]);
        }
      }
    }
  }
}

class _ValidationRuleCache {
  static final Map<String, _CachedValidationRules> _cache = {};

  static Set<String>? forContext(RuleContext context) {
    final root = _rootFolder(context);
    final manifestFile = root.getChildAssumingFile(_manifestPath);
    if (!manifestFile.exists) return null;

    final modificationStamp = manifestFile.modificationStamp;
    final cached = _cache[manifestFile.path];
    if (cached != null && cached.modificationStamp == modificationStamp) {
      return cached.names;
    }

    try {
      final decoded = jsonDecode(manifestFile.readAsStringSync());
      if (decoded is! Map) return null;
      final rawNames = decoded['validationRuleNames'];
      if (rawNames is! List) return null;

      final names = rawNames
          .whereType<Object>()
          .map((value) => value.toString())
          .toSet();
      names.addAll(_aliasRuleNames);

      _cache[manifestFile.path] = _CachedValidationRules(
        modificationStamp,
        names,
      );
      return names;
    } catch (_) {
      return null;
    }
  }

  static Folder _rootFolder(RuleContext context) {
    final packageRoot = context.package?.root;
    if (packageRoot != null) return packageRoot;
    return context.definingUnit.file.parent;
  }
}

class _CachedValidationRules {
  const _CachedValidationRules(this.modificationStamp, this.names);

  final int modificationStamp;
  final Set<String> names;
}
