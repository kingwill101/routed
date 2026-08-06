import 'package:routed/src/binding/multipart.dart';
import 'package:routed/src/validation/context_aware_rule.dart';
import 'package:routed/src/validation/rules/accepted.dart';
import 'package:routed/src/validation/rules/active_url.dart';
import 'package:routed/src/validation/rules/after.dart';
import 'package:routed/src/validation/rules/after_or_equal.dart';
import 'package:routed/src/validation/rules/alpha.dart';
import 'package:routed/src/validation/rules/alpha_dash.dart';
import 'package:routed/src/validation/rules/alpha_num.dart';
import 'package:routed/src/validation/rules/array.dart';
import 'package:routed/src/validation/rules/ascii.dart';
import 'package:routed/src/validation/rules/before.dart';
import 'package:routed/src/validation/rules/before_or_equal.dart';
import 'package:routed/src/validation/rules/between.dart';
import 'package:routed/src/validation/rules/boolean.dart';
import 'package:routed/src/validation/rules/confirmed.dart';
import 'package:routed/src/validation/rules/contains.dart';
import 'package:routed/src/validation/rules/current_password.dart';
import 'package:routed/src/validation/rules/date.dart';
import 'package:routed/src/validation/rules/date_equals.dart';
import 'package:routed/src/validation/rules/date_format.dart';
import 'package:routed/src/validation/rules/decimal.dart';
import 'package:routed/src/validation/rules/different.dart';
import 'package:routed/src/validation/rules/different_timezone.dart';
import 'package:routed/src/validation/rules/digits.dart';
import 'package:routed/src/validation/rules/digits_between.dart';
import 'package:routed/src/validation/rules/distinct.dart';
import 'package:routed/src/validation/rules/doesnt_end_with.dart';
import 'package:routed/src/validation/rules/doesnt_start_with.dart';
import 'package:routed/src/validation/rules/double.dart';
import 'package:routed/src/validation/rules/email.dart';
import 'package:routed/src/validation/rules/ends_with.dart';
import 'package:routed/src/validation/rules/file_between.dart';
import 'package:routed/src/validation/rules/file_dimensions.dart';
import 'package:routed/src/validation/rules/file_extensions.dart';
import 'package:routed/src/validation/rules/file_rules.dart';
import 'package:routed/src/validation/rules/greater_than.dart';
import 'package:routed/src/validation/rules/greater_than_or_equal.dart';
import 'package:routed/src/validation/rules/hex_color.dart';
import 'package:routed/src/validation/rules/in.dart';
import 'package:routed/src/validation/rules/in_array.dart';
import 'package:routed/src/validation/rules/int.dart';
import 'package:routed/src/validation/rules/ip.dart';
import 'package:routed/src/validation/rules/ipv4.dart';
import 'package:routed/src/validation/rules/ipv6.dart';
import 'package:routed/src/validation/rules/json.dart';
import 'package:routed/src/validation/rules/less_than.dart';
import 'package:routed/src/validation/rules/less_than_or_equal.dart';
import 'package:routed/src/validation/rules/list.dart';
import 'package:routed/src/validation/rules/lowercase.dart';
import 'package:routed/src/validation/rules/max.dart';
import 'package:routed/src/validation/rules/max_length.dart';
import 'package:routed/src/validation/rules/min.dart';
import 'package:routed/src/validation/rules/min_length.dart';
import 'package:routed/src/validation/rules/multiple_of.dart';
import 'package:routed/src/validation/rules/not_in.dart';
import 'package:routed/src/validation/rules/not_regex.dart';
import 'package:routed/src/validation/rules/nullable.dart';
import 'package:routed/src/validation/rules/numeric.dart';
import 'package:routed/src/validation/rules/required.dart';
import 'package:routed/src/validation/rules/required_array_keys.dart';
import 'package:routed/src/validation/rules/same.dart';
import 'package:routed/src/validation/rules/same_size.dart';
import 'package:routed/src/validation/rules/slug.dart';
import 'package:routed/src/validation/rules/starts_with.dart';
import 'package:routed/src/validation/rules/string.dart';
import 'package:routed/src/validation/rules/ulid.dart';
import 'package:routed/src/validation/rules/uppercase.dart';
import 'package:routed/src/validation/rules/url.dart';
import 'package:routed/src/validation/rules/uuid.dart';
import 'package:routed/src/validation/rules/word.dart';
import 'package:test/test.dart';

