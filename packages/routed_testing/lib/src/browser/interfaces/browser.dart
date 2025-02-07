import 'dart:async';

import 'package:routed_testing/src/browser/interfaces/assertions.dart';
import 'package:routed_testing/src/browser/interfaces/dialog.dart';
import 'package:routed_testing/src/browser/interfaces/frame.dart';
import 'package:routed_testing/src/browser/interfaces/keyboard.dart';
import 'package:routed_testing/src/browser/interfaces/mouse.dart';
import 'package:routed_testing/src/browser/interfaces/waiter.dart';
import 'package:routed_testing/src/browser/interfaces/window.dart';

import 'cookie.dart';
import 'download.dart';
import 'emulation.dart';
import 'local_storage.dart';
import 'network.dart';
import 'session_storage.dart';

mixin Browser on BrowserAssertions {
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

  Cookie get cookies;

  LocalStorage get localStorage;

  SessionStorage get sessionStorage;

  Keyboard get keyboard;

  Mouse get mouse;

  DialogHandler get dialogs;

  FrameHandler get frames;

  WindowManager get window;

  BrowserWaiter get waiter;

  Network get network;

  Emulation get emulation;

  Download get download;

  FutureOr<void> quit();
}
