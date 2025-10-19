import 'select.dart';

/// A widget for multiple select fields.
///
/// Renders as: `<select multiple ...>`.
class SelectMultiple extends Select {
  SelectMultiple({super.attrs, required super.choices})
    : super(allowMultipleSelected: true);

  @override
  dynamic valueFromData(Map<String, dynamic> data, String name) {
    if (data[name] is List) {
      return List<String>.from(data[name] as Iterable<dynamic>);
    }
    return data[name];
  }

  @override
  bool valueOmittedFromData(Map<String, dynamic> data, String name) {
    // An unselected <select multiple> doesn't appear in POST data, so it's
    // never known if the value is actually omitted.
    return false;
  }
}
