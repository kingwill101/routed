import 'package:config_demo/providers/mail_provider.dart';
import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create(
    runtime: RuntimeContext(
      environment: RuntimeEnvironment({'APP_ENV': 'development'}),
    ),
    providers: [
      ...Engine.defaultProviders,
      MailProvider(
        const MailConfig(
          host: 'mail.example.test',
          port: 2525,
          from: 'demo@example.test',
        ),
      ),
    ],
  );

  engine.get('/', (ctx) async {
    final mail = ctx.config<MailConfig>();
    final service = await ctx.container.make<MailService>();

    return ctx.json({
      'environment': 'development',
      'mail': {
        'driver': mail.driver,
        'host': service.host,
        'port': service.port,
        'from': mail.from,
      },
    });
  });

  engine.get('/configuration', (ctx) {
    final mail = ctx.config<MailConfig>();
    return ctx.json({
      'configuration_type': 'MailConfig',
      'mail_host': mail.host,
      'mail_port': mail.port,
    });
  });

  return engine;
}
