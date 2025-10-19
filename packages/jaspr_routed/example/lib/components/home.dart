import 'package:jaspr/server.dart' as jaspr;

import 'package:jaspr_routed_example/components/counter.dart';

class Home extends jaspr.StatelessComponent {
  const Home({super.key});

  @override
  jaspr.Component build(jaspr.BuildContext context) {
    return jaspr.div(classes: 'content', [
      jaspr.div(classes: 'logo-box', [
        jaspr.img(
          src:
              'https://raw.githubusercontent.com/schultek/jaspr/main/examples/backend_serverpod/example_server/web/images/serverpod-logo.svg',
          width: 160,
          styles: jaspr.Styles(
            margin: jaspr.Margin.only(top: 8.px, bottom: 12.px),
          ),
        ),
        jaspr.p([
          jaspr.a(href: 'https://serverpod.dev/', [
            jaspr.text('Serverpod + Jaspr'),
          ]),
        ]),
      ]),
      jaspr.hr(),
      jaspr.div(classes: 'info-box', [
        jaspr.p([jaspr.text('Served at ${DateTime.now()}')]),
        jaspr.div(id: 'counter', [const Counter()]),
      ]),
      jaspr.hr(),
      jaspr.div(classes: 'link-box', [
        jaspr.a(href: 'https://serverpod.dev', [jaspr.text('Serverpod')]),
        jaspr.text(' • '),
        jaspr.a(href: 'https://docs.serverpod.dev', [
          jaspr.text('Get Started'),
        ]),
        jaspr.text(' • '),
        jaspr.a(href: 'https://github.com/serverpod/serverpod', [
          jaspr.text('Github'),
        ]),
      ]),
      jaspr.div(classes: 'link-box', [
        jaspr.a(href: 'https://docs.jaspr.site', [jaspr.text('Jaspr')]),
        jaspr.text(' • '),
        jaspr.a(href: 'https://docs.jaspr.site/quick-start', [
          jaspr.text('Get Started'),
        ]),
        jaspr.text(' • '),
        jaspr.a(href: 'https://github.com/schultek/jaspr', [
          jaspr.text('Github'),
        ]),
      ]),
    ]);
  }
}
