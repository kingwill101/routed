import 'package:server_testing/server_testing.dart';

class LoginPage extends Page {
  LoginPage(super.browser);

  @override
  String get url => '/login';

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await browser.type('input[name="email"]', email);
    await browser.type('input[name="password"]', password);
    await browser.click('button[type="submit"]');
  }

  Future<void> assertHasError(String message) async {
    await browser.assertSeeIn('.alert-error', message);
  }
}
