import 'package:mockito/mockito.dart';
import 'package:server_testing/src/browser/component.dart';
import 'package:test/test.dart';

import '../_support/mocks_component.mocks.dart';

class TestComponent extends Component {
  TestComponent(super.browser, super.selector);
}

void main() {
  group('Component with Mockito', () {
    test(
      'scoped click and type call Browser with composed selectors',
      () async {
        final browser = MockSyncBrowser();
        when(browser.click(any)).thenAnswer((_) async {});
        when(browser.type(any, any)).thenAnswer((_) async {});
        when(browser.isPresent(any)).thenReturn(true);

        final c = TestComponent(browser, '#root');
        await c.click('.child');
        await c.type('input', 'abc');

        verify(browser.click('#root .child')).called(1);
        verify(browser.type('#root input', 'abc')).called(1);
      },
    );

    test(
      'assert helpers use Browser.isPresent with scoped selectors',
      () async {
        final browser = MockSyncBrowser();
        when(browser.isPresent('#root')).thenReturn(true);
        when(browser.isPresent('#root .item')).thenReturn(true);

        final c = TestComponent(browser, '#root');
        await c.assertPresent();
        await c.assertHas('.item');

        verify(browser.isPresent('#root')).called(1);
        verify(browser.isPresent('#root .item')).called(1);
      },
    );
  });
}
