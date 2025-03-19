import 'dart:async';

abstract class Download {
  FutureOr<DownloadedFile> waitForDownload({Duration? timeout});
}

abstract class DownloadedFile {
  FutureOr<String> path();

  FutureOr<void> delete();
}
