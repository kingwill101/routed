// Content negotiation helpers per refactor.md §11.

import 'package:http_parser/http_parser.dart';
import 'package:routed/routed.dart';

class NegotiatedMediaType {
  NegotiatedMediaType({
    required this.value,
    required this.quality,
    Map<String, String>? parameters,
  }) : parameters = Map.unmodifiable(parameters ?? const {});
  final String value;
  final double quality;
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
    if (mediaType.type != '*') score += 10;
    if (mediaType.subtype != '*') score += 5;
    score += parameterCount;
    return score;
  }
}

class ContentNegotiator {
  static NegotiatedMediaType? negotiate(
    String? acceptHeader,
    Iterable<String> supported, {
    String? defaultType,
  }) {
    final offers = _parseOffers(supported);
    if (offers.isEmpty) return null;
    final specs = _parseAcceptHeader(acceptHeader);
    if (specs.isEmpty) {
      final fallback = _resolveFallback(defaultType, offers);
      if (fallback == null) return null;
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
      for (final spec in specs) {
        if (offer.mediaType == null) continue;
        if (!_matches(offer.mediaType!, spec.mediaType)) continue;
        final q = spec.quality;
        final specScore = spec.specificity;
        if (q > bestQuality ||
            (q == bestQuality && specScore > bestSpecificity) ||
            (q == bestQuality &&
                specScore == bestSpecificity &&
                spec.index < bestHeaderIndex) ||
            (q == bestQuality &&
                specScore == bestSpecificity &&
                spec.index == bestHeaderIndex &&
                offer.index < bestOfferIndex)) {
          bestOffer = offer;
          bestSpec = spec;
          bestQuality = q;
          bestSpecificity = specScore;
          bestHeaderIndex = spec.index;
          bestOfferIndex = offer.index;
        }
      }
    }
    if (bestOffer == null || bestSpec == null) return null;
    final params = Map<String, String>.from(bestSpec.mediaType.parameters);
    params.remove('q');
    return NegotiatedMediaType(
      value: bestOffer.raw,
      quality: bestQuality,
      parameters: params,
    );
  }

  static List<_MediaOffer> _parseOffers(Iterable<String> supported) {
    final offers = <_MediaOffer>[];
    var idx = 0;
    for (final raw in supported) {
      MediaType? mt;
      try {
        mt = MediaType.parse(raw);
      } catch (_) {
        mt = null;
      }
      offers.add(_MediaOffer(raw: raw, mediaType: mt, index: idx++));
    }
    return offers;
  }

  static List<_AcceptSpec> _parseAcceptHeader(String? header) {
    if (header == null || header.trim().isEmpty) return [];
    final specs = <_AcceptSpec>[];
    var idx = 0;
    for (final part in header.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      try {
        final mt = MediaType.parse(trimmed);
        final qStr = mt.parameters['q'];
        final q = qStr == null ? 1.0 : double.tryParse(qStr) ?? 1.0;
        final paramCount = mt.parameters.length - (qStr == null ? 0 : 1);
        specs.add(
          _AcceptSpec(
            mediaType: mt,
            quality: q.clamp(0.0, 1.0),
            index: idx++,
            parameterCount: paramCount,
          ),
        );
      } catch (_) {}
    }
    specs.sort((a, b) {
      final qCmp = b.quality.compareTo(a.quality);
      if (qCmp != 0) return qCmp;
      final specCmp = b.specificity.compareTo(a.specificity);
      if (specCmp != 0) return specCmp;
      return a.index.compareTo(b.index);
    });
    return specs;
  }

  static _MediaOffer? _resolveFallback(
    String? defaultType,
    List<_MediaOffer> offers,
  ) {
    if (defaultType != null) {
      for (final o in offers) {
        if (o.raw == defaultType) return o;
      }
    }
    return offers.isEmpty ? null : offers.first;
  }

  static bool _matches(MediaType offer, MediaType spec) {
    if (spec.type != '*' && spec.type != offer.type) return false;
    if (spec.subtype != '*' && spec.subtype != offer.subtype) return false;
    for (final e in spec.parameters.entries) {
      if (e.key == 'q') continue;
      if (offer.parameters[e.key] != e.value) return false;
    }
    return true;
  }
}

extension NegotiationEngineContext on EngineContext {
  NegotiatedMediaType? negotiatesContentType(
    Iterable<String> supported, {
    String? defaultType,
  }) {
    final header = requestHeader(HttpHeaders.acceptHeader);
    return ContentNegotiator.negotiate(
      header,
      supported,
      defaultType: defaultType,
    );
  }

  bool accepts(String mediaType) {
    final header = requestHeader(HttpHeaders.acceptHeader);
    if (header == null) return true;
    final result = ContentNegotiator.negotiate(header, [mediaType]);
    return result != null;
  }
}
