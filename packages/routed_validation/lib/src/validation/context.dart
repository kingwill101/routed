import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_http/routed_http.dart';

import 'package:routed_validation/src/validation/file.dart';
import 'package:routed_validation/src/validation/validator.dart';

/// Adds request validation and binding helpers to [EngineContext].
///
/// Import `package:routed_validation/routed_validation.dart` to make these
/// extension methods available. The request data source is selected from the
/// method and content type, then passed to [Validator].
extension ValidationContext on EngineContext {
  /// Validates the current request's data against [rules].
  ///
  /// Data source selection mirrors `defaultBinding`:
  /// - GET → query parameters
  /// - `application/json` → decoded JSON body
  /// - `application/x-www-form-urlencoded` → form fields
  /// - `multipart/form-data` → multipart fields + files
  ///
  /// [rules] maps field names to the serialized rule syntax accepted by
  /// [Validator.make]. [messages] overrides a rule message by `field.rule`
  /// first, then by rule name. Set [bail] to stop after the first failed rule
  /// in the request.
  ///
  /// Throws [ValidationError] when one or more rules fail. Malformed JSON or
  /// form data is treated as an empty input map, so a `required` rule can
  /// report missing fields without exposing a parser exception.
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
      // ValidationError is Routed's structured engine error, not an
      // Exception or Error subclass.
      // ignore: only_throw_errors
      throw ValidationError(errors);
    }
  }

  /// Binds the current request's data into [instance].
  ///
  /// A [Map] receives non-file values directly. Any other object is invoked
  /// through a `bind(Map<String, dynamic>)` method when it provides one;
  /// objects without that method are returned unchanged. File values are
  /// available to validation but are not copied into a map.
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
      } on Object catch (_) {}
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
      } on Object catch (_) {
        final bodyString = utf8.decode(await request.bytes);
        if (bodyString.isEmpty) return <String, dynamic>{};
        return _simpleParseUrlEncoded(bodyString);
      }
    }
    if (mime == 'multipart/form-data') {
      try {
        final multipart = await multipartForm;
        final fields = Map<String, dynamic>.from(multipart.fields);
        final files = multipart.files;
        final merged = Map<String, dynamic>.from(fields);
        for (final file in files) {
          final name = file.name;
          if (!merged.containsKey(name)) merged[name] = file;
        }
        return merged;
      } on Object catch (_) {
        try {
          final form = await formCache;
          return Map<String, dynamic>.from(form);
        } on Object catch (_) {
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
            if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
              return decoded;
            }
          } on Object catch (_) {}
          final parsed = _simpleParseUrlEncoded(bodyString);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    } on Object catch (_) {}
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
