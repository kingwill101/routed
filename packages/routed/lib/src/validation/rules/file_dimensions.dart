import 'package:routed/src/validation/rule.dart';

class FileDimensionsRule extends ValidationRule {
  @override
  String get name => 'file_dimensions';

  @override
  String message(dynamic value, [List<String>? options]) {
    //  Implement specific error messages for width, height, ratio
    return 'The image must meet the specified dimension constraints.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    // Implement image dimension checks here
    return false;
  }
}
