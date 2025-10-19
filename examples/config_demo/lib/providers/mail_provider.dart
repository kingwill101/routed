import 'package:routed/routed.dart';

class MailService {
  MailService(this.host, this.port);

  final String host;
  final int port;
}

class MailProvider extends ServiceProvider with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: const [
      ConfigDocEntry(
        path: 'mail.driver',
        type: 'string',
        description: 'Mail transport identifier (e.g. smtp).',
        defaultValue: 'smtp',
      ),
      ConfigDocEntry(
        path: 'mail.host',
        type: 'string',
        description: 'SMTP host used for outbound mail.',
        defaultValue: 'localhost',
      ),
      ConfigDocEntry(
        path: 'mail.port',
        type: 'int',
        description: 'SMTP port (defaults to 2525 for the demo).',
        defaultValue: 2525,
      ),
      ConfigDocEntry(
        path: 'mail.from',
        type: 'string',
        description: 'Sender address applied to outbound messages.',
        defaultValue: 'noreply@example.dev',
      ),
    ],
  );

  @override
  String get configSource => 'config_demo.mail';

  @override
  void register(Container container) {
    if (container.has<Config>()) {
      _validateConfig(container.get<Config>());
    }
    container.singleton<MailService>((c) async {
      final config = await c.make<Config>();
      final host = config.get('mail.host', 'localhost') as String;
      final port = config.get('mail.port', 2525) as int;
      return MailService(host, port);
    });
  }

  void _validateConfig(Config config) {
    Object? node;
    try {
      node = config.get('mail');
    } catch (_) {
      node = null;
    }
    if (node == null) {
      return;
    }
    if (node is! Map) {
      throw ProviderConfigException('mail must be a map');
    }
    final map = node.map((key, value) => MapEntry(key.toString(), value));

    final hostNode = map['host'];
    if (hostNode != null) {
      if (hostNode is! String) {
        throw ProviderConfigException('mail.host must be a string');
      }
      final trimmed = hostNode.trim();
      if (trimmed.isEmpty) {
        throw ProviderConfigException('mail.host must be a string');
      }
      config.set('mail.host', trimmed);
    }

    final portNode = map['port'];
    if (portNode != null) {
      config.set('mail.port', _readPort(portNode));
    }

    final fromNode = map['from'];
    if (fromNode != null) {
      if (fromNode is! String) {
        throw ProviderConfigException('mail.from must be a string');
      }
      final trimmed = fromNode.trim();
      if (trimmed.isEmpty) {
        throw ProviderConfigException('mail.from must be a string');
      }
      config.set('mail.from', trimmed);
    }
  }

  int _readPort(Object value) {
    if (value is int) {
      if (value <= 0 || value > 65535) {
        throw ProviderConfigException('mail.port must be between 1 and 65535');
      }
      return value;
    }
    if (value is String) {
      final trimmed = value.trim();
      final parsed = int.tryParse(trimmed);
      if (parsed == null) {
        throw ProviderConfigException('mail.port must be an integer');
      }
      return _readPort(parsed);
    }
    throw ProviderConfigException('mail.port must be an integer');
  }
}
