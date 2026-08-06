library;
export 'package:routed_storage/routed_storage.dart' show Dir, FileHandler;

// Compatibility stub - real implementation moved to routed_storage.
class Dir {
  Dir(String path, {bool listDirectory = false, dynamic fileSystem});
}

class FileHandler {
  FileHandler(String path, {dynamic fileSystem});
}
