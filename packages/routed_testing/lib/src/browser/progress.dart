class BrowserDownloadProgress {
  final int received;
  final int total;
  final double percent;

  const BrowserDownloadProgress({
    required this.received,
    required this.total,
    required this.percent,
  });

  @override
  String toString() {
    final mb = (received / 1024 / 1024).toStringAsFixed(1);
    final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
    return '$mb MB / $totalMb MB (${percent.toStringAsFixed(1)}%)';
  }
}
