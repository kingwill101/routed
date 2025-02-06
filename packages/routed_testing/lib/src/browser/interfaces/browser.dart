import 'dart:async';

import 'package:routed_testing/src/browser/interfaces/assertions.dart';


mixin Browser on BrowserAssertions{
  FutureOr<void> visit(String url);
  FutureOr<void> back();
  FutureOr<void> forward();
  FutureOr<void> refresh();

  FutureOr<void> click(String selector);
  FutureOr<void> type(String selector, String value);

  FutureOr<dynamic> findElement(String selector);
  FutureOr<bool> isPresent(String selector);

  FutureOr<String> getPageSource();
  FutureOr<String> getCurrentUrl();
  FutureOr<String> getTitle();

  FutureOr<dynamic> executeScript(String script);

  FutureOr<void> waitUntil(
    FutureOr<bool> Function() predicate, {
    Duration? timeout,
    Duration interval = const Duration(milliseconds: 100),
  });

  FutureOr<void> quit();
}
