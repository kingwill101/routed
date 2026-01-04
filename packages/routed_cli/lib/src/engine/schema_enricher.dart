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

/// Enriches a runtime RouteManifest with schema information from static analysis.
class SchemaEnricher {
  final String projectRoot;
  final String entrypoint;

  SchemaEnricher({required this.projectRoot, required this.entrypoint});

  /// Enriches the manifest with request/response schemas inferred from source code.
  Future<routed.RouteManifest> enrich(routed.RouteManifest manifest) async {
    final absoluteEntry = p.normalize(
      p.absolute(p.join(projectRoot, entrypoint)),
    );
    final entryDir = p.dirname(absoluteEntry);

    final collection = AnalysisContextCollection(
      includedPaths: [projectRoot, entryDir],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    // Build a map of (METHOD, PATH) -> handler schemas
    final handlerSchemas = <String, Map<String, Object?>>{};
    final globalSchemas = <String, Map<String, Object?>>{};
    final visitedFiles = <String>{};
    final queue = <String>[absoluteEntry];

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
          final visitor = _RouteSchemaVisitor(handlerSchemas, globalSchemas);
          result.unit.visitChildren(visitor);

          // Add referenced files to queue
          final newFiles = visitor.referencedFiles.where(
            (f) => !visitedFiles.contains(f),
          );
          queue.addAll(newFiles);
        }
      } catch (e) {
        // Ignore analysis errors
      }
    }

    // Enrich each route with its schema
    final enrichedRoutes = <routed.RouteManifestEntry>[];
    for (final route in manifest.routes) {
      final key = '${route.method}:${route.path}';
      final schema = handlerSchemas[key];

      if (schema != null) {
        final newConstraints = Map<String, Object?>.from(route.constraints);
        final existingOpenapi = newConstraints['openapi'];
        if (existingOpenapi is Map<String, Object?>) {
          existingOpenapi.addAll(schema);
        } else {
          newConstraints['openapi'] = schema;
        }

        enrichedRoutes.add(
          routed.RouteManifestEntry(
            method: route.method,
            path: route.path,
            name: route.name,
            middleware: route.middleware,
            constraints: newConstraints,
            isFallback: route.isFallback,
          ),
        );
      } else {
        enrichedRoutes.add(route);
      }
    }

    // Add global schemas to the first route's constraints
    if (enrichedRoutes.isNotEmpty && globalSchemas.isNotEmpty) {
      final first = enrichedRoutes.first;
      final newConstraints = Map<String, Object?>.from(first.constraints);
      newConstraints['components'] = {'schemas': globalSchemas};

      enrichedRoutes[0] = routed.RouteManifestEntry(
        method: first.method,
        path: first.path,
        name: first.name,
        middleware: first.middleware,
        constraints: newConstraints,
        isFallback: first.isFallback,
      );
    }

    return routed.RouteManifest(routes: enrichedRoutes);
  }
}

/// Visitor that finds route handlers and extracts their schemas.
class _RouteSchemaVisitor extends GeneralizingAstVisitor<void> {
  final Map<String, Map<String, Object?>> handlerSchemas;
  final Map<String, Map<String, Object?>> globalSchemas;
  final Set<String> referencedFiles = {};
  final List<String> _pathPrefixStack = [];

  /// Map of function names to their OpenAPI docs from comments
  final Map<String, Map<String, Object?>> functionDocs = {};

  _RouteSchemaVisitor(this.handlerSchemas, this.globalSchemas);

