import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';

typedef FrameCallback = FutureOr<void> Function(Browser);

abstract class FrameHandler {
  FutureOr<void> withinFrame(String selector, FrameCallback callback);
}
