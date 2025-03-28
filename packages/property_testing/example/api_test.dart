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
      // Test properties of the generated User
      expect(user.name, equals(user.email.split('@')[0]));
      expect(user.email.contains('@'), isTrue);
      expect(user.age, greaterThanOrEqualTo(18));
      expect(user.age, lessThanOrEqualTo(99));

      // Test JSON conversion
      final json = user.toJson();
      expect(json['name'], equals(user.name));
      expect(json['email'], equals(user.email));
      expect(json['age'], equals(user.age));
    },
    PropertyConfig(numTests: 100),
  );

  final result = await runner.run();
  print(result.report);
}
