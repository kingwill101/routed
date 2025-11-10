import 'package:routed/src/utils/deep_copy.dart';
import 'package:routed/src/utils/dot.dart';

Map<String, dynamic> _normalizeDynamicMap(Map<dynamic, dynamic> input) {
  final result = <String, dynamic>{};
  input.forEach((key, value) {
    if (key == null) return;
    result[key.toString()] = deepCopyValue(value);
  });
  return result;
}

/// Deeply merges [source] into [target], optionally overriding existing values.
void deepMerge(
  Map<String, dynamic> target,
  Map<String, dynamic> source, {
  bool override = true,
}) {
  final ctx = dot(target);
  source.forEach((key, value) {
    if (key.contains('.')) {
      if (override || !ctx.contains(key)) {
        ctx.set(key, deepCopyValue(value));
      }
      return;
    }
    if (value is Map<String, dynamic>) {
      final next = target[key];
      if (next is Map<String, dynamic>) {
        deepMerge(next, value, override: override);
      } else if (override || next == null) {
        final clone = <String, dynamic>{};
        deepMerge(clone, value, override: true);
        if (override || !target.containsKey(key)) {
          target[key] = clone;
        }
      }
      return;
    }
    if (value is Map) {
      final normalized = _normalizeDynamicMap(value);
      deepMerge(target, {key: normalized}, override: override);
      return;
    }
    if (value is Iterable) {
      if (override || !target.containsKey(key)) {
        target[key] = value.map(deepCopyValue).toList();
      }
      return;
    }
    if (override || !target.containsKey(key)) {
      target[key] = value;
    }
  });
}
