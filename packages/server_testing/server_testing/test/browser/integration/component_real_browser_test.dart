library;

import 'dart:io';

import 'package:server_testing/server_testing.dart';

import '../_support/real_browser_bootstrap.dart';

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

void main() {
  group('Component real browser', () {
    late TestClient client;
    late String baseUrl;

    // Minimal server that renders a simple login page using dart:io
    Future<void> handleRequest(HttpRequest request) async {
      if (request.uri.path == '/' && request.method == 'GET') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('''
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
        await request.response.close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found');
        await request.response.close();
      }
    }

    setUpAll(() async {
      await realBrowserBootstrap(
        BrowserConfig(
          browserName: 'firefox',
          headless: true,
          baseUrl: 'http://127.0.0.1:0',
          // will be overwritten with ephemeral port
          autoScreenshots: false,
        ),
      );

      // Start a real HTTP server and get its base URL before launching browser
      final handler = IoRequestHandler(handleRequest);
      client = TestClient.ephemeralServer(handler);
      baseUrl = await client.baseUrlFuture;
    });

    tearDownAll(() async {
      await client.close();
      await realBrowserCleanup();
    });

    browserTest('serves page and component operates', (browser) async {
      final page = LoginForm(browser, '#login');
      await browser.visit(baseUrl);
      await browser.assertTitle('Login');
      await page.fill('a@b.c', 'secret');
      await page.submitForm();
      await browser.assertTitle('Dashboard');
    });
  });
}
