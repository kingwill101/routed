import 'dart:async';

abstract class Request {
  FutureOr<String> url();

  FutureOr<String> method();

  FutureOr<Map<String, String>> headers();

  FutureOr<dynamic> body(); // Could be String, List<int>, or Map
}
