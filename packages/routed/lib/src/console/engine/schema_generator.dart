import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

class SchemaGenerator {
  final Map<String, Map<String, Object?>> schemas = {};

  Map<String, Object?> generate(DartType type) {
    if (type.isDartCoreString) {
      return {'type': 'string'};
    } else if (type.isDartCoreInt) {
      return {'type': 'integer'};
    } else if (type.isDartCoreDouble || type.isDartCoreNum) {
      return {'type': 'number'};
    } else if (type.isDartCoreBool) {
      return {'type': 'boolean'};
    } else if (type.isDartCoreList) {
      if (type is InterfaceType && type.typeArguments.isNotEmpty) {
        final typeArg = type.typeArguments.first;
        return {'type': 'array', 'items': generate(typeArg)};
      }
      return {'type': 'array'};
    } else if (type.isDartCoreMap) {
      return {'type': 'object'};
    } else if (type is VoidType) {
      return {};
    }

    final element = type.element;
    if (element is ClassElement) {
      final name = element.name ?? 'Unknown';
      if (schemas.containsKey(name)) {
        return {'\$ref': '#/components/schemas/$name'};
      }

      // Placeholder to avoid infinite recursion
      schemas[name] = {};

      final properties = <String, Map<String, Object?>>{};
      for (final field in element.fields) {
        if (field.isStatic || field.isSynthetic) continue;
        properties[field.name ?? 'unknown'] = generate(field.type);
      }

      schemas[name] = {'type': 'object', 'properties': properties};

      return {'\$ref': '#/components/schemas/$name'};
    }

    return {'type': 'string'}; // Fallback
  }
}
