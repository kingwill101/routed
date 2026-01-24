/// Container for shared Inertia props.
class InertiaSharedProps {
  final Map<String, dynamic> _props = {};

  bool get isEmpty => _props.isEmpty;

  Map<String, dynamic> all() => Map.unmodifiable(_props);

  void addAll(Map<String, dynamic> props) {
    _props.addAll(props);
  }

  void set(String key, dynamic value) {
    _props[key] = value;
  }
}
