import 'dart:async';
import 'dart:io' as io;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:routed/src/openapi/annotations.dart';
import 'package:routed/src/openapi/schema.dart';

/// Partial OpenAPI metadata extracted from handler declarations.
class ExtractedRouteMetadata {
  const ExtractedRouteMetadata({
    this.summary,
    this.description,
    this.tags = const <String>[],
    this.operationId,
    this.deprecated,
    this.hidden,
    this.body,
    this.params = const <ParamSchema>[],
    this.responses = const <ResponseSchema>[],
  });

  final String? summary;
  final String? description;
  final List<String> tags;
  final String? operationId;
  final bool? deprecated;
  final bool? hidden;
  final BodySchema? body;
  final List<ParamSchema> params;
  final List<ResponseSchema> responses;

  bool get isEmpty =>
      summary == null &&
      description == null &&
      tags.isEmpty &&
      operationId == null &&
      deprecated == null &&
      hidden == null &&
      body == null &&
      params.isEmpty &&
      responses.isEmpty;

  ExtractedRouteMetadata merge(ExtractedRouteMetadata other) {
    return ExtractedRouteMetadata(
      summary: summary ?? other.summary,
      description: description ?? other.description,
      tags: _mergeTags(tags, other.tags),
      operationId: operationId ?? other.operationId,
      deprecated: deprecated ?? other.deprecated,
      hidden: hidden ?? other.hidden,
      body: body ?? other.body,
      params: params.isNotEmpty ? params : other.params,
      responses: responses.isNotEmpty ? responses : other.responses,
    );
  }
}

Future<Map<String, ExtractedRouteMetadata>> extractRouteMetadataIndex(
  BuildStep buildStep,
) async {
  final assets = <AssetId>{};
  await for (final asset in buildStep.findAssets(Glob('lib/**.dart'))) {
    assets.add(asset);
  }
  await for (final asset in buildStep.findAssets(Glob('bin/**.dart'))) {
    assets.add(asset);
  }

  final index = <String, ExtractedRouteMetadata>{};
  for (final asset in assets) {
    if (asset.package != buildStep.inputId.package) continue;
    final source = await buildStep.readAsString(asset);
    final sourceAliases = <String>{asset.path};
    if (asset.path.startsWith('lib/')) {
      sourceAliases.add(
        'package:${buildStep.inputId.package}/${asset.path.substring(4)}',
      );
    }

    final perFile = extractRouteMetadataFromSource(
      source,
      sourcePaths: sourceAliases,
    );
    perFile.forEach((key, value) {
      final existing = index[key];
      index[key] = existing == null ? value : existing.merge(value);
    });
  }
  return index;
}

/// Extracts route metadata from Dart source files in a package directory.
Future<Map<String, ExtractedRouteMetadata>>
extractRouteMetadataIndexFromFileSystem({
  required String projectRoot,
  required String packageName,
}) async {
  final root = io.Directory(projectRoot);
  if (!root.existsSync()) {
    return const <String, ExtractedRouteMetadata>{};
  }

  final candidates = <io.File>[];
  for (final segment in const <String>['lib', 'bin']) {
    final dir = io.Directory(
      '${root.path}${io.Platform.pathSeparator}$segment',
    );
    if (!dir.existsSync()) continue;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is io.File && entity.path.endsWith('.dart')) {
        candidates.add(entity);
      }
    }
  }

  final index = <String, ExtractedRouteMetadata>{};
  for (final file in candidates) {
    final source = await file.readAsString();
    final aliases = _buildSourceAliases(
      filePath: file.path,
      projectRoot: root.path,
      packageName: packageName,
    );

    final perFile = extractRouteMetadataFromSource(
      source,
      sourcePaths: aliases,
    );
    perFile.forEach((key, value) {
      final existing = index[key];
      index[key] = existing == null ? value : existing.merge(value);
    });
  }

  return index;
}

