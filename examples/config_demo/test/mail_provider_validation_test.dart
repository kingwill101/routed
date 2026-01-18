import 'package:config_demo/providers/mail_provider.dart';
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('MailProvider validation', () {
    test('throws descriptive error when port is invalid', () {
      expect(
        () => Engine(
          providers: [
            CoreServiceProvider(
              configItems: {
                'mail': {'port': 'abc'},
              },
            ),
            MailProvider(),
          ],
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('mail.port must be an integer'),
          ),
        ),
      );
    });
  });
}
