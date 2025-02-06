import 'dart:async';

abstract class DialogHandler {
  FutureOr<void> waitForDialog([Duration? timeout]);
  FutureOr<void> acceptDialog();
  FutureOr<void> dismissDialog();
  FutureOr<void> typeInDialog(String text);
  FutureOr<void> assertDialogOpened(String message);
}
