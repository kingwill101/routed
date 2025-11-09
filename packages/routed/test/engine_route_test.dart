import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import 'test_helpers.dart';

void main() {
  group('Engine route parameter patterns', () {
    final parameterSampleGen = _parameterSampleGenerator();

    test(
      'typed parameters handle valid and invalid payloads (property)',
      () async {
        final runner = PropertyTestRunner<ParameterSample>(parameterSampleGen, (
          sample,
        ) async {
          final engine = Engine()
            ..get(sample.caseInfo.route, (ctx) async {
              final dynamic value = ctx.params[sample.caseInfo.paramKey];
              ctx.json(<String, dynamic>{
                'value': value,
                'type': value.runtimeType.toString(),
              });
            });

          final client = TestClient(RoutedRequestHandler(engine));
          final response = await client.get(sample.path);

          if (sample.shouldMatch) {
            response.assertStatus(HttpStatus.ok);
            final payload = (response.json() as Map).cast<String, dynamic>();
            expect(payload['value'], equals(sample.expectedValue));
            expect(payload['type'], equals(sample.caseInfo.expectedTypeName));
          } else {
            response.assertStatus(HttpStatus.notFound);
          }

          await client.close();
          await engine.close();
        }, PropertyConfig(numTests: 40, seed: 20250310));

        final result = await runner.run();
        expect(result.success, isTrue, reason: result.report);
      },
    );
  });
}

typedef ParameterSample = ({
  ParameterCase caseInfo,
  String path,
  bool shouldMatch,
  dynamic expectedValue,
});

class ParameterCase {
  const ParameterCase({
    required this.name,
    required this.route,
    required this.paramKey,
    required this.validGen,
    required this.invalidGen,
    required this.encode,
    required this.normalize,
    required this.expectedTypeName,
  });

  final String name;
  final String route;
  final String paramKey;
  final Generator<dynamic> validGen;
  final Generator<String> invalidGen;
  final String Function(dynamic value) encode;
  final dynamic Function(dynamic value) normalize;
  final String expectedTypeName;

  String buildPath(String segment) =>
      route.replaceFirst(RegExp(r'\{[^}]+\}'), segment);
}

Generator<ParameterSample> _parameterSampleGenerator() {
  final cases = <ParameterCase>[
    ParameterCase(
      name: 'int',
      route: '/users/{id:int}',
      paramKey: 'id',
      validGen: Gen.integer(min: 0, max: 5000),
      invalidGen: Gen.frequency<String>([
        (1, Gen.integer(min: -5000, max: -1).map((value) => value.toString())),
        (
          2,
          Gen.string(
            minLength: 1,
            maxLength: 10,
          ).where((value) => int.tryParse(value) == null),
        ),
      ]),
      encode: (value) => (value as int).toString(),
      normalize: (value) => value as int,
      expectedTypeName: 'int',
    ),
    ParameterCase(
      name: 'double',
      route: '/price/{amount:double}',
      paramKey: 'amount',
      validGen: Gen.frequency<dynamic>([
        (3, Gen.double_(min: 0, max: 1000)),
        (2, Gen.integer(min: 0, max: 1000).map((value) => value.toDouble())),
      ]),
      invalidGen: Gen.frequency<String>([
        (1, Gen.integer(min: -1000, max: -1).map((value) => value.toString())),
        (
          2,
          Gen.string(
            minLength: 1,
            maxLength: 10,
          ).where((value) => double.tryParse(value) == null),
        ),
      ]),
      encode: (value) {
        final numVal = value as num;
        return numVal % 1 == 0 ? numVal.toInt().toString() : numVal.toString();
      },
      normalize: (value) => (value as num).toDouble(),
      expectedTypeName: 'double',
    ),
    ParameterCase(
      name: 'slug',
      route: '/posts/{slug:slug}',
      paramKey: 'slug',
      validGen: slugSegment(min: 3, max: 20),
      invalidGen: invalidSlugSegment(min: 3, max: 20),
      encode: (value) => value as String,
      normalize: (value) => value as String,
      expectedTypeName: 'String',
    ),
    ParameterCase(
      name: 'uuid',
      route: '/resources/{rid:uuid}',
      paramKey: 'rid',
      validGen: _uuidGen(),
      invalidGen: Gen.string(minLength: 8, maxLength: 20).where(
        (value) => !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(value.toLowerCase()),
      ),
      encode: (value) => value as String,
      normalize: (value) => value as String,
      expectedTypeName: 'String',
    ),
    ParameterCase(
      name: 'email',
      route: '/subscribe/{contact:email}',
      paramKey: 'contact',
      validGen: Specialized.email(),
      invalidGen: Gen.string(
        minLength: 3,
        maxLength: 18,
      ).where((value) => !value.contains('@') || value.endsWith('@')),
      encode: (value) => value as String,
      normalize: (value) => value as String,
      expectedTypeName: 'String',
    ),
  ];

  final caseGen = Gen.oneOf(cases);

  return caseGen.flatMap(
    (caseInfo) => Gen.boolean().flatMap((shouldMatch) {
      if (shouldMatch) {
        return caseInfo.validGen.map(
          (value) => (
            caseInfo: caseInfo,
            path: caseInfo.buildPath(caseInfo.encode(value)),
            shouldMatch: true,
            expectedValue: caseInfo.normalize(value),
          ),
        );
      }

      return caseInfo.invalidGen.map(
                (segment) =>
            (
            caseInfo: caseInfo,
            path: caseInfo.buildPath(segment),
            shouldMatch: false,
            expectedValue: null,
            ),
      );
    }),
  );
}

// Debug helper for manual sampling.
Generator<ParameterSample> debugParameterGenerator() =>
    _parameterSampleGenerator();

Generator<String> _uuidGen() {
  final hex = Gen.oneOf('0123456789abcdef'.split(''));

  Generator<String> segment(int length) => hex
      .list(minLength: length, maxLength: length)
      .map((chars) => chars.join());

  return segment(8).flatMap(
    (part1) => segment(4).flatMap(
      (part2) => segment(4).flatMap(
        (part3) => segment(4).flatMap(
          (part4) =>
              segment(12).map((part5) => '$part1-$part2-$part3-$part4-$part5'),
        ),
      ),
    ),
  );
}
