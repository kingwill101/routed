
import 'dart:async';

import 'package:routed_testing/src/browser/interfaces/browser.dart';

abstract class Page {
  final Browser browser;

  Page(this.browser);

  String get url;

  FutureOr<void> navigate() => browser.visit(url);

  Future<void> assertOnPage() async {
    await browser.assertUrlIs(url);
  }
}
