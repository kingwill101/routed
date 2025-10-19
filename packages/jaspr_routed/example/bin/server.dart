import 'package:jaspr/server.dart' as jaspr;
import 'package:jaspr_routed/jaspr_routed.dart';
import 'package:jaspr_routed_example/components/home.dart';
import 'package:jaspr_routed_example/jaspr_options.dart';
import 'package:routed/routed.dart' as routed;

Future<void> main(List<String> args) async {
  jaspr.Jaspr.initializeApp(options: defaultJasprOptions);

  final engine = await routed.Engine.create();

  engine.get(
    '/{*anything}',
    jasprRoute((ctx) {
      return jaspr.Document(
        title: 'Built with Routed & Jaspr',
        head: [
          jaspr.Component.element(
            tag: 'style',
            children: [jaspr.Component.text(_exampleStyles)],
          ),
        ],
        body: const Home(),
      );
    }),
  );

  await engine.serve(host: '127.0.0.1', port: 9000);
}

const _exampleStyles = '''
html {
  box-sizing: border-box;
  font-size: 14px;
  font-family: Arial, Helvetica, sans-serif;
  background: #fdfdfd;
}

*, *:before, *:after {
  box-sizing: inherit;
}

body, h1, h2, h3, h4, h5, h6, p, ol, ul {
  margin: 0;
  padding: 0;
  font-weight: normal;
}

ol, ul {
  list-style: none;
}

img {
  max-width: 100%;
  height: auto;
}

body {
  padding: 16px;
  background: radial-gradient(#f0f0f5, #d9e4f5);
}

hr {
  margin: 16px 0;
  border: 0;
  height: 1px;
  background: #999;
}

.content {
  min-width: 300px;
  max-width: 420px;
  margin: 0 auto;
  background-color: white;
  border-radius: 8px;
  padding: 16px;
  box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2), 0 6px 20px rgba(0, 0, 0, 0.19);
}

.logo-box a {
  text-decoration: none;
  font-weight: bold;
  color: #666;
}

.logo-box {
  text-align: center;
}

.info-box p {
  margin-top: 2px;
}

.link-box {
  text-align: center;
  color: #999;
}

.link-box a {
  text-decoration: none;
  color: inherit;
}
''';
