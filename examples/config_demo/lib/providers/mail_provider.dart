import 'package:routed/routed.dart';

class MailConfig implements ValidatableConfiguration {
  const MailConfig({
    this.driver = 'smtp',
    this.host = 'localhost',
    this.port = 2525,
    this.from = 'noreply@example.dev',
  });

  final String driver;
  final String host;
  final int port;
  final String from;

  @override
  void validate(ConfigValidationContext context) {
    context.require(driver.trim().isNotEmpty, 'driver', 'cannot be empty');
    context.require(host.trim().isNotEmpty, 'host', 'cannot be empty');
    context.require(
      port > 0 && port <= 65535,
      'port',
      'must be between 1 and 65535',
    );
    context.require(from.trim().isNotEmpty, 'from', 'cannot be empty');
  }
}

class MailService {
  const MailService(this.configuration);

  final MailConfig configuration;

  String get host => configuration.host;
  int get port => configuration.port;
}

class MailProvider extends ServiceProvider
    with ProvidesTypedConfiguration<MailConfig> {
  MailProvider([MailConfig? configuration])
    : configuration = configuration ?? const MailConfig();

  @override
  final MailConfig configuration;

  @override
  void register(Container container) {
    container.singleton<MailService>((_) async => MailService(configuration));
  }
}
