import 'package:routed_testing/src/assertable_json/assertable_json_string.dart';
import 'package:test/test.dart';

void main() {
  group('AssertableJsonString', () {
    test('Constructs with JSON string', () {
      final jsonString = '{"key": "value"}';
      final jsonStringTest = AssertableJsonString(jsonString);

      expect(jsonStringTest.decoded, equals({'key': 'value'}));
    });

    test('Constructs with Map<String, dynamic>', () {
      final jsonData = {'key': 'value'};
      final jsonStringTest = AssertableJsonString(jsonData);

      expect(jsonStringTest.decoded, equals(jsonData));
    });

    test('jsonPath returns correct value', () {
      final jsonData = {
        'key': {'nestedKey': 'nestedValue'}
      };
      final jsonStringTest = AssertableJsonString(jsonData);

      expect(jsonStringTest.jsonPath('key.nestedKey'), equals('nestedValue'));
    });

    test('assertCount passes with correct count', () {
      final jsonData = {'key1': 'value1', 'key2': 'value2'};
      final jsonStringTest = AssertableJsonString(jsonData);
      jsonStringTest.assertCount(2);
    });

    test('assertFragment passes with existing fragment', () {
      final jsonData = {
        'key1': 'value1',
        'key2': {'nested': 'value2'}
      };
      final jsonStringTest = AssertableJsonString(jsonData);

      jsonStringTest.assertFragment({'key1': 'value1'});
      jsonStringTest.assertFragment({
        'key2': {'nested': 'value2'}
      });
    });

    test('assertStructure passes with matching structure', () {
      final jsonData = {
        'key1': {'nested1': 'value1'},
        'key2': {'nested2': 'value2'}
      };
      final structure = {
        'key1': {'nested1': null},
        'key2': {'nested2': null}
      };
      final jsonStringTest = AssertableJsonString(jsonData);

      jsonStringTest.assertStructure(structure);
    });

    test('assertCount fails with incorrect count', () {
      final jsonData = {'key1': 'value1'};
      final jsonStringTest = AssertableJsonString(jsonData);

      expect(
        () => jsonStringTest.assertCount(2),
        throwsA(isA<TestFailure>()),
      );
    });

    test('assertExact passes with identical data', () {
      final jsonData = {'key': 'value'};
      final jsonStringTest = AssertableJsonString(jsonData);

      jsonStringTest.assertExact({'key': 'value'});
    });

    test('assertExact fails with different data', () {
      final jsonData = {'key': 'value'};
      final jsonStringTest = AssertableJsonString(jsonData);

      expect(
        () => jsonStringTest.assertExact({'key': 'differentValue'}),
        throwsA(isA<TestFailure>()),
      );
    });

    // New tests for wildcard support
    test('Validates structure of all objects in an array', () {
      final jsonData = {
        'users': [
          {'name': 'Alice', 'age': 25, 'location': 'New York'},
          {'name': 'Bob', 'age': 30, 'location': 'San Francisco'},
        ],
      };
      final jsonStringTest = AssertableJsonString(jsonData);

      jsonStringTest.assertStructure({
        'users': {
          '*': [
            'name',
            'age',
            'location',
          ],
        }
      });
    });

    test('Fails if any object in the array is missing a required field', () {
      final jsonData = {
        'users': [
          {'name': 'Alice', 'age': 25},
          {'name': 'Bob', 'age': 30, 'location': 'San Francisco'},
        ],
      };
      final jsonStringTest = AssertableJsonString(jsonData);

      expect(
        () => jsonStringTest.assertStructure({
          'users': {
            '*': [
              'name',
              'age',
              'location',
            ],
          }
        }),
        throwsA(isA<TestFailure>()),
      );
    });

    test('Fails if the target is not an array', () {
      final jsonData = {
        'users': {'name': 'Alice', 'age': 25, 'location': 'New York'},
      };
      final jsonStringTest = AssertableJsonString(jsonData);

      expect(
        () => jsonStringTest.assertStructure({
          'users': {
            '*': [
              'name',
              'age',
              'location',
            ],
          }
        }),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
