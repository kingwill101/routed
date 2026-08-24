import 'package:server_contracts/src/cache/repository.dart';

/// Creates cache repositories for named stores.
// A single method is intentional: this is the complete construction contract
// for a named repository factory.
// ignore: one_member_abstracts
abstract class Factory {
  /// Returns a repository for [name], or the default repository when omitted.
  Repository store([String? name]);
}
