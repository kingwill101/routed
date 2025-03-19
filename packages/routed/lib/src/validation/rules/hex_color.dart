import 'package:routed/src/validation/rule.dart';

class HexColorRule extends ValidationRule {
  @override
  String get name => 'hex_color';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be a valid hexadecimal color code.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return RegExp(r'^#([0-9a-fA-F]{3}){1,2}$').hasMatch(value.toString());
  }
}
