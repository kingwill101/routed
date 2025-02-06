import 'package:routed/src/contracts/config.dart/config.dart';

class ConfigImpl implements Config {
  final Map<String, dynamic> _items;

  ConfigImpl([Map<String, dynamic>? items]) : _items = items ?? {};

  @override
  bool has(String key) {
    return _items.containsKey(key);
  }

  @override
  dynamic get(String key, [dynamic defaultValue]) {
    return _items.containsKey(key) ? _items[key] : defaultValue;
  }

  @override
  Map<String, dynamic> all() {
    return _items;
  }

  @override
  void set(String key, dynamic value) {
    _items[key] = value;
  }

  @override
  void prepend(String key, dynamic value) {
    if (_items.containsKey(key) && _items[key] is List) {
      _items[key].insert(0, value);
    } else {
      _items[key] = [value];
    }
  }

  @override
  void push(String key, dynamic value) {
    if (_items.containsKey(key) && _items[key] is List) {
      _items[key].add(value);
    } else {
      _items[key] = [value];
    }
  }
}
