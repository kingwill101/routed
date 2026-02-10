import 'package:routed/routed.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('EngineError', () {
    test('constructor sets message and code', () {
      final err = EngineError(message: 'something broke', code: 500);
      expect(err.message, 'something broke');
      expect(err.code, 500);
    });

    test('code defaults to null', () {
      final err = EngineError(message: 'oops');
      expect(err.code, isNull);
    });

    test('toString without code', () {
      final err = EngineError(message: 'oops');
      expect(err.toString(), 'EngineError: oops');
    });

    test('toString with code', () {
      final err = EngineError(message: 'oops', code: 500);
      expect(err.toString(), 'EngineError(500): oops');
    });

    test('toJson without code', () {
      final err = EngineError(message: 'oops');
      final json = err.toJson();
      expect(json, {'message': 'oops'});
      expect(json.containsKey('code'), isFalse);
    });

    test('toJson with code', () {
      final err = EngineError(message: 'oops', code: 500);
      expect(err.toJson(), {'message': 'oops', 'code': 500});
    });

    test('fromJson roundtrip with code', () {
      final original = EngineError(message: 'test', code: 42);
      final restored = EngineError.fromJson(original.toJson());
      expect(restored.message, original.message);
      expect(restored.code, original.code);
    });

    test('fromJson roundtrip without code', () {
      final original = EngineError(message: 'no code');
      final restored = EngineError.fromJson(original.toJson());
      expect(restored.message, 'no code');
      expect(restored.code, isNull);
    });
  });

  group('ValidationError', () {
    test('default constructor has empty errors and code 422', () {
      final err = ValidationError();
      expect(err.errors, isEmpty);
      expect(err.code, 422);
    });

    test('message with no errors', () {
      expect(ValidationError().message, 'Validation failed.');
    });

    test('message with one field', () {
      final err = ValidationError({
        'email': ['required', 'invalid format'],
      });
      expect(err.message, 'Validation failed. 2 errors.');
    });

    test('message with multiple fields', () {
      final err = ValidationError({
        'email': ['required'],
        'name': ['too short'],
        'age': ['must be positive'],
      });
      expect(err.message, 'Validation failed. 3 errors.');
    });

    test('toString', () {
      final err = ValidationError();
      expect(err.toString(), 'ValidationError: Validation failed.');
    });

    test('toJson includes errors, code, and message', () {
      final err = ValidationError({
        'email': ['required'],
      });
      final json = err.toJson();
      expect(json['errors'], {
        'email': ['required'],
      });
      expect(json['code'], 422);
      expect(json['message'], contains('Validation failed'));
    });

    test('fromJson roundtrip', () {
      final original = ValidationError({
        'email': ['required', 'must be valid'],
        'name': ['too short'],
      });
      final restored = ValidationError.fromJson(original.toJson());
      expect(restored.errors, original.errors);
      expect(restored.code, 422);
    });
  });

  group('NotFoundError', () {
    test('default message', () {
      final err = NotFoundError();
      expect(err.message, 'Not found.');
      expect(err.code, 404);
    });

    test('custom message', () {
      final err = NotFoundError(message: 'User not found');
      expect(err.message, 'User not found');
      expect(err.code, 404);
    });

    test('toJson', () {
      final json = NotFoundError().toJson();
      expect(json['message'], 'Not found.');
      expect(json['code'], 404);
    });

    test('toString', () {
      expect(NotFoundError().toString(), 'EngineError(404): Not found.');
    });
  });

  group('UnauthorizedError', () {
    test('always returns code 401 and message Unauthorized.', () {
      final err = UnauthorizedError(message: 'ignored');
      expect(err.code, 401);
      // The getter overrides the super message
      expect(err.message, 'Unauthorized.');
    });

    test('toJson', () {
      final json = UnauthorizedError(message: 'x').toJson();
      expect(json['message'], 'Unauthorized.');
      expect(json['code'], 401);
    });
  });

  group('ForbiddenError', () {
    test('always returns code 403 and message Forbidden.', () {
      final err = ForbiddenError(message: 'ignored');
      expect(err.code, 403);
      expect(err.message, 'Forbidden.');
    });

    test('toJson', () {
      final json = ForbiddenError(message: 'x').toJson();
      expect(json['message'], 'Forbidden.');
      expect(json['code'], 403);
    });
  });

  group('InternalServerError', () {
    test('always returns code 500 and message Internal server error.', () {
      final err = InternalServerError(message: 'ignored');
      expect(err.code, 500);
      expect(err.message, 'Internal server error.');
    });

    test('toJson', () {
      final json = InternalServerError(message: 'x').toJson();
      expect(json['message'], 'Internal server error.');
      expect(json['code'], 500);
    });
  });

  group('BadRequestError', () {
    test('returns code 400 and message Bad request.', () {
      final err = BadRequestError();
      expect(err.code, 400);
      expect(err.message, 'Bad request.');
    });

    test('toJson', () {
      final json = BadRequestError().toJson();
      expect(json['message'], 'Bad request.');
      expect(json['code'], 400);
    });
  });

  group('JsonParseError', () {
    test('default has no details', () {
      final err = JsonParseError();
      expect(err.code, 400);
      expect(err.message, 'Invalid JSON payload.');
      expect(err.details, '');
    });

    test('with details appends to message', () {
      final err = JsonParseError(details: 'Unexpected token at position 5');
      expect(
        err.message,
        'Invalid JSON payload: Unexpected token at position 5',
      );
    });

    test('toJson has error field', () {
      final json = JsonParseError(details: 'bad').toJson();
      expect(json['error'], 'invalid_json');
      expect(json['message'], 'Invalid JSON payload: bad');
      expect(json['code'], 400);
    });
  });

  group('ConflictError', () {
    test('always returns code 409 and message Conflict.', () {
      final err = ConflictError(message: 'ignored');
      expect(err.code, 409);
      expect(err.message, 'Conflict.');
    });

    test('toJson', () {
      final json = ConflictError(message: 'x').toJson();
      expect(json['message'], 'Conflict.');
      expect(json['code'], 409);
    });
  });
}
