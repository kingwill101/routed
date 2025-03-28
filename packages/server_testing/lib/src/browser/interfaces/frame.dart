import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';

abstract class FrameHandler {
  FutureOr<void> withinFrame(String selector, Function(Browser) callback);
}
