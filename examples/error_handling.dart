import 'package:routed/routed.dart';

// Custom error type
class ResourceError extends EngineError {
  @override
  get code => HttpStatus.conflict;

  ResourceError() : super(message: "Resource already exists");
}

void main() async {
  final engine = Engine();

  // Validation error example
  engine.get('/validation-error', (ctx) {
    throw ValidationError({
      'email': ['Invalid email format'],
      'password': ['Password must be at least 8 characters'],
    });
  });

  // Engine error example
  engine.get('/engine-error', (ctx) {
    throw EngineError(message: 'Resource not found', code: HttpStatus.notFound);
  });

  // Custom error type example
  engine.get('/custom-error', (ctx) {
    throw ResourceError();
  });

  // Uncaught exception example
  engine.get('/uncaught-error', (ctx) {
    throw Exception('Something went wrong!');
  });

  // Form validation example
  engine.post('/users', (ctx) async {
    final body = await ctx.body();

    final errors = <String, List<String>>{};

    // Simulate form validation
    if (!body.contains('"email"')) {
      errors['email'] = ['Email is required'];
    }
    if (!body.contains('"password"')) {
      errors['password'] = ['Password is required'];
    }

    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }

    return ctx.json({'message': 'User created successfully'});
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
}
