import 'package:routed/src/validation/rule.dart';
import 'package:routed/src/binding/multipart.dart';
import 'package:path/path.dart' as p;

class FileExtensionsRule extends ValidationRule {
  @override
  String get name => 'file_extensions';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The file must have one of the following extensions: ${options.join(', ')}.';
    }
    return 'The file must have a valid extension.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null ||
        options == null ||
        options.isEmpty ||
        value is! MultipartFile) {
      return false;
    }

    final fileExtension = p.extension((value).filename);

    return options.contains(fileExtension.replaceAll('.', ''));
  }
}
