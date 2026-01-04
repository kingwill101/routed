import 'dart:async';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart' as routed;
import 'package:routed_cli/src/engine/schema_generator.dart';

class AnalyzerIntrospector {
  final String projectRoot;
  final String entrypoint;

  AnalyzerIntrospector({required this.projectRoot, required this.entrypoint});

  Future<routed.RouteManifest> introspect() async {
    final absoluteEntry = p.normalize(p.absolute(entrypoint));
    final entryDir = p.dirname(absoluteEntry);

    final collection = AnalysisContextCollection(
      includedPaths: [projectRoot, entryDir],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    final routes = <routed.RouteManifestEntry>[];
    final visitedFiles = <String>{};
    final queue = <String>[absoluteEntry];

    // Collect schemas
    final schemas = <String, Map<String, Object?>>{};

    while (queue.isNotEmpty) {
      final currentPath = queue.removeAt(0);
      if (visitedFiles.contains(currentPath)) continue;
      visitedFiles.add(currentPath);

      // Skip system libraries
      if (currentPath.contains('/lib/_internal/') ||
          currentPath.contains('/lib/core/') ||
          currentPath.contains('/lib/async/')) {
        continue;
      }

      try {
        final context = collection.contextFor(currentPath);
        final result = await context.currentSession.getResolvedUnit(
          currentPath,
        );

        if (result is ResolvedUnitResult) {
          final visitor = _RouteVisitor(routes, schemas);
          result.unit.visitChildren(visitor);

          final newFiles = visitor.referencedFiles.where(
            (f) => !visitedFiles.contains(f),
          );
          queue.addAll(newFiles);
        }
      } catch (e) {
        // print('Error analyzing $currentPath: $e');
      }
    }

    // Add schemas to the first route's constraints (hacky, but RouteManifest doesn't have global components yet)
    // Or we can rely on the generator to merge them later if we passed them.
    // But generateOpenApiDocument takes components map.
    // We need to return components too.
    // For now, we'll attach them to a dummy route or rely on the user to pass them?
    // No, generateOpenApiDocument needs them.
    // We might need to extend RouteManifest or return a richer object.
    // But for now, let's just stick them in the first route's constraints under 'components'
    // and modify the generator to pick them up?
    // Or better: The CLI command should handle this.
    // But AnalyzerIntrospector returns RouteManifest.

    // Let's add a special constraint to the first route?
    if (routes.isNotEmpty && schemas.isNotEmpty) {
      final first = routes.first;
      final newConstraints = Map<String, Object?>.from(first.constraints);
      newConstraints['components'] = {'schemas': schemas};

      routes[0] = routed.RouteManifestEntry(
        method: first.method,
        path: first.path,
        name: first.name,
        middleware: first.middleware,
        constraints: newConstraints,
        isFallback: first.isFallback,
      );
    }

    return routed.RouteManifest(routes: routes);
  }
}

class _RouteVisitor extends GeneralizingAstVisitor<void> {
  final List<routed.RouteManifestEntry> routes;
  final Map<String, Map<String, Object?>> schemas;
  final Set<String> referencedFiles = {};
  final List<String> _pathPrefixStack = [];
  final List<String> _groupNameStack = [];

  _RouteVisitor(this.routes, this.schemas);

  String get _currentPathPrefix => _pathPrefixStack.join('');
  String? get _currentGroupName =>
      _groupNameStack.isNotEmpty ? _groupNameStack.join('.') : null;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    try {
      final methodName = node.methodName.name;
      final targetType = node.target?.staticType;
      final isRouterOrEngine = _isRouterOrEngine(targetType);

      // Handle group calls
      if (isRouterOrEngine && methodName == 'group') {
        _handleGroupCall(node);
        return; // Don't call super, we handle children manually
      }

      if (isRouterOrEngine && _isHttpVerb(methodName)) {
        _extractRoute(node, methodName);
      }

      final element = node.methodName.element;
      if (element is ExecutableElement) {
        final source = _getSource(element);
        if (source != null) {
          referencedFiles.add(source.fullName);
        }
      }
    } catch (e) {
      // Ignore
    }

    super.visitMethodInvocation(node);
  }

