/// Shared utilities for Routed analyzer rules.
///
/// These helpers deliberately use resolved analyzer elements and types. A
/// method is treated as a route registration only when its resolved signature
/// has a named `schema` parameter whose type is `RouteSchema`; a method with
/// the same name but a different signature is ignored.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Method names that may register HTTP routes on a Router or Engine.
///
/// `handle` is included because Routed exposes it as a catch-all route
/// registration method even though it is not an HTTP verb.
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

/// Returns whether [node] is a route registration with schema support.
///
/// The resolved method must use one of [routeMethodNames] and expose a named
/// `schema` parameter typed as `RouteSchema` or `RouteSchema?`.
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

/// Returns whether [node] creates a `RouteSchema` value.
bool isRouteSchemaCreation(InstanceCreationExpression node) {
  final type = node.staticType;
  if (type == null) return false;
  return _isRouteSchemaType(type);
}

/// Returns the `schema:` argument from [node], if one was provided.
NamedExpression? getSchemaArgument(MethodInvocation node) {
  return node.argumentList.arguments
      .whereType<NamedExpression>()
      .where((arg) => arg.name.label.name == 'schema')
      .firstOrNull;
}

/// Returns the named argument called [name], if one was provided.
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
