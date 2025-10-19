import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:server_testing/src/browser/page.dart';
import 'package:test/test.dart';

/// Integration test demonstrating enhanced Page functionality
/// with a realistic page object implementation
void main() {
  group('Page Integration Tests', () {
    late MockBrowser mockBrowser;
    late LoginPage loginPage;
    late DashboardPage dashboardPage;

    setUp(() {
      mockBrowser = MockBrowser();
      loginPage = LoginPage(mockBrowser);
      dashboardPage = DashboardPage(mockBrowser);
    });

    test('complete login workflow using enhanced Page methods', () async {
      // Navigate to login page and wait for it to load
      await loginPage.navigate();
      await loginPage.waitForLoad();

      // Fill login form using enhanced methods
      await loginPage.login('user@example.com', 'password123');

      // Navigate to dashboard and verify
      await dashboardPage.navigate();
      await dashboardPage.waitForLoad();
      await dashboardPage.assertOnPage();

      // Verify the sequence of actions
      expect(mockBrowser.actions, [
        'visit:/login',
        'waitForElement:body',
        'type:#email:user@example.com',
        'type:#password:password123',
        'click:#login-btn',
        'visit:/dashboard',
        'waitForElement:body',
        'assertUrlIs:/dashboard',
      ]);
    });

    test('page methods integrate seamlessly with browser interface', () async {
      // Mix page-specific methods with direct browser calls
      await loginPage.navigate();
      await loginPage.waitForLoad();

      // Use page convenience methods
      await loginPage.enterEmail('test@example.com');
      await loginPage.enterPassword('secret');

      // Mix with direct browser calls
      await mockBrowser.takeScreenshot('before-submit');

      // Use page method to submit
      await loginPage.submitLogin();

      // Verify mixed usage works correctly
      expect(mockBrowser.actions, [
        'visit:/login',
        'waitForElement:body',
        'type:#email:test@example.com',
        'type:#password:secret',
        'takeScreenshot:before-submit',
        'click:#login-btn',
      ]);
    });

    test('enhanced Page methods support async/await patterns', () async {
      // Test that page methods work properly with async/await
      await loginPage.navigate();

      // Sequential operations
      await loginPage.waitForLoad();
      await loginPage.enterEmail('async@example.com');
      await loginPage.enterPassword('await123');
      await loginPage.submitLogin();

      // Verify sequential execution
      expect(mockBrowser.actions, [
        'visit:/login',
        'waitForElement:body',
        'type:#email:async@example.com',
        'type:#password:await123',
        'click:#login-btn',
      ]);
    });

    test('page inheritance and method composition', () async {
      // Test that enhanced methods work in inherited page classes
      final adminPage = AdminLoginPage(mockBrowser);

      await adminPage.navigate();
      await adminPage.waitForLoad();
      await adminPage.loginAsAdmin('admin@example.com', 'admin123');

      expect(mockBrowser.actions, [
        'visit:/admin/login',
        'waitForElement:body',
        'type:#email:admin@example.com',
        'type:#password:admin123',
        'check:#admin-checkbox',
        'click:#login-btn',
      ]);
    });

    test('error handling in page methods', () async {
      // Test that page methods handle errors appropriately
      mockBrowser.shouldThrowOnAssert = true;

      await loginPage.navigate();

      // This should throw when assertOnPage is called
      expect(
        () async => await loginPage.assertOnPage(),
        throwsA(isA<Exception>()),
      );
    });
  });
}

/// Example login page using enhanced Page functionality
class LoginPage extends Page {
  LoginPage(super.browser);

  @override
  String get url => '/login';

  // Page element selectors
  String get emailField => '#email';

  String get passwordField => '#password';

  String get loginButton => '#login-btn';

  // Enhanced page methods using new convenience methods
  Future<void> login(String email, String password) async {
    await enterEmail(email);
    await enterPassword(password);
    await submitLogin();
  }

  Future<void> enterEmail(String email) async {
    await fillField(emailField, email);
  }

  Future<void> enterPassword(String password) async {
    await fillField(passwordField, password);
  }

  Future<void> submitLogin() async {
    await clickButton(loginButton);
  }
}

/// Example dashboard page
class DashboardPage extends Page {
  DashboardPage(super.browser);

  @override
  String get url => '/dashboard';
}

/// Example inherited page class
class AdminLoginPage extends LoginPage {
  AdminLoginPage(super.browser);

  @override
  String get url => '/admin/login';

  String get adminCheckbox => '#admin-checkbox';

  Future<void> loginAsAdmin(String email, String password) async {
    await enterEmail(email);
    await enterPassword(password);
    await browser.check(adminCheckbox); // Mix page and browser methods
    await submitLogin();
  }
}

/// Simple mock browser for testing
class MockBrowser implements Browser {
  final List<String> _actions = [];
  final Map<String, dynamic> _state = {};
  bool shouldThrowOnAssert = false;

  List<String> get actions => List.unmodifiable(_actions);

  @override
  Future<void> visit(String url) async {
    _actions.add('visit:$url');
    _state['currentUrl'] = url;
  }

  @override
  Future<void> type(String selector, String value) async {
    _actions.add('type:$selector:$value');
  }

  @override
  Future<void> click(String selector) async {
    _actions.add('click:$selector');
  }

  @override
  Future<void> waitForElement(String selector, {Duration? timeout}) async {
    _actions.add(
      'waitForElement:$selector${timeout != null ? ':${timeout.inMilliseconds}ms' : ''}',
    );
  }

  @override
  Future<Browser> assertUrlIs(String expectedUrl) async {
    _actions.add('assertUrlIs:$expectedUrl');
    if (shouldThrowOnAssert) {
      throw Exception('Mock assertion error');
    }
    if (_state['currentUrl'] != expectedUrl) {
      throw Exception(
        'Expected URL $expectedUrl but was ${_state['currentUrl']}',
      );
    }
    return this;
  }

  @override
  Future<void> takeScreenshot([String? name]) async {
    _actions.add('takeScreenshot:${name ?? 'auto'}');
  }

  @override
  Future<void> check(String selector) async {
    _actions.add('check:$selector');
  }

  // Minimal implementations for other required methods
  @override
  noSuchMethod(Invocation invocation) {
    final methodName = invocation.memberName
        .toString()
        .replaceAll('Symbol("', '')
        .replaceAll('")', '');
    _actions.add('$methodName:called');

    if (methodName.startsWith('assert') || methodName.startsWith('should')) {
      return Future<dynamic>.value(this);
    }
    return Future<void>.value();
  }
}