Map<String, ExtractedRouteMetadata> extractRouteMetadataFromSource(
  String source, {
  Iterable<String> sourcePaths = const <String>[],
}) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _MetadataVisitor(
    lineInfo: parsed.lineInfo,
    sourcePaths: sourcePaths,
  );
  parsed.unit.accept(visitor);

  final merged = Map<String, ExtractedRouteMetadata>.from(visitor.collected);
  final dartdocFallback = _extractDartdocFallbackFromSource(source);
  dartdocFallback.forEach((key, value) {
    final existing = merged[key];
    final docOnly = ExtractedRouteMetadata(
      summary: value.summary,
      description: value.description,
    );
    merged[key] = existing == null ? docOnly : existing.merge(docOnly);
  });

  for (final ref in visitor.routeHandlerRefs) {
    final handlerMetadata =
        merged[ref.handlerName] ??
        merged[_normalizeFunctionRef(ref.handlerName)];
    if (handlerMetadata == null) continue;
    final current = merged[ref.routeKey];
    merged[ref.routeKey] = current == null
        ? handlerMetadata
        : current.merge(handlerMetadata);
  }

  return merged;
}

Map<String, ({String? summary, String? description})>
_extractDartdocFallbackFromSource(String source) {
  final result = <String, ({String? summary, String? description})>{};
  final regex = RegExp(
    r'((?:^[ \t]*///.*\n)+)[ \t]*(?:@[^\n]+\n[ \t]*)*(?:[\w<>,?\[\]\s]+)\s+([A-Za-z_]\w*)\s*\(',
    multiLine: true,
  );

  for (final match in regex.allMatches(source)) {
    final rawDoc = match.group(1);
    final name = match.group(2);
    if (rawDoc == null || name == null || name.isEmpty) continue;
    final parsedDoc = _parseDartdoc(null, fallbackCommentSource: rawDoc);
    if (parsedDoc.summary == null && parsedDoc.description == null) continue;
    result[name] = parsedDoc;
  }
  return result;
}

class _MetadataVisitor extends RecursiveAstVisitor<void> {
  _MetadataVisitor({
    required this.lineInfo,
    required Iterable<String> sourcePaths,
  }) : sourcePaths = sourcePaths
           .where((e) => e.isNotEmpty)
           .toList(growable: false);

  final LineInfo lineInfo;
  final List<String> sourcePaths;

