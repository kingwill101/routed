import 'package:routed_testing/routed_testing.dart';

class NavMenu extends Component {
  NavMenu(Browser browser) : super(browser, 'nav.main-menu');

  Future<void> assertUserMenuVisible() async {
    await browser.assertPresent('.user-menu');
  }

  Future<void> logout() async {
    await browser.click('.user-menu');
    await browser.click('a.logout-button');
  }
}