  String get _currentPathPrefix => _pathPrefixStack.join('');

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Collect comments on function declarations
    final docs = <String, Object?>{};
    _parseCommentsFromNode(node, docs);
    if (docs.isNotEmpty) {
      functionDocs[node.name.lexeme] = docs;
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    try {
      final methodName = node.methodName.name;
      final targetType = node.target?.staticType;
      final isRouterOrEngine = _isRouterOrEngine(targetType);

      // Handle group calls
      if (isRouterOrEngine && methodName == 'group') {
        _handleGroupCall(node);
        return;
      }

      if (isRouterOrEngine && _isHttpVerb(methodName)) {
        _extractRouteSchema(node, methodName);
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

    if (builder != null) {
      builder.body.visitChildren(this);
    }

    if (pathPrefix != null) {
      _pathPrefixStack.removeLast();
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

  void _extractRouteSchema(MethodInvocation node, String method) {
    if (node.argumentList.arguments.isEmpty) return;

    final pathArg = node.argumentList.arguments.first;
    String path = '/';
    if (pathArg is StringLiteral) {
      path = pathArg.stringValue ?? '/';
    }

    final fullPath = _currentPathPrefix + path;
    final key = '${method.toUpperCase()}:$fullPath';

    final openapi = <String, Object?>{};
    final generator = SchemaGenerator();

    // Parse comments
    _parseComments(node, openapi);

    // Infer schemas from handler
    if (node.argumentList.arguments.length > 1) {
      final handlerArg = node.argumentList.arguments[1];

      if (handlerArg is FunctionExpression) {
        // Inline function - visit the body
        final visitor = _HandlerSchemaVisitor(generator, openapi);
        handlerArg.body.visitChildren(visitor);

        if (visitor.responseType != null) {
          final schema = generator.generate(visitor.responseType!);
          _addResponse(openapi, 'application/json', schema);
        }
      } else if (handlerArg is Identifier) {
        // Function reference - look up comments from the function declaration
        final funcName = handlerArg is SimpleIdentifier
            ? handlerArg.name
            : handlerArg.toString();

        // Check if we have collected docs for this function
        final funcDocs = functionDocs[funcName];
        if (funcDocs != null) {
          openapi.addAll(funcDocs);
        }

        // Also try to get annotations from element
        final type = handlerArg.staticType;
        if (type is FunctionType) {
          final element = type.alias?.element ?? type.element;
          if (element != null) {
            _extractAnnotations(element, openapi);
          }
        }
      }
    }

    if (openapi.isNotEmpty) {
      handlerSchemas[key] = openapi;
    }

    // Merge generated schemas into global schemas
    globalSchemas.addAll(generator.schemas);
  }

  void _parseComments(AstNode node, Map<String, Object?> openapi) {
    // Find the containing statement (ExpressionStatement typically)
    AstNode? current = node;
    while (current != null && current is! Statement) {
      current = current.parent;
    }

    if (current != null) {
      final token = current.beginToken;
      Token? preceding = token.precedingComments;
      while (preceding != null) {
        // Strip leading slashes and whitespace
        final comment = preceding.lexeme
            .replaceFirst(RegExp(r'^///?\s*'), '')
            .trim();

        // @Summary Short summary
        if (comment.startsWith('@Summary ')) {
          openapi['summary'] = comment.substring(9).trim();
        }
        // @Description Longer description
        else if (comment.startsWith('@Description ')) {
          openapi['description'] = comment.substring(13).trim();
        }
        // @Tags tag1, tag2, tag3
        else if (comment.startsWith('@Tags ')) {
          final tagsStr = comment.substring(6).trim();
          final tags = tagsStr
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();
          if (tags.isNotEmpty) {
            openapi['tags'] = tags;
          }
        }
        // @Response 200 Success description
        else if (comment.startsWith('@Response ')) {
          final rest = comment.substring(10).trim();
          final match = RegExp(r'^(\d+)\s+(.*)').firstMatch(rest);
          if (match != null) {
            final status = match.group(1)!;
            final description = match.group(2)!.trim();
            final responses =
                openapi.putIfAbsent('responses', () => <String, Object?>{})
                    as Map;
            responses[status] = {'description': description};
          }
        }
        // @Deprecated Reason why deprecated
        else if (comment.startsWith('@Deprecated')) {
          openapi['deprecated'] = true;
        }
        // @OperationId custom_operation_id
        else if (comment.startsWith('@OperationId ')) {
          openapi['operationId'] = comment.substring(13).trim();
        }

        preceding = preceding.next;
      }
    }
  }

  /// Parse comments from any AST node (for function declarations)
  void _parseCommentsFromNode(AstNode node, Map<String, Object?> openapi) {
    final token = node.beginToken;
    Token? preceding = token.precedingComments;
    while (preceding != null) {
      final comment = preceding.lexeme
          .replaceFirst(RegExp(r'^///?\s*'), '')
          .trim();

      if (comment.startsWith('@Summary ')) {
        openapi['summary'] = comment.substring(9).trim();
      } else if (comment.startsWith('@Description ')) {
        openapi['description'] = comment.substring(13).trim();
      } else if (comment.startsWith('@Tags ')) {
        final tagsStr = comment.substring(6).trim();
        final tags = tagsStr
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (tags.isNotEmpty) {
          openapi['tags'] = tags;
        }
      } else if (comment.startsWith('@Response ')) {
        final rest = comment.substring(10).trim();
        final match = RegExp(r'^(\d+)\s+(.*)').firstMatch(rest);
        if (match != null) {
          final status = match.group(1)!;
          final description = match.group(2)!.trim();
          final responses =
              openapi.putIfAbsent('responses', () => <String, Object?>{})
                  as Map;
          responses[status] = {'description': description};
        }
      } else if (comment.startsWith('@Deprecated')) {
        openapi['deprecated'] = true;
      } else if (comment.startsWith('@OperationId ')) {
        openapi['operationId'] = comment.substring(13).trim();
      }

      preceding = preceding.next;
    }
  }

  void _addResponse(
    Map<String, Object?> openapi,
    String contentType,
    Map<String, Object?> schema,
  ) {
    final responses =
        openapi.putIfAbsent('responses', () => <String, Object?>{}) as Map;
    responses['200'] = {
      'description': 'Successful response',
      'content': {
        contentType: {'schema': schema},
      },
    };
  }

  void _extractAnnotations(Element element, Map<String, Object?> openapi) {
    // Get annotations from the element - metadata.annotations is the List
    final annotations = element.metadata.annotations;

    for (final annotation in annotations) {
      final annotationElement = annotation.element;
      if (annotationElement == null) continue;

      final annotationType = annotationElement.enclosingElement?.name;

      // Handle @Summary('...')
      if (annotationType == 'Summary') {
        final value = annotation.computeConstantValue();
        final summary = value?.getField('value')?.toStringValue();
        if (summary != null) {
          openapi['summary'] = summary;
        }
      }

      // Handle @Description('...')
      if (annotationType == 'Description') {
        final value = annotation.computeConstantValue();
        final description = value?.getField('value')?.toStringValue();
        if (description != null) {
          openapi['description'] = description;
        }
      }

      // Handle @ApiTags(['...'])
      if (annotationType == 'ApiTags') {
        final value = annotation.computeConstantValue();
        final tagsList = value?.getField('values')?.toListValue();
        if (tagsList != null) {
          final tags = tagsList
              .map((e) => e.toStringValue())
              .whereType<String>()
              .toList();
          if (tags.isNotEmpty) {
            openapi['tags'] = tags;
          }
        }
      }

      // Handle @OperationId('...')
      if (annotationType == 'OperationId') {
        final value = annotation.computeConstantValue();
        final operationId = value?.getField('value')?.toStringValue();
        if (operationId != null) {
          openapi['operationId'] = operationId;
        }
      }

      // Handle @ApiDeprecated(...)
      if (annotationType == 'ApiDeprecated') {
        openapi['deprecated'] = true;
      }

      // Handle @ApiResponse(...)
      if (annotationType == 'ApiResponse') {
        final value = annotation.computeConstantValue();
        final status = value?.getField('status')?.toIntValue();
        final description = value?.getField('description')?.toStringValue();
        final example = value?.getField('example');

        if (status != null) {
          final responses =
              openapi.putIfAbsent('responses', () => <String, Object?>{})
                  as Map;
          final responseData = <String, Object?>{
            'description': description ?? 'Success',
          };

          if (example != null && !example.isNull) {
            // Convert DartObject to a JSON-serializable value
            final exampleValue = _dartObjectToValue(example);
            if (exampleValue != null) {
              responseData['content'] = {
                'application/json': {'example': exampleValue},
              };
            }
          }

          responses[status.toString()] = responseData;
        }
      }
    }
  }

  Object? _dartObjectToValue(dynamic dartObject) {
    if (dartObject == null) return null;
    if (dartObject.isNull) return null;

    final stringValue = dartObject.toStringValue();
    if (stringValue != null) return stringValue;

    final intValue = dartObject.toIntValue();
    if (intValue != null) return intValue;

    final doubleValue = dartObject.toDoubleValue();
    if (doubleValue != null) return doubleValue;

    final boolValue = dartObject.toBoolValue();
    if (boolValue != null) return boolValue;

    final listValue = dartObject.toListValue();
    if (listValue != null) {
      return listValue.map(_dartObjectToValue).toList();
    }

    final mapValue = dartObject.toMapValue();
    if (mapValue != null) {
      final result = <String, Object?>{};
      for (final entry in mapValue.entries) {
        final key = _dartObjectToValue(entry.key);
        if (key is String) {
          result[key] = _dartObjectToValue(entry.value);
        }
      }
      return result;
    }

    return null;
  }
}

/// Visitor for extracting schema information from a handler function body.
class _HandlerSchemaVisitor extends RecursiveAstVisitor<void> {
  final SchemaGenerator generator;
  final Map<String, Object?> openapi;
  DartType? responseType;
  DartType? requestType;

  _HandlerSchemaVisitor(this.generator, this.openapi);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;

    // Check for ctx.bind(instance)
    if (methodName == 'bind' || methodName == 'bindJSON') {
      DartType? type;
      final typeArgs = node.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.isNotEmpty) {
        type = typeArgs.first.type;
      } else if (node.argumentList.arguments.isNotEmpty) {
        type = node.argumentList.arguments.first.staticType;
      }

      if (type != null) {
        requestType = type;
        _addRequestBody('application/json', type);
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
        _addRequestBody('application/xml', type);
      }
    }

    // Check for ctx.shouldBindWith/mustBindWith
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

        if (contentType != null && node.argumentList.arguments.isNotEmpty) {
          final instanceArg = node.argumentList.arguments[0];
          final type = instanceArg.staticType;
          if (type != null) {
            requestType = type;
            _addRequestBody(contentType, type);
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

    // Check for ctx.json(data)
    if (methodName == 'json') {
      if (node.argumentList.arguments.isNotEmpty) {
        final arg = node.argumentList.arguments.first;
        responseType = arg.staticType;
      }
    }

    // Check for ctx.string(data)
    if (methodName == 'string') {
      final responses =
          openapi.putIfAbsent('responses', () => <String, Object?>{}) as Map;
      responses['200'] = {
        'description': 'Successful response',
        'content': {
          'text/plain': {
            'schema': {'type': 'string'},
          },
        },
      };
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
            as List;
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

  void _addRequestBody(String contentType, DartType type) {
    final requestBody =
        openapi.putIfAbsent('requestBody', () => <String, Object?>{}) as Map;
    final content =
        requestBody.putIfAbsent('content', () => <String, Object?>{}) as Map;
    content[contentType] = {'schema': generator.generate(type)};
  }
}
