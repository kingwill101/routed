import 'browser.dart';

class Keyboard {
  final Browser browser;

  Keyboard(this.browser);

  Future<Keyboard> type(List<String> keys) async {
    for (final key in keys) {
      await browser.driver.keyboard.sendKeys(key);
    }
    return this;
  }

  Future<Keyboard> press(String key) async {
    await browser.driver.keyboard.sendKeys(key);
    // Since webdriver doesn't have direct press/release,
    // we simulate it by sending the key
    return this;
  }

  Future<Keyboard> release(String key) async {
    // In webdriver, keys are automatically released after sendKeys
    // This method is kept for API compatibility
    return this;
  }

  Future<Keyboard> pause([int milliseconds = 100]) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
    return this;
  }

  // Special key combinations
  Future<Keyboard> sendModifier(String modifier, String key) async {
    await browser.driver.keyboard.sendChord([modifier, key]);
    return this;
  }

  // Support for keyboard macros
  static final _macros = <String, Future<void> Function(Keyboard)>{};

  static void macro(String name, Future<void> Function(Keyboard) callback) {
    _macros[name] = callback;
  }

  Future<void> runMacro(String name) async {
    final macro = _macros[name];
    if (macro == null) {
      throw Exception('Keyboard macro "$name" not found');
    }
    await macro(this);
  }
}
