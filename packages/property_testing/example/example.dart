import 'package:property_testing/property_testing.dart';

void main() async {
  // Using the new PropertyTestRunner with an email generator
  final runner = PropertyTestRunner(Specialized.email(), (email) {
    // You can add property assertions here
    assert(email.contains('@'), 'Email should contain @');

    // Example property test
    final parts = email.split('@');
    assert(parts.length == 2, 'Email should have exactly one @');

    // Property: email should have local part and domain
    assert(parts[0].isNotEmpty, 'Local part should not be empty');
    assert(parts[1].isNotEmpty, 'Domain should not be empty');
  }, PropertyConfig(numTests: 100));

  final result = await runner.run();
  if (!result.success) {
    print(result.report);
  }
}
