import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

// Define a User class to test with
class User {
  final String name;
  final String email;
  final int age;

  User({required this.name, required this.email, required this.age});

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'age': age,
      };
}

void main() async {
  // Create a generator for User objects
  final emailGenerator = Specialized.email();
  final userGenerator = emailGenerator.map((email) => User(
        name: email.split('@')[0], // Use local part of email as name
        email: email,
        age: 18 + (email.hashCode % 82), // Random age between 18-99
      ));

  final runner = PropertyTestRunner(
      userGenerator,
      (user) {
        // Test properties of the generated User using assert
        assert(user.name == user.email.split('@')[0], 'Name mismatch');
        assert(user.email.contains('@'), 'Email should contain @');
        assert(user.age >= 18, 'Age should be >= 18');
        assert(user.age <= 99, 'Age should be <= 99');
  
        // Test JSON conversion using assert
        final json = user.toJson();
        assert(json['name'] == user.name, 'JSON name mismatch');
        assert(json['email'] == user.email, 'JSON email mismatch');
        assert(json['age'] == user.age, 'JSON age mismatch');
      },
    PropertyConfig(numTests: 100),
  );

  final result = await runner.run();
  if (!result.success) {
    print(result.report);
  }
}
