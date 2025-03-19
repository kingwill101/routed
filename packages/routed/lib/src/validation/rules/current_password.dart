// NOTE: This is a placeholder. A real implementation would need to
// access the user's stored password and compare it securely.
import 'package:routed/src/validation/abstract_rule.dart';

class CurrentPasswordRule extends AbstractValidationRule {
  @override
  String get name => 'current_password';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The password does not match your current password.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    // In a real application, you would compare the input password
    // with the user's hashed password securely.  This is just a stub.
    print('Warning: CurrentPasswordRule is a placeholder and not secure!');
    return false; // Always fails for now (security).  Replace in a real app.
  }
}