  final Map<String, ExtractedRouteMetadata> collected = {};
  final List<({String routeKey, String handlerName})> routeHandlerRefs = [];
  final List<String> _classStack = <String>[];
  final List<String> _prefixStack = <String>[''];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // ignore: deprecated_member_use
    _classStack.add(node.name.lexeme);
    super.visitClassDeclaration(node);
    _classStack.removeLast();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.functionExpression.parameters == null) {
      super.visitFunctionDeclaration(node);
      return;
    }

    final metadata = _readDeclarationMetadata(
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      fallbackCommentSource: _leadingCommentSource(node),
    );
    _store(node.name.lexeme, metadata);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.parameters == null) {
      super.visitMethodDeclaration(node);
      return;
    }

    final metadata = _readDeclarationMetadata(
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      fallbackCommentSource: _leadingCommentSource(node),
    );

    final methodName = node.name.lexeme;
    _store(methodName, metadata);

    if (_classStack.isNotEmpty) {
      final qualified = '${_classStack.last}.$methodName';
      _store(qualified, metadata);
    }

    super.visitMethodDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_visitGroupInvocation(node)) {
      return;
    }

    final registrations = _extractRouteRegistrations(node);
    if (registrations.isNotEmpty) {
      final commentSource = _leadingCommentSource(
        node.parent is ExpressionStatement ? node.parent! : node,
      );
      final docs = _parseDartdoc(null, fallbackCommentSource: commentSource);
      final metadata = ExtractedRouteMetadata(
        summary: docs.summary,
        description: docs.description,
      );

      final handlerRef = _extractHandlerReference(node);

      for (final route in registrations) {
        final routeKey = 'route:${route.method} ${route.path}';
        _store(routeKey, metadata);
        final location = lineInfo.getLocation(node.methodName.offset);
        for (final sourcePath in sourcePaths) {
          final sourceKey =
              'source:$sourcePath:${location.lineNumber}:${location.columnNumber}';
          _store(sourceKey, metadata);
        }
        if (handlerRef != null && handlerRef.isNotEmpty) {
          routeHandlerRefs.add((routeKey: routeKey, handlerName: handlerRef));
        }
      }
    }

    super.visitMethodInvocation(node);
  }

  void _store(String key, ExtractedRouteMetadata metadata) {
    if (key.isEmpty || metadata.isEmpty) return;
    final existing = collected[key];
    collected[key] = existing == null ? metadata : existing.merge(metadata);
  }

  bool _visitGroupInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name != 'group') {
      return false;
    }

    final args = node.argumentList.arguments;
    final pathExpr =
        _namedExpression(args, 'path') ??
        (args.isNotEmpty ? _unwrapNamed(args.first) : null);
    final rawPrefix = _stringValue(pathExpr);

    final builderExpr = _namedExpression(args, 'builder');
    if (builderExpr is! FunctionExpression) {
      return false;
    }

    final nextPrefix = _joinPaths(_currentPrefix, rawPrefix ?? '');
    _prefixStack.add(nextPrefix);
    builderExpr.body.visitChildren(this);
    _prefixStack.removeLast();
    return true;
  }

  List<({String method, String path})> _extractRouteRegistrations(
    MethodInvocation node,
  ) {
    final name = node.methodName.name;
    final args = node.argumentList.arguments;

    if (name == 'handle') {
      if (args.length < 2) return const [];
      final method = _stringValue(_unwrapNamed(args[0]))?.toUpperCase();
      final rawPath = _stringValue(_unwrapNamed(args[1]));
      if (method == null || method.isEmpty || rawPath == null) return const [];
      return [(method: method, path: _joinPaths(_currentPrefix, rawPath))];
    }

    if (!_routeMethodNames.contains(name)) {
      return const [];
    }

    if (args.isEmpty) return const [];
    final rawPath = _stringValue(_unwrapNamed(args.first));
    if (rawPath == null) return const [];

    final path = _joinPaths(_currentPrefix, rawPath);
    if (name == 'any') {
      return _anyMethods
          .map((method) => (method: method, path: path))
          .toList(growable: false);
    }

    return [(method: name.toUpperCase(), path: path)];
  }

  String? _extractHandlerReference(MethodInvocation node) {
    final name = node.methodName.name;
    final args = node.argumentList.arguments;

    Expression? handler;
    if (name == 'handle') {
      if (args.length >= 3) {
        handler = _unwrapNamed(args[2]);
      }
    } else if (_routeMethodNames.contains(name)) {
      if (args.length >= 2) {
        handler = _unwrapNamed(args[1]);
      }
    }

    if (handler is SimpleIdentifier) {
      return handler.name;
    }
    if (handler is PrefixedIdentifier) {
      return '${handler.prefix.name}.${handler.identifier.name}';
    }
    if (handler is PropertyAccess) {
      return '${handler.target}.${handler.propertyName.name}';
    }
    return null;
  }

  String get _currentPrefix => _prefixStack.isEmpty ? '' : _prefixStack.last;
}

const Set<String> _routeMethodNames = {
  'get',
  'post',
  'put',
  'delete',
  'patch',
  'head',
  'options',
  'connect',
  'any',
};

const List<String> _anyMethods = [
  'GET',
  'POST',
  'PUT',
  'DELETE',
  'PATCH',
  'HEAD',
  'OPTIONS',
];

String _joinPaths(String prefix, String child) {
  final normalizedPrefix = prefix.trim();
  final normalizedChild = child.trim();

  if (normalizedPrefix.isEmpty || normalizedPrefix == '/') {
    if (normalizedChild.isEmpty) return '/';
    return normalizedChild.startsWith('/')
        ? normalizedChild
        : '/$normalizedChild';
  }

  if (normalizedChild.isEmpty || normalizedChild == '/') {
    return normalizedPrefix.startsWith('/')
        ? normalizedPrefix
        : '/$normalizedPrefix';
  }

  final left = normalizedPrefix.endsWith('/')
      ? normalizedPrefix.substring(0, normalizedPrefix.length - 1)
      : normalizedPrefix;
  final right = normalizedChild.startsWith('/')
      ? normalizedChild.substring(1)
      : normalizedChild;

  final full = '$left/$right';
  return full.startsWith('/') ? full : '/$full';
}

