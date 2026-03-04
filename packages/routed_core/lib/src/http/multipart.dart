/// Configuration for handling multipart file uploads.
///
/// This class controls limits and behavior for file uploads through multipart
/// form data. It helps protect against denial-of-service attacks and ensures
/// uploaded files meet security requirements.
class MultipartConfig {
  /// Maximum memory size allowed for file uploads in bytes.
  ///
  /// This limits how much memory can be used for buffering uploads before
  /// they are written to disk. Default is 32MB.
  int maxMemory;

  /// Maximum file size allowed for individual uploads in bytes.
  ///
  /// Any file exceeding this size will be rejected. Default is 10MB.
  int maxFileSize;

  /// Maximum total disk usage per request in bytes.
  ///
  /// This limits the total size of all files in a single request.
  /// Default mirrors [maxMemory].
  int maxDiskUsage;

  /// Set of allowed file extensions for uploads.
  ///
  /// Only files with these extensions will be accepted. Extensions should be
  /// lowercase without the leading dot.
  Set<String> allowedExtensions;

  /// Directory where uploaded files will be stored.
  ///
  /// This path is relative to the application root. Default is 'uploads'.
  final String uploadDirectory;

  /// File permissions for uploaded files in octal notation.
  ///
  /// Default is 0750 (owner: read/write/execute, group: read/execute, others: none).
  final int filePermissions;

  /// Creates a multipart configuration with the given settings.
  MultipartConfig({
    this.maxMemory = 32 * 1024 * 1024,
    this.maxFileSize = 10 * 1024 * 1024,
    int? maxDiskUsage,
    this.allowedExtensions = const {'jpg', 'jpeg', 'png', 'gif', 'pdf'},
    this.uploadDirectory = 'uploads',
    this.filePermissions = 0750,
  }) : maxDiskUsage = maxDiskUsage ?? maxMemory;
}
