import 'package:routed/src/openapi/pipe_rule_converter.dart';
import 'package:test/test.dart';

void main() {
  group('PipeRuleSchemaConverter', () {
    group('convertRules', () {
      test('converts basic string rules to JSON Schema', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'name': 'required|string|min:2|max:100',
        });

        expect(schema['type'], 'object');
        expect(schema['required'], ['name']);

        final props = schema['properties'] as Map<String, Object?>;
        final nameProp = props['name'] as Map<String, Object?>;
        expect(nameProp['type'], 'string');
        expect(nameProp['minLength'], 2);
        expect(nameProp['maxLength'], 100);
      });

      test('converts email rule with format', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'email': 'required|email',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final emailProp = props['email'] as Map<String, Object?>;
        expect(emailProp['type'], 'string');
        expect(emailProp['format'], 'email');
        expect(schema['required'], ['email']);
      });

      test('converts integer rules', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'age': 'integer|min:0|max:150',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final ageProp = props['age'] as Map<String, Object?>;
        expect(ageProp['type'], 'integer');
        expect(ageProp['minimum'], 0);
        expect(ageProp['maximum'], 150);
        // Not required — no 'required' in rules
        expect(schema['required'], isNull);
      });

      test('converts multiple fields', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'name': 'required|string|min:2',
          'email': 'required|email',
          'age': 'int',
          'bio': 'string|max:500',
        });

        expect(schema['required'], unorderedEquals(['name', 'email']));
        final props = schema['properties'] as Map<String, Object?>;
        expect(props, hasLength(4));
      });

      test('converts enum values with in rule', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'role': 'required|in:admin,editor,viewer',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final roleProp = props['role'] as Map<String, Object?>;
        expect(roleProp['type'], 'string');
        expect(roleProp['enum'], ['admin', 'editor', 'viewer']);
      });

      test('converts url rule', () {
        final schema = PipeRuleSchemaConverter.convertRules({'website': 'url'});

        final props = schema['properties'] as Map<String, Object?>;
        final siteProp = props['website'] as Map<String, Object?>;
        expect(siteProp['type'], 'string');
        expect(siteProp['format'], 'uri');
      });

      test('converts uuid rule', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'id': 'required|uuid',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final idProp = props['id'] as Map<String, Object?>;
        expect(idProp['type'], 'string');
        expect(idProp['format'], 'uuid');
      });

      test('converts boolean rule', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'active': 'boolean',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final activeProp = props['active'] as Map<String, Object?>;
        expect(activeProp['type'], 'boolean');
      });

      test('converts alpha_dash pattern rule', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'username': 'required|alpha_dash',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final userProp = props['username'] as Map<String, Object?>;
        expect(userProp['type'], 'string');
        expect(userProp['pattern'], r'^[a-zA-Z0-9_-]+$');
      });

      test('converts between rule for numbers', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'score': 'numeric|between:1,100',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final scoreProp = props['score'] as Map<String, Object?>;
        expect(scoreProp['type'], 'number');
        expect(scoreProp['minimum'], 1);
        expect(scoreProp['maximum'], 100);
      });

      test('converts array rule with distinct', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'tags': 'array|distinct',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final tagsProp = props['tags'] as Map<String, Object?>;
        expect(tagsProp['type'], 'array');
        expect(tagsProp['uniqueItems'], true);
      });

      test('converts ip rules', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'server_ip': 'ipv4',
          'server_ipv6': 'ipv6',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final v4Prop = props['server_ip'] as Map<String, Object?>;
        expect(v4Prop['format'], 'ipv4');
        final v6Prop = props['server_ipv6'] as Map<String, Object?>;
        expect(v6Prop['format'], 'ipv6');
      });

      test('converts multiple_of rule', () {
        final schema = PipeRuleSchemaConverter.convertRules({
          'quantity': 'int|multiple_of:5',
        });

        final props = schema['properties'] as Map<String, Object?>;
        final qtyProp = props['quantity'] as Map<String, Object?>;
        expect(qtyProp['type'], 'integer');
        expect(qtyProp['multipleOf'], 5);
      });
    });

    group('convertSingleRule', () {
      test('converts a single field rule', () {
        final schema = PipeRuleSchemaConverter.convertSingleRule(
          'string|min:1|max:50',
        );
        expect(schema['type'], 'string');
        expect(schema['minLength'], 1);
        expect(schema['maxLength'], 50);
      });

      test('handles date format', () {
        final schema = PipeRuleSchemaConverter.convertSingleRule('date');
        expect(schema['type'], 'string');
        expect(schema['format'], 'date');
      });
    });
  });
}
