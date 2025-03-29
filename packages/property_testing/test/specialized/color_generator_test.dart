import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';
import 'dart:math' as math;

void main() {
  group('Color Generator', () {
    test('generates valid RGB colors with default settings', () async {
      final runner = PropertyTestRunner(
        Specialized.color(),
        (color) {
          expect(color.r, inInclusiveRange(0, 255));
          expect(color.g, inInclusiveRange(0, 255));
          expect(color.b, inInclusiveRange(0, 255));
          expect(color.a, equals(1.0)); // Default alpha
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates RGBA colors when alpha is enabled', () async {
      final runner = PropertyTestRunner(
        Specialized.color(alpha: true),
        (color) {
          expect(color.r, inInclusiveRange(0, 255));
          expect(color.g, inInclusiveRange(0, 255));
          expect(color.b, inInclusiveRange(0, 255));
          expect(color.a, inInclusiveRange(0.0, 1.0));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('shrinks towards primary colors', () async {
      final runner = PropertyTestRunner(
        Specialized.color(),
        (color) {
          // Force failure to trigger shrinking
          fail('Triggering shrink');
        },
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);

      final shrunkColor = result.failingInput as Color;
      // The shrunk color should be one of the primary colors or black
      expect(
        [
          const Color(r: 255, g: 0, b: 0, a: 1.0), // Red
          const Color(r: 0, g: 255, b: 0, a: 1.0), // Green
          const Color(r: 0, g: 0, b: 255, a: 1.0), // Blue
          const Color(r: 0, g: 0, b: 0, a: 1.0), // Black
        ],
        contains(shrunkColor),
      );
    });

    test('generates reproducible colors from the same seed', () async {
      // Use separate Random instances with the same seed
      const int fixedSeed = 42;

      final random1 = math.Random(fixedSeed);
      final config1 = PropertyConfig(numTests: 10, random: random1);
      final generator = Specialized.color(alpha: true);

      final colors1 = <String>[];
      await PropertyTestRunner(
        generator,
        (color) => colors1.add(color.toString()),
        config1,
      ).run();

      // Create a fresh Random with the same seed
      final random2 = math.Random(fixedSeed);
      final config2 = PropertyConfig(numTests: 10, random: random2);

      final colors2 = <String>[];
      await PropertyTestRunner(
        generator,
        (color) => colors2.add(color.toString()),
        config2,
      ).run();

      expect(colors1, equals(colors2));
    });

    test('generates diverse color values', () async {
      final seenRed = <int>{};
      final seenGreen = <int>{};
      final seenBlue = <int>{};
      final seenAlpha = <double>{};

      final runner = PropertyTestRunner(
        Specialized.color(alpha: true),
        (color) {
          seenRed.add(color.r);
          seenGreen.add(color.g);
          seenBlue.add(color.b);
          seenAlpha.add(color.a);
        },
        PropertyConfig(numTests: 1000),
      );

      await runner.run();

      // We should see a good distribution of values
      expect(seenRed.length, greaterThan(50));
      expect(seenGreen.length, greaterThan(50));
      expect(seenBlue.length, greaterThan(50));
      expect(seenAlpha.length, greaterThan(50));
    });

    test('color blending properties', () async {
      final runner = PropertyTestRunner(
        Specialized.color(alpha: true).list(minLength: 2, maxLength: 2),
        (colors) {
          final c1 = colors[0];
          final c2 = colors[1];
          final blended = _blendColors(c1, c2, 0.5);

          // Test that blended components are between the source colors
          expect(blended.r, inInclusiveRange(min(c1.r, c2.r), max(c1.r, c2.r)));
          expect(blended.g, inInclusiveRange(min(c1.g, c2.g), max(c1.g, c2.g)));
          expect(blended.b, inInclusiveRange(min(c1.b, c2.b), max(c1.b, c2.b)));
          expect(blended.a, inInclusiveRange(min(c1.a, c2.a), max(c1.a, c2.a)));
        },
        PropertyConfig(numTests: 1000),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('color string representation', () async {
      final runner = PropertyTestRunner(
        Specialized.color(alpha: true),
        (color) {
          final str = color.toString();
          if (color.a == 1.0) {
            expect(str, matches(r'^rgb\(\d+, \d+, \d+\)$'));
          } else {
            expect(str, matches(r'^rgba\(\d+, \d+, \d+, \d+\.\d+\)$'));
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates valid grayscale colors', () async {
      final runner = PropertyTestRunner(
        Specialized.color(),
        (color) {
          final gray = Color(r: color.r, g: color.r, b: color.r, a: color.a);
          expect(gray.r, equals(gray.g));
          expect(gray.g, equals(gray.b));
          expect(gray.toString(), matches(r'^rgb\(\d+, \d+, \d+\)$'));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates valid HSL conversions', () async {
      final runner = PropertyTestRunner(
        Specialized.color(),
        (color) {
          final hsl = _rgbToHsl(color.r, color.g, color.b);
          final rgb = _hslToRgb(hsl.$1, hsl.$2, hsl.$3);

          // Allow small differences due to floating point conversion
          expect((rgb.$1 - color.r).abs(), lessThanOrEqualTo(1));
          expect((rgb.$2 - color.g).abs(), lessThanOrEqualTo(1));
          expect((rgb.$3 - color.b).abs(), lessThanOrEqualTo(1));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates valid complementary colors', () async {
      final runner = PropertyTestRunner(
        Specialized.color(),
        (color) {
          final complement = Color(
            r: 255 - color.r,
            g: 255 - color.g,
            b: 255 - color.b,
            a: color.a,
          );

          // Sum of original and complement should be white
          expect(color.r + complement.r, equals(255));
          expect(color.g + complement.g, equals(255));
          expect(color.b + complement.b, equals(255));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('maintains color distance properties', () async {
      final runner = PropertyTestRunner(
        Specialized.color().list(minLength: 3, maxLength: 3),
        (colors) {
          final c1 = colors[0];
          final c2 = colors[1];
          final c3 = colors[2];

          final d12 = _colorDistance(c1, c2);
          final d23 = _colorDistance(c2, c3);
          final d13 = _colorDistance(c1, c3);

          // Triangle inequality
          expect(d12 + d23, greaterThanOrEqualTo(d13));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates perceptually distinct colors', () async {
      final colors = <Color>[];

      final runner = PropertyTestRunner(
        Specialized.color(),
        (color) {
          colors.add(color);
          if (colors.length >= 2) {
            for (int i = 0; i < colors.length - 1; i++) {
              final distance = _colorDistance(colors[i], color);
              // Ensure colors are perceptually different enough
              expect(distance, greaterThan(20.0));
            }
          }
        },
        PropertyConfig(numTests: 10),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });
  });
}

/// Helper function to blend two colors
Color _blendColors(Color c1, Color c2, double t) {
  return Color(
    r: (c1.r + (c2.r - c1.r) * t).round(),
    g: (c1.g + (c2.g - c1.g) * t).round(),
    b: (c1.b + (c2.b - c1.b) * t).round(),
    a: c1.a + (c2.a - c1.a) * t,
  );
}

/// Helper function to find the minimum of two numbers
T min<T extends num>(T a, T b) => a < b ? a : b;

/// Helper function to find the maximum of two numbers
T max<T extends num>(T a, T b) => a > b ? a : b;

/// Helper matcher for inclusive range checks
Matcher inInclusiveRange(num min, num max) => predicate((dynamic value) {
      final numValue = value as num;
      return numValue >= min && numValue <= max;
    }, 'is in range [$min, $max]');

/// Helper function to calculate color distance
double _colorDistance(Color c1, Color c2) {
  final dr = (c1.r - c2.r).abs();
  final dg = (c1.g - c2.g).abs();
  final db = (c1.b - c2.b).abs();
  final da = ((c1.a - c2.a) * 255).abs();
  return math.sqrt(dr * dr + dg * dg + db * db + da * da);
}

/// Helper function to convert RGB to HSL
(double, double, double) _rgbToHsl(int r, int g, int b) {
  final rf = r / 255;
  final gf = g / 255;
  final bf = b / 255;

  final max = math.max(math.max(rf, gf), bf);
  final min = math.min(math.min(rf, gf), bf);
  final l = (max + min) / 2;

  if (max == min) {
    return (0, 0, l);
  }

  final d = max - min;
  final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);

  double h;
  if (max == rf) {
    h = (gf - bf) / d + (gf < bf ? 6 : 0);
  } else if (max == gf) {
    h = (bf - rf) / d + 2;
  } else {
    h = (rf - gf) / d + 4;
  }
  h /= 6;

  return (h, s, l);
}

/// Helper function to convert HSL to RGB
(int, int, int) _hslToRgb(double h, double s, double l) {
  double hue2rgb(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  if (s == 0) {
    final gray = (l * 255).round();
    return (gray, gray, gray);
  }

  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;

  final r = (255 * hue2rgb(p, q, h + 1 / 3)).round();
  final g = (255 * hue2rgb(p, q, h)).round();
  final b = (255 * hue2rgb(p, q, h - 1 / 3)).round();

  return (r, g, b);
}

/// Helper function to calculate square root
double sqrt(num x) => x <= 0 ? 0.0 : math.sqrt(x);

/// Helper function for exponentiation
double pow(num x, num exponent) =>
    x <= 0 ? 0.0 : math.pow(x, exponent).toDouble();
