/// Shared utilities for routed analyzer rules.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// HTTP route registration method names on Router and Engine.
const routeMethodNames = {
  'get',
  'post',
  'put',
  'delete',
  'patch',
  'head',
  'options',
  'connect',
  'handle',
};

/// Checks if a [MethodInvocation] is a route registration call on a Router
/// or Engine (or any class that has a `schema` named parameter of type
/// `RouteSchema?`).
bool isRouteRegistration(MethodInvocation node) {
  final name = node.methodName.name;
  if (!routeMethodNames.contains(name)) return false;

  // Verify the method has a 'schema' named parameter of type RouteSchema.
  final methodElement = node.methodName.element;
  if (methodElement is! ExecutableElement) return false;

  return methodElement.formalParameters.any(
    (p) => p.isNamed && p.name == 'schema' && _isRouteSchemaType(p.type),
  );
}

/// Checks if an [InstanceCreationExpression] creates a `RouteSchema`.
bool isRouteSchemaCreation(InstanceCreationExpression node) {
  final type = node.staticType;
  if (type == null) return false;
  return _isRouteSchemaType(type);
}

/// Returns the `schema:` named argument from a route method invocation,
/// or null if not provided.
NamedExpression? getSchemaArgument(MethodInvocation node) {
  return node.argumentList.arguments
      .whereType<NamedExpression>()
      .where((arg) => arg.name.label.name == 'schema')
      .firstOrNull;
}

/// Returns a named argument by name from an argument list.
NamedExpression? getNamedArgument(ArgumentList argumentList, String name) {
  return argumentList.arguments
      .whereType<NamedExpression>()
      .where((arg) => arg.name.label.name == name)
      .firstOrNull;
}

/// Checks whether the given [type] is `RouteSchema` from the routed package.
bool _isRouteSchemaType(DartType type) {
  if (type is! InterfaceType) return false;
  final element = type.element;
  if (element.name != 'RouteSchema') return false;
  final uri = element.library.uri;
  return uri.scheme == 'package' && uri.pathSegments.first == 'routed';
}
