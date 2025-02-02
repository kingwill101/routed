import 'package:routed/routed.dart';

class CustomError implements Exception {
  final String message;
  final int code;

  CustomError(this.message, this.code);
}

void main(List<String> args) async {
  final engine = Engine();

  // Global error handler middleware
  engine.middlewares.add((ctx) async {
    try {
      await ctx.next();
    } on CustomError catch (e) {
      ctx.status(e.code);
      ctx.json({
        'error': e.message,
        'code': e.code,
      });
    } catch (e) {
      ctx.status(500);
      ctx.json({
        'error': 'Internal Server Error',
        'message': e.toString(),
      });
    }
  });

  // Route that throws a custom error
  engine.get('/custom-error', (ctx) {
    throw CustomError('Resource not found', 404);
  });

  // Route that throws a standard error
  engine.get('/standard-error', (ctx) {
    throw Exception('Something went wrong');
  });

  // Route with validation error handling
  engine.post('/validate', (ctx) async {
    try {
      await ctx.validate({
        'email': 'required|email',
        'age': 'required|numeric|min:18',
      });
      ctx.json({'message': 'Validation passed'});
    } on ValidationError catch (e) {
      ctx.status(422);
      ctx.json({'errors': e.errors});
    }
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
