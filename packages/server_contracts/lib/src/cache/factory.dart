import 'repository.dart';

abstract class Factory {
  Repository store([String? name]);
}
