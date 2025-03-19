import 'dart:async';

abstract class BrowserWaiter {
  FutureOr<void> wait(Duration timeout);
  FutureOr<void> waitFor(String selector, [Duration? timeout]);
  FutureOr<void> waitUntilMissing(String selector, [Duration? timeout]);
  FutureOr<void> waitForText(String text, [Duration? timeout]);
  FutureOr<void> waitForLocation(String path, [Duration? timeout]);
  FutureOr<void> waitForReload(Function() callback);
}
