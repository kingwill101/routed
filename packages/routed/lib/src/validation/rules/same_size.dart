import 'package:routed/src/validation/context_aware_rule.dart';

class SameSizeRule extends ContextAwareValidationRule {
  @override
  String get name => 'same_size';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must have the same size as ${options[0]}.';
    }
    return 'The field must have the same size as the specified value.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;
    if (contextValues == null) return false;

    final otherFieldName = options[0];
    if (!contextValues!.containsKey(otherFieldName)) return false;

    final otherValue = contextValues![otherFieldName];
    if (value is String && otherValue is String) {
      return value.length == otherValue.length;
    } else if (value is List && otherValue is List) {
      return value.length == otherValue.length;
    } else if (value is Map && otherValue is Map) {
      return value.length == otherValue.length;
    } else if (value is num && otherValue is num) {
      return value == otherValue;
    }
    return false;
  }
}
