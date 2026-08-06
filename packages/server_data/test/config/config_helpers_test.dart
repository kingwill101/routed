import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

void main() {
  engineTest('config helpers access current zone configuration', (
    engine,
    client,
  ) async {
    await engine.initialize();

    await AppZone.run(
      engine: engine,
      body: () async {
        final override = ConfigImpl({
          'app': {'name': 'Helper App'},
        });

        await withConfig(override, () async {
          expect(configValue<String>('app.name'), equals('Helper App'));
          expect(configValueOrThrow<String>('app.name'), equals('Helper App'));
          expect(configNamespace('app'), containsPair('name', 'Helper App'));
        });

        expect(configValue<String>('app.name'), equals('Test App'));
      },
    );
  });
}
