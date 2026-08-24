import 'repository.dart';

/// Creates cache repositories for named stores.
abstract class Factory {
  /// Returns a repository for [name], or the default repository when omitted.
  Repository store([String? name]);
}
