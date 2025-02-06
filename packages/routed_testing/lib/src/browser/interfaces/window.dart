import 'dart:async';

abstract class WindowManager {
  FutureOr<void> resize(int width, int height);
  FutureOr<void> maximize();
  FutureOr<void> fitContent();
  FutureOr<void> move(int x, int y);
}