ExtractedRouteMetadata _readDeclarationMetadata({
  required NodeList<Annotation> metadata,
  required Comment? documentationComment,
  required String? fallbackCommentSource,
}) {
  String? summary;
  String? description;
  String? operationId;
  bool? deprecated;
  bool? hidden;
  BodySchema? body;
  final tags = <String>[];
  final params = <ParamSchema>[];
  final responses = <ResponseSchema>[];

  final doc = _parseDartdoc(
    documentationComment,
    fallbackCommentSource: fallbackCommentSource,
  );
  summary = doc.summary;
  description = doc.description;

  for (final annotation in metadata) {
    final name = annotation.name.name;
    final args = annotation.arguments?.arguments ?? const <Expression>[];

    switch (name) {
      case 'Summary':
        summary = _firstStringArg(args) ?? summary;
      case 'Description':
        description = _firstStringArg(args) ?? description;
      case 'Tags':
        final list = _firstListArg(args)
            .map(_stringValue)
            .whereType<String>()
            .where((v) => v.isNotEmpty)
            .toList();
        tags.addAll(list);
      case 'OperationId':
        operationId = _firstStringArg(args) ?? operationId;
      case 'ApiDeprecated':
        deprecated = true;
        final message = _firstStringArg(args);
        if ((description == null || description.isEmpty) &&
            message != null &&
            message.isNotEmpty) {
          description = message;
        }
      case 'ApiHidden':
        hidden = true;
      case 'ApiResponse':
        final response = _parseApiResponse(args);
        if (response != null) {
          responses.add(response);
        }
      case 'ApiParam':
        final param = _parseApiParam(args);
        if (param != null) {
          params.add(param);
        }
      case 'ApiBody':
        body = _parseApiBody(args) ?? body;
    }
  }

  return ExtractedRouteMetadata(
    summary: summary,
    description: description,
    tags: _mergeTags(const <String>[], tags),
    operationId: operationId,
    deprecated: deprecated,
    hidden: hidden,
    body: body,
    params: params,
    responses: responses,
  );
}

({String? summary, String? description}) _parseDartdoc(
  Comment? comment, {
  required String? fallbackCommentSource,
}) {
  final rawSource = comment?.toSource() ?? fallbackCommentSource;
  if (rawSource == null || rawSource.trim().isEmpty) {
    return (summary: null, description: null);
  }

  var raw = rawSource;
  raw = raw
      .replaceAll(RegExp(r'^\s*/\*\*?', multiLine: true), '')
      .replaceAll(RegExp(r'\*/\s*$', multiLine: true), '');

  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .map((line) => line.replaceFirst(RegExp(r'^///\s?'), ''))
      .map((line) => line.replaceFirst(RegExp(r'^\*\s?'), ''))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  if (lines.isEmpty) {
    return (summary: null, description: null);
  }

  final summary = lines.first;
  final description = lines.length > 1 ? lines.skip(1).join('\n').trim() : null;
  return (summary: summary, description: description);
}

String? _leadingCommentSource(AstNode node) {
  final firstComment = node.beginToken.precedingComments;
  if (firstComment == null) return null;

  final parts = <String>[];
  Token? current = firstComment;
  while (current != null) {
    parts.add(current.lexeme);
    current = current.next;
  }
  if (parts.isEmpty) return null;
  return parts.join('\n');
}

ResponseSchema? _parseApiResponse(List<Expression> args) {
  if (args.isEmpty) return null;
  final statusCode = _intValue(_unwrapNamed(args.first));
  if (statusCode == null) return null;

  final description = _namedString(args, 'description') ?? '';
  final contentType = _namedString(args, 'contentType');
  final schema = _namedMap(args, 'schema');
  final headers = _namedMap(args, 'headers');

  return ResponseSchema(
    statusCode,
    description: description,
    contentType: contentType,
    jsonSchema: schema,
    headers: headers,
  );
}

ParamSchema? _parseApiParam(List<Expression> args) {
  if (args.isEmpty) return null;
  final name = _stringValue(_unwrapNamed(args.first));
  if (name == null || name.isEmpty) return null;

  final locationExpr = _namedExpression(args, 'location');
  final location = _parseParamLocation(locationExpr);

  return ParamSchema(
    name,
    location: location,
    description: _namedString(args, 'description') ?? '',
    required: _namedBool(args, 'required'),
    jsonSchema: _namedMap(args, 'schema'),
    example: _literalValue(_namedExpression(args, 'example')),
  );
}

BodySchema? _parseApiBody(List<Expression> args) {
  if (args.isEmpty) return null;
  return BodySchema(
    description: _namedString(args, 'description') ?? '',
    contentType: _namedString(args, 'contentType') ?? 'application/json',
    required: _namedBool(args, 'required') ?? false,
    jsonSchema: _namedMap(args, 'schema'),
  );
}

