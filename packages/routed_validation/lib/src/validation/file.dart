abstract class ValidationFile {
  String get filename;
  int get size;
  String get contentType;
}

/// Returns true if [value] is a [ValidationFile] or a duck-typed file
/// object such as `MultipartFile` from `routed_http`.
///
/// The historical `MultipartFile` does not implement [ValidationFile] but
/// has the same `filename`, `size`, and `contentType` properties. This
/// helper allows file rules to accept both without creating a hard
/// dependency from `routed_validation` to `routed_http`.
bool isValidationFile(dynamic value) {
  if (value is ValidationFile) return true;
  if (value == null) return false;
  try {
    final dynamic v = value;
    final filename = v.filename;
    final size = v.size;
    final contentType = v.contentType;
    return filename is String && size is int && contentType is String;
  } catch (_) {
    return false;
  }
}

/// Extracts file properties from a [ValidationFile] or duck-typed file.
/// Returns null if not a file.
ValidationFile? asValidationFile(dynamic value) {
  if (value is ValidationFile) return value;
  if (!isValidationFile(value)) return null;
  try {
    final dynamic v = value;
    return _DuckTypedValidationFile(
      filename: v.filename as String,
      size: v.size as int,
      contentType: v.contentType as String,
    );
  } catch (_) {
    return null;
  }
}

class _DuckTypedValidationFile implements ValidationFile {
  @override
  final String filename;
  @override
  final int size;
  @override
  final String contentType;

  _DuckTypedValidationFile({
    required this.filename,
    required this.size,
    required this.contentType,
  });
}
