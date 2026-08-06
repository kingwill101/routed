import 'dart:convert';

import 'package:routed/routed.dart';

import 'file.dart';
import 'validator.dart';

/// Extension that adds [validate] and [bind] to [EngineContext].
///
/// Historically these helpers lived on `routed`'s `context/binding.dart`
/// (see git history `packages/routed/lib/src/context/binding.dart` and
/// `packages/routed/lib/src/binding/*`). After the validator was moved
/// to `routed_validation`, the extension must live here so that
/// `ctx.validate` / `ctx.bind` remain available when `routed_validation`
/// is imported. `routed_openapi`'s `schemaValidationMiddleware` also
/// relies on `ctx.validate`.
///
/// Implementation mirrors the historical `BindingMethods` extension:
/// - `validate` selects the appropriate data source based on HTTP method
///   and content type, then runs it through [Validator].
/// - `bind` extracts the same data source and populates the provided
///   [model] (Map or Bindable).
extension ValidationContext on EngineContext {
  /// Validates the current request's data against [rules].
  ///
  /// Data source selection mirrors `defaultBinding`:
  /// - GET → query parameters
  /// - `application/json` → decoded JSON body
  /// - `application/x-www-form-urlencoded` → form fields
  /// - `multipart/form-data` → multipart fields + files
  ///
  /// Throws [ValidationError] when validation fails.
  Future<void> validate(
    Map<String, String> rules, {
    bool bail = false,
    Map<String, String>? messages,
  }) async {
    final data = await _extractValidationData();
    final registry = requireValidationRegistry(container);
    final validator = Validator.make(
      rules,
      registry: registry,
      bail: bail,
      messages: messages,
    );
    final errors = validator.validate(data);
    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }

  /// Binds the current request's data into [instance].
  ///
  /// Supports `Map` and any object with a `bind(Map<String, dynamic>)`
  /// method (the historical `Bindable` contract from `routed_http`).
  Future<T> bind<T>(T instance) async {
    final data = await _extractValidationData();
    if (instance is Map) {
      // Historical MultipartBinding excluded files from Map bind.
      for (final entry in data.entries) {
        final value = entry.value;
        // Skip file objects for JSON encoding; they are validated but not
        // bound to Map for JSON responses.
        if (isValidationFile(value)) continue;
        // Also skip duck-typed MultipartFile that isValidationFile covers.
        (instance as Map)[entry.key] = value;
      }
    } else {
      try {
        (instance as dynamic).bind(data);
      } catch (_) {}
    }
    return instance;
  }

  Future<Map<String, dynamic>> _extractValidationData() async {
    if (method.toUpperCase() == 'GET') {
      return Map<String, dynamic>.from(queryCache);
    }
    final contentType = request.contentType?.value ?? '';
    final mime = contentType.split(';').first.trim().toLowerCase();
    if (mime == 'application/json') {
      final bodyBytes = await request.bytes;
      final bodyString = utf8.decode(bodyBytes);
      if (bodyString.trim().isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(bodyString);
        if (decoded is Map<String, dynamic>) return decoded;
        return <String, dynamic>{};
      } on FormatException {
        return <String, dynamic>{};
      }
    }
    if (mime == 'application/x-www-form-urlencoded') {
      try {
        final form = await formCache;
        return Map<String, dynamic>.from(form);
      } catch (_) {
        final bodyString = utf8.decode(await request.bytes);
        if (bodyString.isEmpty) return <String, dynamic>{};
        return _simpleParseUrlEncoded(bodyString);
      }
    }
    if (mime == 'multipart/form-data') {
      try {
        final dynamic multipart = await multipartForm;
        final fields = (multipart.fields as Map).cast<String, dynamic>();
        final files = (multipart.files as List).cast<dynamic>();
        final merged = Map<String, dynamic>.from(fields);
        for (final file in files) {
          final name = (file as dynamic).name as String;
          if (!merged.containsKey(name)) merged[name] = file;
        }
        return merged;
      } catch (_) {
        try {
          final form = await formCache;
          return Map<String, dynamic>.from(form);
        } catch (_) {
          return <String, dynamic>{};
        }
      }
    }
    try {
      final bodyBytes = await request.bytes;
      if (bodyBytes.isNotEmpty) {
        final bodyString = utf8.decode(bodyBytes).trim();
        if (bodyString.isNotEmpty) {
          try {
            final decoded = jsonDecode(bodyString);
            if (decoded is Map<String, dynamic> && decoded.isNotEmpty) return decoded;
          } catch (_) {}
          final parsed = _simpleParseUrlEncoded(bodyString);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    } catch (_) {}
    return Map<String, dynamic>.from(queryCache);
  }

  Map<String, dynamic> _simpleParseUrlEncoded(String input) {
    final result = <String, dynamic>{};
    for (final pair in input.split('&')) {
      if (pair.isEmpty) continue;
      final eqIndex = pair.indexOf('=');
      if (eqIndex == -1) continue;
      final rawKey = Uri.decodeQueryComponent(pair.substring(0, eqIndex));
      final rawValue = Uri.decodeQueryComponent(pair.substring(eqIndex + 1));
      if (!result.containsKey(rawKey)) {
        result[rawKey] = rawValue;
      } else {
        final existing = result[rawKey];
        if (existing is List) {
          existing.add(rawValue);
        } else {
          result[rawKey] = [existing, rawValue];
        }
      }
    }
    return result;
  }
}
