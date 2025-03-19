import 'package:routed/src/binding/multipart.dart';
import 'package:routed/src/validation/abstract_rule.dart';

class FileBetweenRule extends AbstractValidationRule {
  @override
  String get name => 'file_between';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.length == 2) {
      return 'The file size must be between ${options[0]} and ${options[1]} kilobytes.';
    }
    return 'The file size must be between the specified values.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null ||
        options == null ||
        options.length != 2 ||
        value is! MultipartFile) {
      return false;
    }

    final minSize = int.tryParse(options[0]) ?? 0;
    final maxSize = int.tryParse(options[1]) ?? 0;
    final fileSize = (value).size / 1024; // Size in KB

    return fileSize >= minSize && fileSize <= maxSize;
  }
}
