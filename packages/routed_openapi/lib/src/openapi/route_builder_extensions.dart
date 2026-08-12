import 'package:routed_core/routed_core.dart';

import 'schema.dart';

/// Route metadata key used by the OpenAPI integration.
const openApiSchemaKey = RouteMetadataKey<RouteSchema>('routed.openapi.schema');

/// Fluent OpenAPI metadata extensions for [RouteBuilder].
extension OpenApiRouteBuilderExtensions on RouteBuilder {
  /// Attaches a complete OpenAPI route schema.
  RouteBuilder schema(RouteSchema value) => metadata(openApiSchemaKey, value);

  /// Sets the operation summary.
  RouteBuilder summary(String value) =>
      schema(_currentSchema().copyWith(summary: value));

  /// Sets the operation description.
  RouteBuilder description(String value) =>
      schema(_currentSchema().copyWith(description: value));

  /// Sets the OpenAPI tags.
  RouteBuilder tags(Iterable<String> values) =>
      schema(_currentSchema().copyWith(tags: values.toList()));

  /// Sets the operation id.
  RouteBuilder operationId(String value) =>
      schema(_currentSchema().copyWith(operationId: value));

  /// Marks the operation deprecated.
  RouteBuilder deprecated([bool value = true]) =>
      schema(_currentSchema().copyWith(deprecated: value));

  /// Hides the route from generated documents.
  RouteBuilder hidden([bool value = true]) =>
      schema(_currentSchema().copyWith(hidden: value));

  /// Adds request body metadata.
  RouteBuilder requestSchema(BodySchema value) =>
      schema(_currentSchema().copyWith(body: value));

  /// Adds a response schema.
  RouteBuilder responseSchema(ResponseSchema value) {
    final current = _currentSchema();
    return schema(current.copyWith(responses: [...?current.responses, value]));
  }

  RouteSchema _currentSchema() =>
      metadataValue(openApiSchemaKey) ?? const RouteSchema();
}
