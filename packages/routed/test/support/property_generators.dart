import 'package:property_testing/property_testing.dart';

const List<String> _httpMethods = <String>[
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OPTIONS',
  'HEAD',
  'TRACE',
  'CONNECT',
];

Generator<String> httpMethod() => Gen.oneOf(_httpMethods);

Generator<Set<String>> httpMethodSet({int min = 1, int? max}) {
  final int upper = max ?? _httpMethods.length;
  return Gen.someOf(
    _httpMethods,
    min: min,
    max: upper,
  ).map((methods) => methods.toSet());
}

Generator<String> slugSegment({int min = 1, int max = 16}) {
  if (min < 1) {
    throw ArgumentError.value(min, 'min', 'Slug segment cannot be empty');
  }
  if (max < min) {
    throw ArgumentError.value(
      max,
      'max',
      'Maximum length must be greater than or equal to min',
    );
  }

  final validPartCounts = <int>[];
  for (var partCount = 1; partCount <= 4; partCount++) {
    final hyphenCount = partCount - 1;
    final minimumTotal = partCount + hyphenCount;
    final minCandidate = min > minimumTotal ? min : minimumTotal;
    if (minCandidate <= max) {
      validPartCounts.add(partCount);
    }
  }

  if (validPartCounts.isEmpty) {
    throw ArgumentError('No valid slug configuration for min=$min, max=$max');
  }

  return Gen.oneOf(validPartCounts).flatMap((partCount) {
    final hyphenCount = partCount - 1;
    final baseMin = partCount + hyphenCount;
    final minTotal = min > baseMin ? min : baseMin;

    return Gen.integer(min: minTotal, max: max).flatMap((totalLength) {
      final characterCount = totalLength - hyphenCount;
      return _positiveComposition(characterCount, partCount).flatMap(
        (lengths) => _partsFromLengths(lengths).map((parts) => parts.join('-')),
      );
    });
  });
}

Generator<String> invalidSlugSegment({int min = 1, int max = 16}) {
  if (min < 1) {
    throw ArgumentError.value(min, 'min', 'Slug segment cannot be empty');
  }
  if (max < min) {
    throw ArgumentError.value(
      max,
      'max',
      'Maximum length must be greater than or equal to min',
    );
  }

  final base = slugSegment(min: min, max: max);
  return base.flatMap((slug) {
    final generators = <Generator<String>>[
      Gen.integer(min: 0, max: slug.length - 1).flatMap(
        (index) => Gen.oneOf(
          _slugInvalidReplacements,
        ).map((replacement) => _replaceChar(slug, index, replacement)),
      ),
      Gen.constant(_replaceChar(slug, 0, '-')),
      Gen.constant(_replaceChar(slug, slug.length - 1, '-')),
    ];

    if (slug.contains(_lettersPattern)) {
      generators.add(Gen.constant(slug.toUpperCase()));
    }

    return Gen.oneOfGen(generators);
  });
}

Generator<String> fileName({List<String>? extensions}) {
  final base = slugSegment(
    min: 3,
    max: 12,
  ).map((value) => value.replaceAll('-', '_'));
  if (extensions == null || extensions.isEmpty) {
    return base;
  }
  final extensionGen = Gen.oneOf(extensions);
  return base.flatMap((name) {
    return Gen.boolean().flatMap((useExt) {
      if (!useExt) return Gen.constant(name);
      return extensionGen.map((ext) => '$name.$ext');
    });
  });
}

Generator<Map<String, List<String>>> headerMap({
  int minEntries = 1,
  int maxEntries = 5,
  Generator<String>? keyGen,
  Generator<String>? valueGen,
}) {
  final keys =
      keyGen ?? slugSegment(min: 3, max: 10).map((key) => key.toLowerCase());
  final values = valueGen ?? Gen.string(minLength: 1, maxLength: 20);

  final entryGen = keys.flatMap(
    (key) => values
        .list(minLength: 1, maxLength: 3)
        .map((vals) => MapEntry(key, List<String>.from(vals))),
  );

  return Gen.integer(min: minEntries, max: maxEntries).flatMap((count) {
    return entryGen.list(minLength: count, maxLength: count).map((entries) {
      final map = <String, List<String>>{};
      for (final entry in entries) {
        map[entry.key] = entry.value;
      }
      return map;
    });
  });
}

Generator<Duration> duration({
  int minMilliseconds = 0,
  int maxMilliseconds = 500,
}) => Gen.integer(
  min: minMilliseconds,
  max: maxMilliseconds,
).map((ms) => Duration(milliseconds: ms));

Generator<({int start, int end})> byteRange({int maxLength = 1024}) {
  final upperBound = maxLength - 1;
  return Gen.integer(min: 0, max: upperBound).flatMap(
    (start) => Gen.integer(
      min: start,
      max: upperBound,
    ).map((end) => (start: start, end: end)),
  );
}

const _slugAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
const _slugInvalidReplacements = <String>['_', '.', '@', ' '];
final RegExp _lettersPattern = RegExp(r'[a-z]');

Generator<List<int>> _positiveComposition(int total, int parts) {
  if (parts == 1) {
    return Gen.constant(<int>[total]);
  }

  final maxFirst = total - (parts - 1);
  return Gen.integer(min: 1, max: maxFirst).flatMap(
    (first) => _positiveComposition(
      total - first,
      parts - 1,
    ).map((rest) => <int>[first, ...rest]),
  );
}

Generator<List<String>> _partsFromLengths(List<int> lengths) {
  return lengths.fold<Generator<List<String>>>(
    Gen.constant(<String>[]),
    (gen, length) => gen.flatMap(
      (parts) => _lowerAlphaNumericString(minLength: length, maxLength: length)
          .map((value) {
            final updated = List<String>.from(parts)..add(value);
            return updated;
          }),
    ),
  );
}

Generator<String> _lowerAlphaNumericString({
  required int minLength,
  required int maxLength,
}) {
  if (minLength < 1) {
    throw ArgumentError.value(
      minLength,
      'minLength',
      'Slug parts must contain at least one character',
    );
  }
  if (maxLength < minLength) {
    throw ArgumentError.value(
      maxLength,
      'maxLength',
      'maxLength must be >= minLength',
    );
  }

  final charGen = Gen.oneOf(_slugAlphabet.split(''));
  return Gen.containerOf<String, String>(
    charGen,
    (chars) => chars.join(),
    minLength: minLength,
    maxLength: maxLength,
  );
}

String _replaceChar(String value, int index, String replacement) {
  assert(
    replacement.length == 1,
    'Replacement must be a single character to preserve slug length',
  );
  return value.substring(0, index) + replacement + value.substring(index + 1);
}
