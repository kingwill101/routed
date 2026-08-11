// ignore_for_file: implementation_imports
import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'binding.dart';

/// Handles JSON binding and validation.
class JsonBinding extends Binding {
  @override
  String get name => 'json';

  @override
  MimeType get mimeType => MimeType.json;

  Future<Map<String, dynamic>> _decodedBody(EngineContext ctx) async {
    final bodyBytes = await ctx.request.bytes;
    final bodyString = utf8.decode(bodyBytes);
    if (bodyString.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(bodyString);
      if (decoded is! Map<String, dynamic>) {
        throw JsonParseError(
          details: 'Expected JSON object, got ${decoded.runtimeType}',
        );
      }
      return decoded;
    } on FormatException catch (e) {
      throw JsonParseError(details: e.message);
    }
  }

  @override
  Future<void> validate(
    EngineContext context,
    Map<String, String> rules, {
    bool bail = false,
    Map<String, String>? messages,
  }) async {
    throw UnimplementedError('validation moved to routed_validation');
  }

  @override
  Future<T> bind<T>(EngineContext context, T instance) async {
    final decoded = await _decodedBody(context);
    await bindBody(decoded, instance);
    return instance;
  }

  Future<void> bindBody(Map<String, dynamic> decoded, dynamic instance) async {
    if (instance is Map) {
      instance.addAll(decoded);
    } else if (instance is Bindable) {
      instance.bind(decoded);
    }
  }
}
