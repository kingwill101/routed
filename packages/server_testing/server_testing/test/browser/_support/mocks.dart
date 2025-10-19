import 'dart:convert';

import 'package:webdriver/sync_core.dart'
    show WebDriver, WebElement, By, Attributes;

/// Mock Attributes implementation
class MockAttributes implements Attributes {
  final Map<String, String> _attrs;

  MockAttributes(this._attrs);

  @override
  String? operator [](String name) => _attrs[name];

  @override
  noSuchMethod(Invocation invocation) => null;
}

/// Simple mock WebDriver for testing SyncBrowser convenience methods
class MockSyncWebDriver implements WebDriver {
  // 1x1 PNG (black pixel)
  static const _png1x1Base64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6XkLcUAAAAASUVORK5CYII=';
  final List<String> _actions = [];
  final Set<String> _existingElements = {};
  String _currentUrl = 'http://localhost:8080';
  String _pageTitle = 'Test Page';

  String _pageSource = '<html><body>Test content</body></html>';

  List<String> get actions => List.unmodifiable(_actions);

  @override
  String get currentUrl {
    _actions.add('getCurrentUrl');
    return _currentUrl;
  }

  @override
  String get pageSource {
    _actions.add('getPageSource');
    return _pageSource;
  }

  @override
  String get title {
    _actions.add('getTitle');
    return _pageTitle;
  }

  void addElement(String selector) => _existingElements.add(selector);

  @override
  void back() => _actions.add('back');

  @override
  String captureScreenshotAsBase64() {
    _actions.add('captureScreenshot');
    return _png1x1Base64;
  }

  // WebDriver API in manager expects captureScreenshotAsList()
  @override
  List<int> captureScreenshotAsList() {
    _actions.add('captureScreenshot');
    return List<int>.from(base64Decode(_png1x1Base64));
  }

  @override
  dynamic execute(String script, List<dynamic> args) {
    _actions.add('execute:$script');
    return 'script_result';
  }

  @override
  WebElement findElement(By by) {
    _actions.add('findElement:${by.toString()}');
    final selector = by.toString();

    if (!_existingElements.contains(selector) &&
        !selector.contains('cssSelector') &&
        !selector.contains('partialLinkText') &&
        !selector.contains('tagName')) {
      throw Exception('Element not found: $selector');
    }

    return MockWebElement(selector);
  }

  @override
  void forward() => _actions.add('forward');

  @override
  void get(Object url) {
    _actions.add('get:${url.toString()}');
    _currentUrl = url.toString();
  }

  @override
  noSuchMethod(Invocation invocation) => null;

  @override
  void quit({bool closeSession = true}) => _actions.add('quit');

  @override
  void refresh() => _actions.add('refresh');

  void setCurrentUrl(String url) => _currentUrl = url;

  void setPageSource(String source) => _pageSource = source;

  void setPageTitle(String title) => _pageTitle = title;
}

/// Simple mock WebElement for testing
class MockWebElement implements WebElement {
  final String selector;
  bool _selected = false;
  String _text = '';
  final Map<String, String> _attributes = {};

  MockWebElement(this.selector);

  @override
  Attributes get attributes => MockAttributes(_attributes);

  @override
  bool get selected => _selected;

  @override
  String get text => _text;

  @override
  void clear() {}

  @override
  void click() {}

  @override
  WebElement findElement(By by) {
    return MockWebElement('$selector > ${by.toString()}');
  }

  @override
  noSuchMethod(Invocation invocation) => null;

  @override
  void sendKeys(String keys) {}

  void setAttribute(String name, String value) => _attributes[name] = value;

  void setSelected(bool selected) => _selected = selected;

  void setText(String text) => _text = text;
}
