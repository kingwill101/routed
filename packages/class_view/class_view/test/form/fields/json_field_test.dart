import 'dart:convert';

import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('JSONField Tests', () {
    test('valid JSON input', () async {
      final field = JSONField();
      final value = await field.clean('{"a": "b"}');
      expect(value, equals({"a": "b"}));
    });

    test('valid empty values', () async {
      final field = JSONField(required: false);
      expect(await field.clean(""), isNull);
      expect(await field.clean(null), isNull);
    });

    test('invalid JSON', () async {
      final field = JSONField();
      expect(
        () => field.clean("{some badly formed: json}"),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['invalid']![0],
            'error message',
            'Enter a valid JSON.',
          ),
        ),
      );
    });

    test('prepare value', () {
      final field = JSONField();
      expect(field.prepareValue({"a": "b"}), '{"a":"b"}');
      expect(field.prepareValue(null), 'null');
      expect(field.prepareValue("foo"), '"foo"');
      expect(field.prepareValue("你好，世界"), '"你好，世界"');
      expect(field.prepareValue({"a": "😀🐱"}), '{"a":"😀🐱"}');
      expect(field.prepareValue(["你好，世界", "jaźń"]), '["你好，世界","jaźń"]');
    });

    test('widget defaults to Textarea', () {
      final field = JSONField();
      expect(field.widget, isA<Textarea>());
    });

    test('custom widget in constructor', () {
      final field = JSONField(widget: TextInput());
      expect(field.widget, isA<TextInput>());
    });

    test('converted value', () async {
      final field = JSONField(required: false);
      final tests = [
        '["a", "b", "c"]',
        '{"a": 1, "b": 2}',
        '1',
        '1.5',
        '"foo"',
        'true',
        'false',
        'null',
      ];

      for (final jsonString in tests) {
        final val = await field.clean(jsonString);
        final cleaned = await field.clean(val);
        expect(cleaned, equals(val), reason: 'Failed for $jsonString');
      }
    });

    test('has changed', () {
      final field = JSONField();
      expect(field.hasChanged({"a": true}, '{"a": 1}'), isTrue);
      expect(field.hasChanged({"a": 1, "b": 2}, '{"b": 2, "a": 1}'), isFalse);
    });

    test('custom encoder decoder', () async {
      // Create a custom encoder/decoder for UUID handling
      Object? convertToJson(dynamic obj) {
        if (obj is TestUuid) {
          return {'uuid': obj.value};
        }
        return obj;
      }

      final customEncoder = JsonEncoder(convertToJson);
      // Create a reviver function that handles both Map and primitive cases
      reviver(key, value) {
        if (value is Map && value.containsKey('uuid')) {
          return TestUuid(value['uuid'] as String);
        }
        return value;
      }

      final customDecoder = JsonDecoder(reviver);

      final field = JSONField(encoder: customEncoder, decoder: customDecoder);

      final value = TestUuid('c141e152-6550-4172-a784-05448d98204b');
      final encodedValue = '{"uuid":"c141e152-6550-4172-a784-05448d98204b"}';

      expect(field.prepareValue(value), equals(encodedValue));

      final cleaned = await field.clean(encodedValue);
      expect(cleaned, isA<TestUuid>());
      expect(
        (cleaned as TestUuid).value,
        equals('c141e152-6550-4172-a784-05448d98204b'),
      );
    });

    test('disabled field', () {
      final field = JSONField(disabled: true);
      expect(field.prepareValue(['foo']), equals('["foo"]'));
    });

    test('redisplay null input', () async {
      final field = JSONField(required: true);

      expect(field.prepareValue(null), equals('null'));

      expect(
        () => field.clean(null),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['required']![0],
            'error message',
            'This field is required.',
          ),
        ),
      );
    });

    test('redisplay wrong input', () async {
      final field = JSONField();

      // Valid JSON
      expect(field.prepareValue(['foo']), equals('["foo"]'));

      // Invalid JSON should throw validation error but preserve the input
      expect(
        () => field.clean('{"foo"}'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['invalid']![0],
            'error message',
            'Enter a valid JSON.',
          ),
        ),
      );
    });
  });
}

/// Test class to simulate UUID handling
class TestUuid {
  final String value;

  TestUuid(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestUuid &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}