  void _handleGroupCall(MethodInvocation node) {
    String? pathPrefix;
    FunctionExpression? builder;

    for (final arg in node.argumentList.arguments) {
      if (arg is NamedExpression) {
        if (arg.name.label.name == 'path' && arg.expression is StringLiteral) {
          pathPrefix = (arg.expression as StringLiteral).stringValue;
        } else if (arg.name.label.name == 'builder' &&
            arg.expression is FunctionExpression) {
          builder = arg.expression as FunctionExpression;
        }
      }
    }

    if (pathPrefix != null) {
      _pathPrefixStack.add(pathPrefix);
    }

    // Visit the builder function body to find nested routes
    if (builder != null) {
      builder.body.visitChildren(this);
    }

    // Also check for chained .name() on the group call
    final parent = node.parent;
    if (parent is MethodInvocation && parent.methodName.name == 'name') {
      // This is router.group(...).name('...')
      final nameArg = parent.argumentList.arguments.firstOrNull;
      if (nameArg is StringLiteral) {
        final groupName = nameArg.stringValue;
        if (groupName != null) {
          _groupNameStack.add(groupName);
        }
      }
    }

    if (pathPrefix != null) {
      _pathPrefixStack.removeLast();
    }

    // Pop group name if we added one
    if (parent is MethodInvocation &&
        parent.methodName.name == 'name' &&
        _groupNameStack.isNotEmpty) {
      _groupNameStack.removeLast();
    }
  }

  bool _isRouterOrEngine(DartType? type) {
    if (type == null) return false;
    final name = type.element?.name;
    return name == 'Engine' || name == 'Router';
  }

  bool _isHttpVerb(String name) {
    const verbs = {'get', 'post', 'put', 'delete', 'patch', 'head', 'options'};
    return verbs.contains(name);
  }

  void _extractRoute(MethodInvocation node, String method) {
    if (node.argumentList.arguments.isEmpty) return;

    final pathArg = node.argumentList.arguments.first;
    String path = '/';
    if (pathArg is StringLiteral) {
      path = pathArg.stringValue ?? '/';
    }

    // Prepend current path prefix from group stack
    final fullPath = _currentPathPrefix + path;

    // Look for chained .name() call
    String? routeName;
    AstNode? current = node.parent;
    while (current is MethodInvocation) {
      if (current.methodName.name == 'name' &&
          current.argumentList.arguments.isNotEmpty) {
        final nameArg = current.argumentList.arguments.first;
        if (nameArg is StringLiteral) {
          routeName = nameArg.stringValue;
        }
        break;
      }
      current = current.parent;
    }

    // Prepend group name if available
    final fullName = _currentGroupName != null && routeName != null
        ? '$_currentGroupName.$routeName'
        : routeName;

    final constraints = <String, Object?>{};
    final openapi = <String, Object?>{};

    _parseComments(node, openapi);

    if (node.argumentList.arguments.length > 1) {
      final handlerArg = node.argumentList.arguments[1];
      if (handlerArg is FunctionExpression) {
        _inferSchema(handlerArg, openapi);
      }
    }

    if (openapi.isNotEmpty) {
      constraints['openapi'] = openapi;
    }

    routes.add(
      routed.RouteManifestEntry(
        method: method.toUpperCase(),
        path: fullPath,
        name: fullName,
        constraints: constraints,
      ),
    );
  }

  void _parseComments(AstNode node, Map<String, Object?> openapi) {
    AstNode? current = node;
    while (current != null && current is! Statement) {
      current = current.parent;
    }

    if (current != null) {
      final token = current.beginToken;
      Token? preceding = token.precedingComments;
      while (preceding != null) {
        final comment = preceding.lexeme.trim().replaceAll(
          RegExp(r'^///?\s*'),
          '',
        );
        if (comment.startsWith('@Summary ')) {
          openapi['summary'] = comment.substring(9).trim();
        } else if (comment.startsWith('@Description ')) {
          openapi['description'] = comment.substring(13).trim();
        }
        preceding = preceding.next;
      }
    }
  }

  void _inferSchema(FunctionExpression handler, Map<String, Object?> openapi) {
    final generator = SchemaGenerator();
    final body = handler.body;

    final visitor = _HandlerVisitor(generator, openapi);
    body.visitChildren(visitor);

    if (visitor.responseType != null) {
      final schema = generator.generate(visitor.responseType!);
      visitor._addResponse('application/json', schema);
    }

    // Merge generated schemas into global schemas
    schemas.addAll(generator.schemas);
  }

  dynamic _getSource(Element element) {
    Element? current = element;
    while (current != null) {
      try {
        final source = (current as dynamic).source;
        if (source != null) return source;
      } catch (_) {}
      current = current.enclosingElement;
    }
    return null;
  }
}

class _HandlerVisitor extends RecursiveAstVisitor<void> {
  final SchemaGenerator generator;
  final Map<String, Object?> openapi;
  DartType? responseType;
  DartType? requestType;

  _HandlerVisitor(this.generator, this.openapi);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;

    // Check for ctx.bind(instance) or ctx.bind<T>(instance)
    if (methodName == 'bind') {
      DartType? type;
      // Try to get type from type argument first
      final typeArgs = node.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.isNotEmpty) {
        type = typeArgs.first.type;
      }
      // Fallback to inferring from the first argument
      else if (node.argumentList.arguments.isNotEmpty) {
        type = node.argumentList.arguments.first.staticType;
      }

