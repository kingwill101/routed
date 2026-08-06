// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:convert';

import 'package:routed/routed.dart'
    hide
        Binding,
        Bindable,
        MimeType,
        SseEvent,
        SseCodec,
        ContentNegotiator,
        NegotiatedMediaType;
import 'package:routed/src/validation/validator.dart';

import 'binding.dart';
import 'utils.dart';

/// Handles form binding and validation.
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
  Future<void> validate(
    EngineContext context,
    Map<String, String> rules, {
    bool bail = false,
    Map<String, String>? messages,
  }) async {
    final decoded = await _decodedBody(context);
    final registry = requireValidationRegistry(context.container);
    final validator = Validator.make(
      rules,
      registry: registry,
      bail: bail,
      messages: messages,
    );
    final errors = validator.validate(decoded);
    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
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