MultipartFile buildFile({
  required String filename,
  required int size,
  required String contentType,
}) {
  return MultipartFile(
    name: 'file',
    filename: filename,
    path: '/tmp/$filename',
    size: size,
    contentType: contentType,
  );
}

void setContext(ContextAwareValidationRule rule, Map<String, dynamic> values) {
  rule.setContextValues(values);
}

void main() {
  group('Validation rules', () {
    test('string and character rules validate formats', () {
      expect(AlphaRule().validate('abc'), isTrue);
      expect(AlphaRule().validate('abc123'), isFalse);

      expect(AlphaDashRule().validate('abc-123'), isTrue);
      expect(AlphaDashRule().validate('abc+123'), isFalse);

      expect(AlphaNumRule().validate('abc123'), isTrue);
      expect(AlphaNumRule().validate('abc-123'), isFalse);

      expect(AsciiRule().validate('hello'), isTrue);
      expect(AsciiRule().validate('olá'), isFalse);

      expect(StringRule().validate('text'), isTrue);
      expect(StringRule().validate(null), isFalse);

      expect(WordRule().validate('word_123'), isTrue);
      expect(WordRule().validate('word-123'), isFalse);

      expect(SlugRule().validate('hello-world'), isTrue);
      expect(SlugRule().validate('HelloWorld'), isFalse);

      expect(StartsWithRule().validate('prefix-value', ['prefix']), isTrue);
      expect(StartsWithRule().validate('value', ['pre']), isFalse);

      expect(EndsWithRule().validate('value-end', ['end']), isTrue);
      expect(EndsWithRule().validate('value', ['suffix']), isFalse);

      expect(DoesntStartWithRule().validate('value', ['nope']), isTrue);
      expect(DoesntStartWithRule().validate('nope-value', ['nope']), isFalse);

      expect(DoesntEndWithRule().validate('value', ['nope']), isTrue);
      expect(DoesntEndWithRule().validate('value-nope', ['nope']), isFalse);

      expect(LowercaseRule().validate('lower'), isTrue);
      expect(LowercaseRule().validate('Lower'), isFalse);

      expect(UppercaseRule().validate('UPPER'), isTrue);
      expect(UppercaseRule().validate('Upper'), isFalse);

      expect(HexColorRule().validate('#fff'), isTrue);
      expect(HexColorRule().validate('123456'), isFalse);

      expect(UrlRule().validate('https://example.com'), isTrue);
      expect(UrlRule().validate('not-a-url'), isFalse);

      expect(ActiveUrlRule().validate('https://example.com/path'), isTrue);
      expect(ActiveUrlRule().validate('invalid-url'), isFalse);

      expect(EmailRule().validate('user@example.com'), isTrue);
      expect(EmailRule().validate('invalid'), isFalse);
    });

    test('numeric rules enforce numeric constraints', () {
      expect(NumericRule().validate('42'), isTrue);
      expect(NumericRule().validate('nope'), isFalse);

      expect(IntRule().validate('123'), isTrue);
      expect(IntRule().validate('12.3'), isFalse);

      expect(DoubleRule().validate('12.3'), isTrue);
      expect(DoubleRule().validate('abc'), isFalse);

      expect(DecimalRule().validate('10.55', ['2', '3']), isTrue);
      expect(DecimalRule().validate('10.5', ['2']), isFalse);

      expect(MultipleOfRule().validate('10', ['5']), isTrue);
      expect(MultipleOfRule().validate('10', ['6']), isFalse);

      expect(GreaterThanRule().validate('5', ['3']), isTrue);
      expect(GreaterThanRule().validate('3', ['5']), isFalse);

      expect(GreaterThanOrEqualRule().validate('5', ['5']), isTrue);
      expect(GreaterThanOrEqualRule().validate('4', ['5']), isFalse);

      expect(LessThanRule().validate('3', ['5']), isTrue);
      expect(LessThanRule().validate('6', ['5']), isFalse);

      expect(LessThanOrEqualRule().validate('5', ['5']), isTrue);
      expect(LessThanOrEqualRule().validate('6', ['5']), isFalse);

      expect(MinRule().validate('abc', ['2']), isTrue);
      expect(MinRule().validate(1, ['2']), isFalse);

      expect(MaxRule().validate('abc', ['5']), isTrue);
      expect(MaxRule().validate(10, ['5']), isFalse);

      expect(MinLengthRule().validate('abcd', ['3']), isTrue);
      expect(MinLengthRule().validate('ab', ['3']), isFalse);

      expect(MaxLengthRule().validate('abcd', ['5']), isTrue);
      expect(MaxLengthRule().validate('abcdef', ['5']), isFalse);

      expect(BetweenRule().validate('7', ['5', '10']), isTrue);
      expect(BetweenRule().validate('4', ['5', '10']), isFalse);

      expect(DigitsRule().validate('1234', ['4']), isTrue);
      expect(DigitsRule().validate('123', ['4']), isFalse);

      expect(DigitsBetweenRule().validate('1234', ['2', '5']), isTrue);
      expect(DigitsBetweenRule().validate('1', ['2', '5']), isFalse);
    });

    test('date and time rules handle comparisons', () {
      expect(DateRule().validate('2025-01-01'), isTrue);
      expect(DateRule().validate('01-01-2025'), isFalse);

      expect(DateFormatRule().validate('01/31/2025', ['MM/dd/yyyy']), isTrue);
      expect(DateFormatRule().validate('2025-01-31', ['MM/dd/yyyy']), isFalse);

      expect(DateEqualsRule().validate('2025-01-01', ['2025-01-01']), isTrue);
      expect(DateEqualsRule().validate('2025-01-02', ['2025-01-01']), isFalse);

      expect(BeforeRule().validate('2025-01-01', ['2025-01-10']), isTrue);
      expect(BeforeRule().validate('2025-01-12', ['2025-01-10']), isFalse);

      expect(AfterRule().validate('2025-01-12', ['2025-01-10']), isTrue);
      expect(AfterRule().validate('2025-01-01', ['2025-01-10']), isFalse);

      expect(AfterOrEqualRule().validate('2025-01-10', ['2025-01-10']), isTrue);
      expect(
        AfterOrEqualRule().validate('2025-01-01', ['2025-01-10']),
        isFalse,
      );

      expect(
        BeforeOrEqualRule().validate('2025-01-10', ['2025-01-10']),
        isTrue,
      );
      expect(
        BeforeOrEqualRule().validate('2025-01-12', ['2025-01-10']),
        isFalse,
      );
    });

    test('membership rules check inclusion and patterns', () {
      expect(InRule().validate('red', ['red', 'blue']), isTrue);
      expect(InRule().validate('green', ['red', 'blue']), isFalse);

      expect(NotInRule().validate('green', ['red', 'blue']), isTrue);
      expect(NotInRule().validate('red', ['red', 'blue']), isFalse);

      expect(NotRegexRule().validate('abc', [r'\d+']), isTrue);
      expect(NotRegexRule().validate('123', [r'\d+']), isFalse);

      expect(JsonRule().validate('{"ok":true}'), isTrue);
      expect(JsonRule().validate('{bad'), isFalse);
    });

    test('list rules enforce list requirements', () {
      expect(ArrayRule().validate(['a', 'b'], ['a', 'b']), isTrue);
      expect(ArrayRule().validate(['a', 'c'], ['a', 'b']), isFalse);

      expect(ListRule().validate(['a', 'b']), isTrue);
      expect(ListRule().validate('not-list'), isFalse);

      expect(DistinctRule().validate(['a', 'b', 'c']), isTrue);
      expect(DistinctRule().validate(['a', 'b', 'a']), isFalse);

      expect(ContainsRule().validate(['a', 'b', 'c'], ['a', 'b']), isTrue);
      expect(ContainsRule().validate(['a'], ['a', 'b']), isFalse);

      expect(
        RequiredArrayKeysRule().validate({'a': 1, 'b': 2}, ['a', 'b']),
        isTrue,
      );
      expect(RequiredArrayKeysRule().validate({'a': 1}, ['a', 'b']), isFalse);
    });

    test('context-aware rules use other field values', () {
      final sameRule = SameRule();
      setContext(sameRule, {'password': 'secret'});
      expect(sameRule.validate('secret', ['password']), isTrue);
      expect(sameRule.validate('nope', ['password']), isFalse);

      final differentRule = DifferentRule();
      setContext(differentRule, {'password': 'secret'});
      expect(differentRule.validate('nope', ['password']), isTrue);
      expect(differentRule.validate('secret', ['password']), isFalse);

      final sameSizeRule = SameSizeRule();
      setContext(sameSizeRule, {
        'list': [1, 2],
      });
      expect(sameSizeRule.validate([3, 4], ['list']), isTrue);
      expect(sameSizeRule.validate([3], ['list']), isFalse);

      final inArrayRule = InArrayRule();
      setContext(inArrayRule, {
        'choices': ['a', 'b'],
      });
      expect(inArrayRule.validate('a', ['choices']), isTrue);
      expect(inArrayRule.validate('c', ['choices']), isFalse);

      final confirmedRule = ConfirmedRule();
      setContext(confirmedRule, {'other': 'value'});
      expect(confirmedRule.validate(null, ['confirmation']), isTrue);
      expect(confirmedRule.validate('value', ['confirmation']), isFalse);
    });

    test('miscellaneous rules enforce types', () {
      expect(RequiredRule().validate('value'), isTrue);
      expect(RequiredRule().validate(''), isFalse);

      expect(NullableRule().validate(null), isTrue);
      expect(NullableRule().validate('value'), isFalse);

      expect(BooleanRule().validate(true), isTrue);
      expect(BooleanRule().validate('nope'), isFalse);

      expect(AcceptedRule().validate('yes'), isTrue);
      expect(AcceptedRule().validate('no'), isFalse);

      expect(IpRule().validate('192.168.1.1'), isTrue);
      expect(IpRule().validate('invalid'), isFalse);

      expect(Ipv4Rule().validate('192.168.1.1'), isTrue);
      expect(Ipv4Rule().validate('invalid'), isFalse);

      expect(
        Ipv6Rule().validate('2001:0db8:85a3:0000:0000:8a2e:0370:7334'),
        isTrue,
      );
      expect(Ipv6Rule().validate('invalid'), isFalse);

      expect(
        UuidRule().validate('123e4567-e89b-12d3-a456-426614174000'),
        isTrue,
      );
      expect(UuidRule().validate('invalid'), isFalse);

      expect(UlidRule().validate('01ARZ3NDEKTSV4RRFFQ69G5FAV'), isTrue);
      expect(UlidRule().validate('invalid'), isFalse);

      expect(DifferentTimezoneRule().validate('2025-01-01', ['UTC']), isFalse);
      expect(DifferentTimezoneRule().validate('2025-01-01'), isFalse);

      expect(CurrentPasswordRule().validate('secret'), isFalse);
    });

    test('file rules validate multipart metadata', () {
      final file = buildFile(
        filename: 'test.pdf',
        size: 2048,
        contentType: 'application/pdf',
      );

      expect(FileRule().validate(file), isTrue);
      expect(FileRule().validate('not-file'), isFalse);

      expect(MaxFileSizeRule().validate(file, ['4096']), isTrue);
      expect(MaxFileSizeRule().validate(file, ['1024']), isFalse);

      expect(
        AllowedMimeTypesRule().validate(file, ['application/pdf']),
        isTrue,
      );
      expect(AllowedMimeTypesRule().validate(file, ['image/png']), isFalse);

      expect(FileBetweenRule().validate(file, ['1', '3']), isTrue);
      expect(FileBetweenRule().validate(file, ['3', '4']), isFalse);

      expect(FileExtensionsRule().validate(file, ['pdf']), isTrue);
      expect(FileExtensionsRule().validate(file, ['png']), isFalse);

      expect(FileDimensionsRule().validate(file), isFalse);
    });

    test('rule messages include option data', () {
      expect(MinRule().message('x', ['2']), contains('2'));
      expect(MaxRule().message('x', ['5']), contains('5'));
      expect(BetweenRule().message('x', ['1', '3']), contains('1'));
      expect(DigitsRule().message('x', ['4']), contains('4'));
      expect(DigitsBetweenRule().message('x', ['2', '5']), contains('5'));
      expect(DateEqualsRule().message('x', ['2025-01-01']), contains('2025'));
      expect(StartsWithRule().message('x', ['pre']), contains('pre'));
      expect(EndsWithRule().message('x', ['suf']), contains('suf'));
      expect(DoesntStartWithRule().message('x', ['no']), contains('no'));
      expect(DoesntEndWithRule().message('x', ['no']), contains('no'));
      expect(ContainsRule().message('x', ['a', 'b']), contains('a'));
      expect(RequiredArrayKeysRule().message('x', ['a', 'b']), contains('a'));
      expect(FileExtensionsRule().message('x', ['txt']), contains('txt'));
      expect(MaxFileSizeRule().message('x', ['10']), contains('10'));
      expect(FileBetweenRule().message('x', ['1', '2']), contains('1'));
      expect(DecimalRule().message('x', ['1', '2']), contains('1'));
      expect(DifferentTimezoneRule().message('x', ['UTC']), contains('UTC'));
    });
  });
}
