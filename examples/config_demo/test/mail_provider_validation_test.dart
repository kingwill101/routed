import 'package:config_demo/providers/mail_provider.dart';
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test('validates the typed mail configuration before boot', () {
    expect(
      () =>
          ConfigStore.fromProviders([MailProvider(const MailConfig(port: 0))]),
      throwsA(
        isA<ConfigValidationException>().having(
          (error) => error.issues.single.toString(),
          'issue',
          contains('port: must be between 1 and 65535'),
        ),
      ),
    );
  });
}
