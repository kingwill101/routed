import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_http/src/binding/binding.dart';
import 'package:routed_http/src/binding/utils.dart';

/// Decodes URL-encoded form bodies into maps or [Bindable] models.
class FormBinding extends Binding {
  @override
  String get name => 'form';

  @override
  MimeType get mimeType => MimeType.postForm;

  Future<Map<String, dynamic>> _decodedBody(EngineContext ctx) async {
    final bodyBytes = await ctx.request.bytes;
    return parseUrlEncoded(utf8.decode(bodyBytes));
  }

  @override
  Future<T> bind<T>(EngineContext context, T instance) async {
    final decoded = await _decodedBody(context);
    await bindBody(decoded, instance);
    return instance;
  }

  /// Applies decoded form data to [instance].
  Future<void> bindBody(Map<String, dynamic> decoded, dynamic instance) async {
    if (instance is Map) {
      instance.addAll(decoded);
    } else if (instance is Bindable) {
      instance.bind(decoded);
    }
  }
}
