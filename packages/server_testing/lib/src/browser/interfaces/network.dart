import 'dart:async';

import 'request.dart';
import 'response.dart';

abstract class Network {
  FutureOr<void> route(
      String url, FutureOr<Response> Function(Request) handler);

  FutureOr<void> unroute(String url);

  FutureOr<Request> waitForRequest(String url, {Duration? timeout});

  FutureOr<Response> waitForResponse(String url, {Duration? timeout});
}