      if (type != null) {
        requestType = type;
        _addRequestBody('application/json', requestType!);
      }
    }

    // Check for ctx.bindJSON(instance)
    if (methodName == 'bindJSON') {
      DartType? type;
      final typeArgs = node.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.isNotEmpty) {
        type = typeArgs.first.type;
      } else if (node.argumentList.arguments.isNotEmpty) {
        type = node.argumentList.arguments.first.staticType;
      }

      if (type != null) {
        requestType = type;
        _addRequestBody('application/json', requestType!);
      }
    }

    // Check for ctx.bindXML(instance)
    if (methodName == 'bindXML') {
      DartType? type;
      final typeArgs = node.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.isNotEmpty) {
        type = typeArgs.first.type;
      } else if (node.argumentList.arguments.isNotEmpty) {
        type = node.argumentList.arguments.first.staticType;
      }

      if (type != null) {
        requestType = type;
        _addRequestBody('application/xml', requestType!);
      }
    }

    // Check for ctx.bindQuery<T>
    if (methodName == 'bindQuery') {
      // Query binding doesn't affect request body, but we might want to document it?
      // For now, let's just note it.
    }

    // Check for ctx.shouldBindWith(instance, binding) or ctx.mustBindWith(instance, binding)
    if (methodName == 'shouldBindWith' || methodName == 'mustBindWith') {
      if (node.argumentList.arguments.length >= 2) {
        final bindingArg = node.argumentList.arguments[1];
        String? contentType;
        if (bindingArg is Identifier) {
          final name = bindingArg.name;
          if (name == 'jsonBinding') {
            contentType = 'application/json';
          } else if (name == 'xmlBinding') {
            contentType = 'application/xml';
          } else if (name == 'formBinding') {
            contentType = 'application/x-www-form-urlencoded';
          } else if (name == 'multipartBinding') {
            contentType = 'multipart/form-data';
          }
        }

        if (contentType != null) {
          // Try to infer type from first argument
          final instanceArg = node.argumentList.arguments[0];
          requestType = instanceArg.staticType;
          if (requestType != null) {
            _addRequestBody(contentType, requestType!);
          }
        }
      }
    }

    // Check for ctx.query('name')
    if (methodName == 'query') {
      if (node.argumentList.arguments.isNotEmpty) {
        final arg = node.argumentList.arguments.first;
        if (arg is StringLiteral) {
          final paramName = arg.stringValue;
          if (paramName != null) {
            _addParameter(paramName, 'query', 'string');
          }
        }
      }
    }

    // Check for ctx.param('name')
    if (methodName == 'param') {
      if (node.argumentList.arguments.isNotEmpty) {
        final arg = node.argumentList.arguments.first;
        if (arg is StringLiteral) {
          final paramName = arg.stringValue;
          if (paramName != null) {
            _addParameter(paramName, 'path', 'string', required: true);
          }
        }
      }
    }

    // Check for ctx.json(data) or Response.json(data)
    if (methodName == 'json') {
      // ctx.json(data)
      if (node.argumentList.arguments.isNotEmpty) {
        final arg = node.argumentList.arguments.first;
        responseType = arg.staticType;
      }
    }

    // Check for ctx.string(data) or Response.string(data)
    if (methodName == 'string') {
      _addResponse('text/plain', {'type': 'string'});
    }

    // Check for Response.ok(data)
    if (methodName == 'ok' || methodName == 'created') {
      final target = node.target;
      if (target is Identifier && target.name == 'Response') {
        if (node.argumentList.arguments.isNotEmpty) {
          final arg = node.argumentList.arguments.first;
          responseType = arg.staticType;
        }
      }
    }

    super.visitMethodInvocation(node);
  }

  void _addParameter(
    String name,
    String location,
    String type, {
    bool required = false,
  }) {
    final params =
        openapi.putIfAbsent('parameters', () => <Map<String, Object?>>[])
            as List<Map<String, Object?>>;
    // Check if param already exists
    if (params.any((p) => p['name'] == name && p['in'] == location)) {
      return;
    }

    params.add({
      'name': name,
      'in': location,
      'required': required,
      'schema': {'type': type},
    });
  }

  void _addResponse(String contentType, Map<String, Object?> schema) {
    final responses =
        openapi.putIfAbsent('responses', () => <String, Object?>{}) as Map;
    responses['200'] = {
      'description': 'Successful response',
      'content': {
        contentType: {'schema': schema},
      },
    };
  }

  void _addRequestBody(String contentType, DartType type) {
    final requestBody =
        openapi.putIfAbsent('requestBody', () => <String, Object?>{}) as Map;
    final content =
        requestBody.putIfAbsent('content', () => <String, Object?>{}) as Map;

    content[contentType] = {'schema': generator.generate(type)};
  }
}
