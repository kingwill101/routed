@Tags(['real-browser'])
library;

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

// A reusable LoginForm component
class LoginForm extends Component {
  LoginForm(super.browser, super.selector);

  String get email => 'input[name="email"]';

  String get password => 'input[name="password"]';

  String get submit => 'button[type="submit"]';

  Future<void> fill(String e, String p) async {
    await type(email, e);
    await type(password, p);
  }

  Future<void> submitForm() async => click(submit);
}

// A Page object that composes the LoginForm component
class LoginPage extends Page {
  LoginPage(super.browser);

  @override
  String get url => '/';

  LoginForm get form => LoginForm(browser, '#login');
}

void main() async {
  // Bootstrap the browser environment once
  await testBootstrap(
    BrowserConfig(
      browserName: 'firefox',
      headless: true,
      baseUrl: 'http://127.0.0.1:0',
      // will be overridden with ephemeral server port
      autoScreenshots: false,
    ),
  );

  // Minimal server that renders a simple login page
  final engine = Engine()
    ..get('/', (ctx) async {
      await ctx.html('''
      <html><head><title>Login</title></head>
      <body>
        <div id="login">
          <form>
            <input name="email" />
            <input name="password" />
            <button type="submit">Login</button>
          </form>
          <div class="flash" style="display:none">OK</div>
        </div>
        <script>
          document.querySelector('form').addEventListener('submit', function(e){
            e.preventDefault();
            document.querySelector('.flash').style.display='block';
            document.title = 'Dashboard';
          });
        </script>
      </body>
      </html>
      ''');
    });

  // Start ephemeral HTTP server and extract baseUrl before launching browser
  final handler = RoutedRequestHandler(engine);
  final client = TestClient.ephemeralServer(handler);
  final baseUrl = await client.baseUrlFuture;

  browserGroup(
    'Page + Component real browser',
    baseUrl: baseUrl,
    define: (getBrowser) {
      test('login flow works using Page + Component', () async {
        final browser = getBrowser();
        final page = LoginPage(browser);
        await page.navigate();
        await browser.assertTitle('Login');
        await page.form.fill('user@example.com', 'secret');
        await page.form.submitForm();
        await browser.assertTitle('Dashboard');
      });

      tearDownAll(() async {
        await client.close();
      });
    },
  );
}
