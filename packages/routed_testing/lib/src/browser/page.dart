import 'browser.dart';

abstract class Page {
  final Browser browser;

  Page(this.browser);

  String get url;

  Future<void> navigate() => browser.visit(url);

  Future<void> assertOnPage() async {
    await browser.assertUrlIs(url);
  }
}