ParamLocation _parseParamLocation(Expression? expr) {
  if (expr is PrefixedIdentifier) {
    final name = expr.identifier.name;
    for (final candidate in ParamLocation.values) {
      if (candidate.name == name) return candidate;
    }
  }
  if (expr is PropertyAccess) {
    final name = expr.propertyName.name;
    for (final candidate in ParamLocation.values) {
      if (candidate.name == name) return candidate;
    }
  }
  return ParamLocation.query;
}

List<String> _mergeTags(List<String> a, List<String> b) {
  final merged = <String>[];
  for (final tag in [...a, ...b]) {
    if (tag.isEmpty || merged.contains(tag)) continue;
    merged.add(tag);
  }
  return merged;
}

String? _firstStringArg(List<Expression> args) {
  if (args.isEmpty) return null;
  return _stringValue(_unwrapNamed(args.first));
}

List<Expression> _firstListArg(List<Expression> args) {
  if (args.isEmpty) return const [];
  final expr = _unwrapNamed(args.first);
  if (expr is ListLiteral) {
    return expr.elements.whereType<Expression>().toList(growable: false);
  }
  return const [];
}

Expression _unwrapNamed(Expression expression) {
  if (expression is NamedExpression) return expression.expression;
  return expression;
}

Expression? _namedExpression(List<Expression> args, String name) {
  for (final arg in args) {
    if (arg is NamedExpression && arg.name.label.name == name) {
      return arg.expression;
    }
  }
  return null;
}

String? _namedString(List<Expression> args, String name) {
  final expr = _namedExpression(args, name);
  return _stringValue(expr);
}

bool? _namedBool(List<Expression> args, String name) {
  final expr = _namedExpression(args, name);
  if (expr is BooleanLiteral) return expr.value;
  return null;
}

Map<String, Object?>? _namedMap(List<Expression> args, String name) {
  final expr = _namedExpression(args, name);
  return _mapValue(expr);
}

String? _stringValue(Expression? expr) {
  if (expr is SimpleStringLiteral) return expr.value;
  return null;
}

int? _intValue(Expression? expr) {
  if (expr is IntegerLiteral) return expr.value;
  if (expr is SimpleIdentifier) {
    return int.tryParse(expr.name);
  }
  return null;
}

Map<String, Object?>? _mapValue(Expression? expr) {
  if (expr is! SetOrMapLiteral) return null;
  final map = <String, Object?>{};
  for (final element in expr.elements) {
    if (element is! MapLiteralEntry) continue;
    final keyValue = _literalValue(element.key);
    if (keyValue == null) continue;
    map[keyValue.toString()] = _literalValue(element.value);
  }
  return map;
}

Object? _literalValue(Expression? expr) {
  if (expr == null) return null;
  if (expr is SimpleStringLiteral) return expr.value;
  if (expr is IntegerLiteral) return expr.value;
  if (expr is DoubleLiteral) return expr.value;
  if (expr is BooleanLiteral) return expr.value;
  if (expr is NullLiteral) return null;
  if (expr is ListLiteral) {
    return expr.elements
        .whereType<Expression>()
        .map(_literalValue)
        .toList(growable: false);
  }
  if (expr is SetOrMapLiteral) {
    return _mapValue(expr);
  }
  if (expr is PrefixedIdentifier) {
    return expr.identifier.name;
  }
  if (expr is SimpleIdentifier) {
    return expr.name;
  }
  return null;
}

String _normalizeFunctionRef(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.contains('.')) {
    return trimmed.split('.').last;
  }
  return trimmed;
}

Set<String> _buildSourceAliases({
  required String filePath,
  required String projectRoot,
  required String packageName,
}) {
  final normalizedFile = filePath.replaceAll('\\', '/');
  final normalizedRoot = projectRoot.replaceAll('\\', '/');

  final aliases = <String>{normalizedFile};
  if (normalizedFile.startsWith('$normalizedRoot/')) {
    final relative = normalizedFile.substring(normalizedRoot.length + 1);
    aliases.add(relative);
    if (relative.startsWith('lib/')) {
      aliases.add('package:$packageName/${relative.substring(4)}');
    }
  }

  return aliases;
}
