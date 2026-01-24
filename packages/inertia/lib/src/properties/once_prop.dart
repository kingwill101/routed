import '../property_context.dart';
import 'inertia_prop.dart';

/// Property that is resolved once per instance and cached
class OnceProp<T> implements InertiaProp {
  OnceProp(this.resolver, {this.ttl});
  final T Function() resolver;
  final Duration? ttl;
  T? _cachedValue;
  DateTime? _expiresAt;

  @override
  bool shouldInclude(String key, PropertyContext context) => true;

  @override
  T resolve(String key, PropertyContext context) {
    if (_cachedValue != null && !_isExpired()) {
      return _cachedValue!;
    }

    _cachedValue = resolver();
    if (ttl != null) {
      _expiresAt = DateTime.now().add(ttl!);
    }
    return _cachedValue!;
  }

  bool _isExpired() {
    if (_expiresAt == null) return false;
    return DateTime.now().isAfter(_expiresAt!);
  }
}
