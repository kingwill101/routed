import 'dart:convert';
import 'package:routed/routed.dart';
import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/binding/utils.dart';
import 'package:routed/src/validation/validator.dart';

/// A class that handles form binding and validation.
class FormBinding extends Binding {
  /// The name of the binding, which is 'form'.
  @override
  String get name => 'form';

  /// Decodes the body of the request from the given [EngineContext].
  ///
  /// This method reads the bytes from the request body, decodes them using UTF-8,
  /// and then parses the URL-encoded string into a map.
  ///
  /// Returns a [Future] that completes with a [Map] containing the decoded body.
  Future<Map<String, dynamic>> _decodedBody(EngineContext ctx) async {
    final bodyBytes =
        await ctx.request.bytes; // Read the bytes from the request body.
    return parseUrlEncoded(
        utf8.decode(bodyBytes)); // Decode and parse the body.
  }

  /// Validates the request body against the given [rules].
  ///
  /// This method decodes the request body, creates a [Validator] with the provided rules,
  /// and validates the decoded body. If there are validation errors, a [ValidationError] is thrown.
  ///
  /// [context] is the [EngineContext] of the request.
  /// [rules] is a [Map] of validation rules.
  ///
  /// Returns a [Future] that completes when validation is done.
  @override
  Future<void> validate(EngineContext context, Map<String, String> rules,
      {bool bail = false}) async {
    final decoded = await _decodedBody(context); // Decode the request body.
    final validator =
        Validator.make(rules, bail: bail); // Create a validator with the rules.
    final errors = validator.validate(decoded); // Validate the decoded body.

    if (errors.isNotEmpty) {
      throw ValidationError(errors); // Throw an error if validation fails.
    }
  }

  /// Binds the request body to the given [instance].
  ///
  /// This method decodes the request body and binds it to the provided instance.
  ///
  /// [context] is the [EngineContext] of the request.
  /// [instance] is the object to bind the decoded body to.
  ///
  /// Returns a [Future] that completes when binding is done.
  @override
  Future<void> bind(EngineContext context, dynamic instance) async {
    final decoded = await _decodedBody(context); // Decode the request body.
    await bindBody(decoded, instance); // Bind the decoded body to the instance.
  }

  /// Binds the decoded body to the given [instance].
  ///
  /// This method adds all key-value pairs from the decoded body to the instance if it is a [Map].
  ///
  /// [decoded] is the [Map] containing the decoded body.
  /// [instance] is the object to bind the decoded body to.
  ///
  /// Returns a [Future] that completes when binding is done.
  Future<void> bindBody(Map<String, dynamic> decoded, dynamic instance) async {
    if (instance is Map) {
      instance.addAll(decoded); // Add all key-value pairs to the instance.
    }
  }
}
