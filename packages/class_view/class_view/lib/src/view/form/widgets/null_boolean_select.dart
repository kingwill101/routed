import 'select.dart';

/// A Select Widget intended to be used with NullBooleanField.
class NullBooleanSelect extends Select {
  NullBooleanSelect({super.attrs})
    : super(
        choices: [
          ['', 'Unknown'],
          ['true', 'Yes'],
          ['false', 'No'],
        ],
      );

  @override
  List<String> formatValue(dynamic value) {
    const valueMap = {
      true: 'true',
      false: 'false',
      'true': 'true',
      'false': 'false',
      '2': 'true', // For backwards compatibility
      '3': 'false', // For backwards compatibility
    };
    return [valueMap[value] ?? ''];
  }

  @override
  bool isValueSelected(dynamic optionValue, dynamic value) {
    if (value == null) {
      return optionValue == '';
    }
    const valueMap = {
      true: 'true',
      false: 'false',
      'true': 'true',
      'false': 'false',
      '2': 'true', // For backwards compatibility
      '3': 'false', // For backwards compatibility
    };
    return optionValue == valueMap[value];
  }

  @override
  dynamic valueFromData(Map<String, dynamic> data, String name) {
    final value = data[name];
    const valueMap = {
      true: true,
      'True': true,
      'False': false,
      false: false,
      'true': true,
      'false': false,
      '2': true, // For backwards compatibility
      '3': false, // For backwards compatibility
    };
    return valueMap[value];
  }
}
