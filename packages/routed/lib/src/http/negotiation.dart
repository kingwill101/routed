import 'dart:math';

import 'package:http_parser/http_parser.dart';

/// Result of content negotiation containing the chosen media type
/// and associated preference metadata.
class NegotiatedMediaType {
  NegotiatedMediaType({
    required this.value,
    required this.quality,
    Map<String, String>? parameters,
  }) : parameters = Map.unmodifiable(parameters ?? const {});

  /// Selected media type string (e.g. `application/json`).
  final String value;

  /// Negotiated quality factor (0.0 – 1.0).
  final double quality;

  /// Additional parameters supplied by the `Accept` header (excluding `q`).
  final Map<String, String> parameters;
}

class _MediaOffer {
  _MediaOffer({
    required this.raw,
    required this.mediaType,
    required this.index,
  });

  final String raw;
  final MediaType? mediaType;
  final int index;
}

class _AcceptSpec {
  _AcceptSpec({
    required this.mediaType,
    required this.quality,
    required this.index,
    required this.parameterCount,
  });

  final MediaType mediaType;
  final double quality;
  final int index;
  final int parameterCount;

  int get specificity {
    var score = 0;
    if (mediaType.type != '*') {
      score += 10;
    }
    if (mediaType.subtype != '*') {
      score += 5;
    }
    score += parameterCount;
    return score;
  }
}

/// Utilities for negotiating response content types based on the `Accept` header.
class ContentNegotiator {
  /// Determines the best supported media type for the provided [acceptHeader].
  ///
  /// [supported] should contain the response media types that can be produced.
  /// When the header is absent or no match is found, [defaultType] (or the first
  /// supported value) is used. Returns `null` when no option can satisfy the header.
  static NegotiatedMediaType? negotiate(
    String? acceptHeader,
    Iterable<String> supported, {
    String? defaultType,
  }) {
    final offers = _parseOffers(supported);
    if (offers.isEmpty) {
      return null;
    }

    final specs = _parseAcceptHeader(acceptHeader);

    if (specs.isEmpty) {
      final fallback = _resolveFallback(defaultType, offers);
      if (fallback == null) {
        return null;
      }
      return NegotiatedMediaType(
        value: fallback.raw,
        quality: 1.0,
        parameters: const {},
      );
    }

    _MediaOffer? bestOffer;
    _AcceptSpec? bestSpec;
    double bestQuality = -1;
    int bestSpecificity = -1;
    int bestHeaderIndex = specs.length;
    int bestOfferIndex = offers.length;

    for (final offer in offers) {
      final offerType = offer.mediaType;
      if (offerType == null) {
        continue;
      }
      for (final spec in specs) {
        if (!_matches(offerType, spec.mediaType)) {
          continue;
        }
        final quality = spec.quality;
        if (quality <= 0) {
          continue;
        }
        final specificity = spec.specificity;

        final shouldSelect =
            quality > bestQuality ||
            (quality == bestQuality &&
                (specificity > bestSpecificity ||
                    (specificity == bestSpecificity &&
                        (spec.index < bestHeaderIndex ||
                            (spec.index == bestHeaderIndex &&
                                offer.index < bestOfferIndex)))));

        if (shouldSelect) {
          bestQuality = quality;
          bestSpecificity = specificity;
          bestHeaderIndex = spec.index;
          bestOfferIndex = offer.index;
          bestOffer = offer;
          bestSpec = spec;
        }
      }
    }

    if (bestOffer != null && bestSpec != null) {
      final params = Map<String, String>.from(bestSpec.mediaType.parameters)
        ..remove('q');
      return NegotiatedMediaType(
        value: bestOffer.raw,
        quality: min(1.0, max(0.0, bestSpec.quality)),
        parameters: params.map(
          (key, value) => MapEntry(key.toLowerCase(), value),
        ),
      );
    }

    final fallback = _resolveFallback(defaultType, offers);
    if (fallback == null) {
      return null;
    }
    return NegotiatedMediaType(
      value: fallback.raw,
      quality: 1.0,
      parameters: const {},
    );
  }

  static List<_MediaOffer> _parseOffers(Iterable<String> supported) {
    final result = <_MediaOffer>[];
    var index = 0;
    for (final raw in supported) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        index++;
        continue;
      }
      MediaType? parsed;
      try {
        parsed = MediaType.parse(trimmed);
      } catch (_) {
        parsed = null;
      }
      result.add(_MediaOffer(raw: trimmed, mediaType: parsed, index: index));
      index++;
    }
    return result;
  }

  static List<_AcceptSpec> _parseAcceptHeader(String? header) {
    if (header == null || header.trim().isEmpty) {
      return const [];
    }
    final parts = header.split(',');
    final specs = <_AcceptSpec>[];
    for (var i = 0; i < parts.length; i++) {
      final value = parts[i].trim();
      if (value.isEmpty) {
        continue;
      }
      MediaType mediaType;
      try {
        mediaType = MediaType.parse(value);
      } catch (_) {
        continue;
      }
      final params = Map<String, String>.from(mediaType.parameters);
      final qualityRaw = params.remove('q');
      double quality = 1.0;
      if (qualityRaw != null) {
        final parsed = double.tryParse(qualityRaw);
        if (parsed != null) {
          quality = parsed.clamp(0.0, 1.0);
        }
      }
      specs.add(
        _AcceptSpec(
          mediaType: MediaType(mediaType.type, mediaType.subtype, params),
          quality: quality,
          index: i,
          parameterCount: params.length,
        ),
      );
    }
    return specs;
  }

  static _MediaOffer? _resolveFallback(
    String? defaultType,
    List<_MediaOffer> offers,
  ) {
    if (offers.isEmpty) {
      return null;
    }
    if (defaultType == null) {
      return offers.first;
    }
    final match = offers.firstWhere(
      (offer) => offer.raw == defaultType,
      orElse: () => offers.first,
    );
    return match;
  }

  static bool _matches(MediaType offer, MediaType spec) {
    final typeMatches = spec.type == '*' || spec.type == offer.type;
    final subtypeMatches = spec.subtype == '*' || spec.subtype == offer.subtype;
    return typeMatches && subtypeMatches;
  }
}
