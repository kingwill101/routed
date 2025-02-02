import 'repository.dart';

abstract class Factory {
  /// Returns a cache store instance by name.
  ///
  /// If [name] is not provided, the default cache store is returned.
  Repository store([String? name]);
}
