import 'dart:convert';

import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/validation/validator.dart';

/// A class that handles JSON binding and validation for incoming requests.
class JsonBinding extends Binding {
  /// The name of the binding, which is 'json'.
  @override
  String get name => 'json';

  @override
  MimeType get mimeType => MimeType.json;

  /// Decodes the body of the request from JSON format.
  ///
  /// This method reads the bytes from the request body, decodes them into a UTF-8 string,
  /// and then parses that string into a `Map<String, dynamic>` using jsonDecode.
  ///
  /// [ctx] - The EngineContext containing the request information.
  ///
  /// Returns a Future that completes with the decoded JSON body as a Map.
  Future<Map<String, dynamic>> _decodedBody(EngineContext ctx) async {
    final bodyBytes = await ctx.request.bytes;
    return jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
  }

  /// Validates the JSON body of the request against a set of rules.
  ///
  /// This method first decodes the JSON body using [_decodedBody], then creates a Validator
  /// with the provided rules, and finally validates the decoded JSON. If there are any validation
  /// errors, a ValidationError is thrown.
  ///
  /// [context] - The EngineContext containing the request information.
  /// [rules] - A Map of validation rules to apply to the JSON body.
  ///
  /// Returns a Future that completes when validation is done.
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

  /// Binds the JSON body of the request to an instance.
  ///
  /// This method first decodes the JSON body using [_decodedBody], then binds the decoded
  /// JSON to the provided instance. If validation rules are provided, it validates the JSON
  /// body before binding.
  ///
  /// [context] - The EngineContext containing the request information.
  /// [instance] - The instance to bind the JSON data to.
  /// [rules] - An optional Map of validation rules to apply to the JSON body.
  ///
  /// Returns a Future that completes when binding is done.
  @override
  Future<T> bind<T>(
    EngineContext context,
    T instance, {
    Map<String, String>? rules,
  }) async {
    final decoded = await _decodedBody(context);
    await bindBody(decoded, instance);
    return instance;
  }

  /// Binds the decoded JSON body to an instance.
  ///
  /// This method adds all key-value pairs from the decoded JSON to the provided instance
  /// if the instance is a Map or implements Bindable.
  ///
  /// [decoded] - The decoded JSON body as a Map.
  /// [instance] - The instance to bind the JSON data to.
  ///
  /// Returns a Future that completes when binding is done.
  Future<void> bindBody(Map<String, dynamic> decoded, dynamic instance) async {
    if (instance is Map) {
      instance.addAll(decoded);
    } else if (instance is Bindable) {
      instance.bind(decoded);
    }
  }
}
