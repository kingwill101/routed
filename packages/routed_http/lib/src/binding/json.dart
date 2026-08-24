import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_http/src/binding/binding.dart';

/// Decodes JSON object bodies into maps or [Bindable] models.
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
        // JsonParseError is the framework's public EngineError contract.
        // ignore: only_throw_errors
        throw JsonParseError(
          details: 'Expected JSON object, got ${decoded.runtimeType}',
        );
      }
      return decoded;
    } on FormatException catch (e) {
      // JsonParseError is the framework's public EngineError contract.
      // ignore: only_throw_errors
      throw JsonParseError(details: e.message);
    }
  }

  @override
  Future<T> bind<T>(EngineContext context, T instance) async {
    final decoded = await _decodedBody(context);
    await bindBody(decoded, instance);
    return instance;
  }

  /// Applies decoded JSON data to [instance].
  Future<void> bindBody(Map<String, dynamic> decoded, dynamic instance) async {
    if (instance is Map) {
      instance.addAll(decoded);
    } else if (instance is Bindable) {
      instance.bind(decoded);
    }
  }
}
