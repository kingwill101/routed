import 'package:routed/src/container/container.dart';
import 'package:routed/src/validation/context_aware_rule.dart';
import 'package:routed/src/validation/rule.dart';
import 'package:routed/src/validation/rules/required.dart';
import 'package:routed/src/validation/validator.dart';
import 'package:test/test.dart';

class _PassRule extends ValidationRule {
  @override
  String get name => 'pass';

  @override
  String message(dynamic value, [List<String>? options]) => 'pass';

  @override
  bool validate(dynamic value, [List<String>? options]) => true;
}

class _OptionsRule extends ValidationRule {
  @override
  String get name => 'options';

  @override
  String message(dynamic value, [List<String>? options]) => 'options';

  @override
  bool validate(dynamic value, [List<String>? options]) => true;
}

class _MatchesFieldRule extends ContextAwareValidationRule {
  @override
  String get name => 'matches';

  @override
  String message(dynamic value, [List<String>? options]) {
    final field = options?.isNotEmpty == true ? options!.first : 'field';
    return 'Must match $field.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    final otherField = options?.isNotEmpty == true ? options!.first : null;
    if (otherField == null) {
      return false;
    }
    return contextValues?[otherField] == value;
  }
}

void main() {
  group('Validation subsystem', () {
    test('ValidationRuleRegistry defaults register core rules', () {
      final registry = ValidationRuleRegistry.defaults();

      expect(registry.contains('required'), isTrue);
      expect(registry.names, contains('string'));
    });

    test('ValidationRuleRegistry clone keeps registered factories', () {
      final registry = ValidationRuleRegistry();
      registry.register(() => _PassRule());

      final clone = ValidationRuleRegistry.clone(registry);

      expect(clone.contains('pass'), isTrue);
      expect(clone.resolve('pass'), isNotNull);
    });

    test('requireValidationRegistry surfaces missing bindings', () {
      final container = Container();

      expect(
        () => requireValidationRegistry(container),
        throwsA(isA<StateError>()),
      );

      final registry = ValidationRuleRegistry.defaults();
      container.instance(registry);

      expect(requireValidationRegistry(container), same(registry));
    });

    test('parseRules splits options and resolves rules', () {
      final registry = ValidationRuleRegistry();
      registry
        ..register(() => _OptionsRule())
        ..register(() => RequiredRule());

      final parsed = parseRules({'field': 'options:a,b|required'}, registry);
      final rules = parsed['field'];

      expect(rules, isNotNull);
      expect(rules, hasLength(2));
      expect(rules!.first.rule.name, 'options');
      expect(rules.first.options, ['a', 'b']);
      expect(rules.last.rule.name, 'required');
      expect(rules.last.options, isNull);
    });

    test('parseRules throws for unknown rule names', () {
      final registry = ValidationRuleRegistry();

      expect(
        () => parseRules({'field': 'unknown'}, registry),
        throwsA(isA<Exception>()),
      );
    });

    test('Validator applies context-aware rules and overrides', () {
      final registry = ValidationRuleRegistry();
      registry.register(() => _MatchesFieldRule());

      final validator = Validator.make(
        {'confirm': 'matches:password'},
        registry: registry,
        messages: {'confirm.matches': 'Confirmation does not match.'},
      );

      final errors = validator.validate({
        'password': 'secret',
        'confirm': 'nope',
      });

      expect(errors['confirm'], ['Confirmation does not match.']);

      final passErrors = validator.validate({
        'password': 'secret',
        'confirm': 'secret',
      });

      expect(passErrors, isEmpty);
    });

    test('Validator bail stops after first field failure', () {
      final registry = ValidationRuleRegistry.defaults();
      final validator = Validator.make(
        {'first': 'required', 'second': 'required'},
        registry: registry,
        bail: true,
      );

      final errors = validator.validate({'first': '', 'second': ''});

      expect(errors.keys, ['first']);
    });
  });
}
