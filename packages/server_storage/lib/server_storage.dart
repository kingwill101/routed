/// Framework-neutral storage disks and static-file serving primitives.
///
/// The package provides a small registry, [StorageManager], for named disks;
/// local and cloud-backed disk implementations; and [FileHandler] for serving
/// files through a [StaticFileSink]. It does not create an HTTP server, bind
/// an application container, or choose a web framework.
///
/// Configure a manager during application startup, then pass the same manager
/// to the framework adapter or to application services:
///
/// ```dart
/// final manager = StorageManager()
///   ..registerDisk('local', LocalStorageDisk(root: 'storage/app'))
///   ..setDefault('local');
///
/// final path = manager.resolve('avatars/user-1.png');
/// ```
///
/// [LocalStorageDisk] normalizes its root and rejects absolute paths or
/// relative paths that escape that root. Treat request-derived path segments
/// as untrusted and resolve them through the disk rather than joining them to
/// a root yourself. Static-file serving uses the same principle: pass a
/// request-relative path to [FileHandler.serveFile].
library;

import 'package:server_storage/src/file_handler.dart' show FileHandler;
import 'package:server_storage/src/static_file_sink.dart' show StaticFileSink;
import 'package:server_storage/src/storage.dart' show LocalStorageDisk;
import 'package:server_storage/src/storage_manager.dart' show StorageManager;

export 'src/file_handler.dart';
export 'src/static_file_sink.dart';
export 'src/storage.dart';
export 'src/storage_manager.dart';
