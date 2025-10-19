import 'dart:async';

abstract class Keyboard {
  FutureOr<Keyboard> type(List<String> keys);

  FutureOr<Keyboard> press(String key);

  FutureOr<Keyboard> release(String key);

  FutureOr<Keyboard> sendModifier(String modifier, String key);

  FutureOr<Keyboard> pause([int milliseconds = 100]);
}
