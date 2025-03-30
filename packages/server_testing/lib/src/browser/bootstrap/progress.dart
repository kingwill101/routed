/// Represents the progress of a browser archive download operation.
///
/// Contains the number of bytes received, the total expected bytes, and the
/// calculated percentage completion.
class BrowserDownloadProgress {
  /// The number of bytes received so far.
  final int received;
  /// The total expected size of the download in bytes. May be 0 if unknown.
  final int total;
  /// The download progress as a percentage (0.0 to 100.0).
  final double percent;

  /// Creates a constant [BrowserDownloadProgress] instance.
  const BrowserDownloadProgress({
    required this.received,
    required this.total,
    required this.percent,
  });

  /// Returns a user-friendly string representation of the download progress,
  /// showing megabytes received out of total and the percentage.
  @override
  String toString() {
    final mb = (received / 1024 / 1024).toStringAsFixed(1);
    final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
    return '$mb MB / $totalMb MB (${percent.toStringAsFixed(1)}%)';
  }
}
