import 'dart:async';

abstract class Response {
  FutureOr<int> status();

  FutureOr<Map<String, String>> headers();

  FutureOr<dynamic> body(); // Could be String, List<int>, or Map
}
