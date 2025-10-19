import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

void main() {
  group('URLField', () {
    // Debug test to help diagnose issues
    test('debug error messages', () {
      final field = URLField(minLength: 15, maxLength: 20);

      try {
        field.toDart("http://f.com");
        fail('Expected ValidationError');
      } catch (e) {
        print('Debug - Error for min length: $e');
      }

      try {
        field.toDart("http://abcdefghijklmnopqrstuvwxyz.com");
        fail('Expected ValidationError');
      } catch (e) {
        print('Debug - Error for max length: $e');
      }
    });

    test('validates URLs correctly', () {
      final field = URLField(required: false);
      final validUrls = {
        "http://localhost": "http://localhost",
        "http://example.com": "http://example.com",
        "http://example.com/test": "http://example.com/test",
        "http://example.com.": "http://example.com.",
        "http://www.example.com": "http://www.example.com",
        "http://www.example.com:8000/test": "http://www.example.com:8000/test",
        "http://example.com?some_param=some_value":
            "http://example.com?some_param=some_value",
        "valid-with-hyphens.com": "https://valid-with-hyphens.com",
        "subdomain.domain.com": "https://subdomain.domain.com",
        "http://200.8.9.10": "http://200.8.9.10",
        "http://200.8.9.10:8000/test": "http://200.8.9.10:8000/test",
        "http://valid-----hyphens.com": "http://valid-----hyphens.com",
        "www.example.com/s/http://code.djangoproject.com/ticket/13804":
            "https://www.example.com/s/http://code.djangoproject.com/ticket/13804",
        "http://example.com/     ": "http://example.com/",
      };

      for (var entry in validUrls.entries) {
        expect(field.toDart(entry.key), equals(entry.value));
      }
    });

    test('rejects invalid URLs', () {
      final field = URLField();
      final invalidUrls = [
        "foo",
        "com.",
        ".",
        "http://",
        "http://example",
        "http://example.",
        "http://.com",
        "http://invalid-.com",
        "http://-invalid.com",
        "http://inv-.alid-.com",
        "http://inv-.-alid.com",
        "[a",
        "http://[a",
        23,
        "http://${"X" * 60}",
        "http://${"X" * 200}",
      ];

      for (var url in invalidUrls) {
        expect(
          () => field.toDart(url),
          throwsA(isA<ValidationError>()),
          reason: 'URL "$url" should be invalid',
        );
      }
    });

    test('handles required validation', () {
      final field = URLField();
      expect(() => field.toDart(null), throwsA(isA<ValidationError>()));
      expect(() => field.toDart(""), throwsA(isA<ValidationError>()));
    });

    test('handles non-required fields', () {
      final field = URLField(required: false);
      expect(field.toDart(null), equals(""));
      expect(field.toDart(""), equals(""));
    });

    test('handles custom empty value', () {
      final field = URLField(required: false, emptyValue: null);
      expect(field.toDart(""), isNull);
      expect(field.toDart(null), isNull);
    });

    test('handles length validation', () {
      final field = URLField(minLength: 15, maxLength: 20);
      expect(field.toDart("http://example.com"), equals("http://example.com"));

      expect(
        () => field.toDart("http://f.com"),
        throwsA(
          containsErrorMessage('Ensure this value has at least 15 characters'),
        ),
      );

      expect(
        () => field.toDart("http://abcdefghijklmnopqrstuvwxyz.com"),
        throwsA(
          containsErrorMessage('Ensure this value has at most 20 characters'),
        ),
      );
    });

    test('handles assume_scheme parameter', () {
      final field = URLField();
      expect(field.toDart("example.com"), equals("https://example.com"));

      final httpField = URLField(assumeScheme: "http");
      expect(httpField.toDart("example.com"), equals("http://example.com"));

      final httpsField = URLField(assumeScheme: "https");
      expect(httpsField.toDart("example.com"), equals("https://example.com"));
    });

    test('widget renders with correct attributes', () {
      final field = URLField(minLength: 15, maxLength: 20);
      final attrs = field.widgetAttrs(field.widget);

      expect(attrs['maxlength'], equals('20'));
      expect(attrs['minlength'], equals('15'));
    });
  });
}
