import 'dart:async';

import 'package:routed_testing/src/browser/interfaces/browser.dart';

abstract class FrameHandler {
  FutureOr<void> withinFrame(String selector, Function(Browser) callback);
}
