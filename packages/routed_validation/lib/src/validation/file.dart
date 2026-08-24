/// Describes the file metadata consumed by file validation rules.
///
/// Multipart adapters can implement this small contract without depending on
/// the HTTP package used by the application. [isValidationFile] also accepts
/// compatible objects that expose the same three properties.
abstract class ValidationFile {
  /// The original client-provided filename, including its extension when one
  /// was supplied.
  String get filename;

  /// The file size in bytes.
  int get size;

  /// The MIME type reported by the multipart adapter.
  String get contentType;
}

// The duck-typed branch is required to support multipart implementations
// without coupling this public contract to one concrete HTTP package.
// ignore_for_file: avoid_dynamic_calls

/// Returns whether [value] can be consumed by a file validation rule.
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
  } on Object catch (_) {
    return false;
  }
}

/// Adapts [value] to [ValidationFile] when it exposes file metadata.
///
/// Returns `null` when [value] is neither a [ValidationFile] nor a compatible
/// duck-typed object. The returned adapter contains only the three public
/// metadata fields; it does not retain or read file contents.
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
  } on Object catch (_) {
    return null;
  }
}

class _DuckTypedValidationFile implements ValidationFile {
  _DuckTypedValidationFile({
    required this.filename,
    required this.size,
    required this.contentType,
  });
  @override
  final String filename;
  @override
  final int size;
  @override
  final String contentType;
}
