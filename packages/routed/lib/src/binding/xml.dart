import 'package:routed/routed.dart';
import 'package:routed/src/binding/binding.dart';

/// A class that handles XML binding for the routing engine.
///
/// This class extends the [Binding] class and provides specific implementations
/// for binding and validating XML data.
class XmlBinding extends Binding {
  /// The name of this binding, which is 'xml'.
  @override
  String get name => 'xml';

  /// Binds the XML data from the request context to the given instance.
  ///
  /// This method retrieves the body bytes from the request context and is
  /// intended to bind these bytes to the provided instance. The actual binding
  /// logic is currently commented out.
  ///
  /// [context] - The context of the engine containing the request information.
  /// [instance] - The instance to which the XML data should be bound.
  @override
  Future<void> bind(EngineContext context, dynamic instance) async {
    final bodyBytes = await context.request.bytes;
    // The following line is commented out and should contain the logic to bind
    // the body bytes to the instance.
    // await bindBody(bodyBytes, instance);
  }

  /// Validates the XML data in the request context against the provided rules.
  ///
  /// This method is intended to validate the XML data but currently throws an
  /// [UnimplementedError] as the validation logic is not yet implemented.
  ///
  /// [context] - The context of the engine containing the request information.
  /// [rules] - A map of validation rules to apply to the XML data.
  @override
  Future<void> validate(
      EngineContext context, Map<String, String> rules) async {
    // XML validation will be implemented later
    throw UnimplementedError('XML validation not yet implemented');
  }
}
