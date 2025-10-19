import 'dart:math' as math;

import '../generator_base.dart';

/// Represents a color in RGBA format
/// Represents a color with red, green, blue, and alpha components.
///
/// Components `r`, `g`, `b` are integers ranging from 0 to 255.
/// The `a` (alpha) component is a double ranging from 0.0 (transparent)
/// to 1.0 (opaque).
///
/// ```dart
/// const red = Color(r: 255, g: 0, b: 0, a: 1.0);
/// const semiTransparentBlue = Color(r: 0, g: 0, b: 255, a: 0.5);
/// print(red); // Output: rgb(255, 0, 0)
/// print(semiTransparentBlue); // Output: rgba(0, 0, 255, 0.50)
/// ```
class Color {
  final int r;
  final int g;
  final int b;
  final double a;

  const Color({
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Color &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          (a - other.a).abs() < 1e-10;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => a == 1.0
      ? 'rgb($r, $g, $b)'
      : 'rgba($r, $g, $b, ${a.toStringAsFixed(2)})';
}

/// Generator for Color values
/// A generator that produces [Color] values.
///
/// Can optionally include an alpha channel (`includeAlpha`). Generated colors
/// aim for good distribution across the color space using HSL conversion internally.
///
/// Shrinking targets primary colors (red, green, blue), black, and white.
///
/// Usually used via [Specialized.color].
///
/// ```dart
/// final colorGen = Specialized.color(alpha: true);
/// final runner = PropertyTestRunner(colorGen, (color) {
///   // Test property with generated color
/// });
/// await runner.run();
/// ```
class ColorGenerator extends Generator<Color> {
  final bool includeAlpha;

  ColorGenerator({this.includeAlpha = false});

  @override
  ShrinkableValue<Color> generate(math.Random random) {
    // Use the provided random generator
    final hue = random.nextDouble() * 360; // 0-360
    final saturation = 0.7 + random.nextDouble() * 0.3; // 70-100%
    final lightness = 0.4 + random.nextDouble() * 0.2; // 40-60%
    final alpha = includeAlpha
        ? (random.nextInt(101) / 100.0)
        : 1.0; // Correct range 0-100 -> 0.0-1.0

    final rgb = _hslToRgb(hue, saturation, lightness);
    final original = Color(r: rgb.$1, g: rgb.$2, b: rgb.$3, a: alpha);

    return ShrinkableValue(original, () sync* {
      // Try primary colors
      final primaryColors = [
        Color(r: 255, g: 0, b: 0, a: original.a), // Red
        Color(r: 0, g: 255, b: 0, a: original.a), // Green
        Color(r: 0, g: 0, b: 255, a: original.a), // Blue
        Color(r: 0, g: 0, b: 0, a: original.a), // Black
        Color(r: 255, g: 255, b: 255, a: original.a), // White
      ];

      // Find closest primary color
      var closestPrimary = primaryColors.reduce(
        (a, b) =>
            _colorDistance(original, a) < _colorDistance(original, b) ? a : b,
      );

      yield ShrinkableValue.leaf(closestPrimary);
    });
  }

  double _colorDistance(Color a, Color b) {
    // Use CIE76 color difference formula for better perceptual distance
    final dr = (a.r - b.r).abs();
    final dg = (a.g - b.g).abs();
    final db = (a.b - b.b).abs();
    final da = ((a.a - b.a) * 255).abs();
    return math.sqrt(dr * dr + dg * dg + db * db + da * da).toDouble();
  }

  (int, int, int) _hslToRgb(double h, double s, double l) {
    double r, g, b;

    if (s == 0) {
      r = g = b = l; // achromatic
    } else {
      double hue2rgb(double p, double q, double t) {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
      }

      final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      final p = 2 * l - q;
      r = hue2rgb(p, q, h / 360 + 1 / 3);
      g = hue2rgb(p, q, h / 360);
      b = hue2rgb(p, q, h / 360 - 1 / 3);
    }

    return ((r * 255).round(), (g * 255).round(), (b * 255).round());
  }
}
