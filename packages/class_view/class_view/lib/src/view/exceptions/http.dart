import 'dart:io';

class HttpException implements Exception {
  final int statusCode;
  final String message;

  const HttpException({required this.statusCode, required this.message});

  factory HttpException.notFound([String? message]) {
    return HttpException(
      statusCode: HttpStatus.notFound,
      message: message ?? 'Not Found',
    );
  }

  factory HttpException.badRequest([String? message]) {
    return HttpException(
      statusCode: HttpStatus.badRequest,
      message: message ?? 'Bad Request',
    );
  }

  factory HttpException.unauthorized() {
    return const HttpException(
      statusCode: HttpStatus.unauthorized,
      message: 'Unauthorized',
    );
  }

  factory HttpException.forbidden() {
    return const HttpException(
      statusCode: HttpStatus.forbidden,
      message: 'Forbidden',
    );
  }

  @override
  String toString() {
    return 'HttpException: $statusCode - $message';
  }

  factory HttpException.methodNotAllowed({
    required String message,
    required List<String> allowedMethods,
  }) {
    return HttpException(
      statusCode: HttpStatus.methodNotAllowed,
      message: message,
    );
  }
}
