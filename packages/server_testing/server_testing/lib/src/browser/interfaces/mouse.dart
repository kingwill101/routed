import 'dart:async';

abstract class Mouse {
  FutureOr<Mouse> clickAndHold([String? selector]);

  FutureOr<Mouse> releaseMouse();

  FutureOr<Mouse> moveTo(String selector);

  FutureOr<Mouse> dragTo(String selector);

  FutureOr<Mouse> dragOffset(int x, int y);

  FutureOr<Mouse> moveToOffset(String selector, {int? xOffset, int? yOffset});
}
