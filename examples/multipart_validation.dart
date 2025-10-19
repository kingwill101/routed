import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:routed/routed.dart';

void main() async {
  final engine = Engine(
    config: EngineConfig(
      multipart: MultipartConfig(
        maxFileSize: 5 * 1024 * 1024, // 5MB
        allowedExtensions: {'.jpg', '.png', '.pdf'},
        uploadDirectory: 'uploads',
      ),
    ),
  );

  // Ensure uploads directory exists
  await Directory('uploads').create(recursive: true);

  // Single file upload with validation
  engine.post('/upload/single', (ctx) async {
    final data = <String, dynamic>{};

    try {
      // Validate request data
      await ctx.validate({
        'title': 'required|string|min:3',
        'description': 'string',
        'file': 'required|file|max:5120', // 5MB in KB
        'tags': 'array',
      });

      // Bind validated data
      await ctx.bind(data);

      // Process file
      final file = await ctx.formFile('file');
      if (file != null) {
        final safeFileName =
            DateTime.now().millisecondsSinceEpoch.toString() +
            path.extension(file.filename);
        final savePath = path.join('uploads', safeFileName);
        await ctx.saveUploadedFile(file, savePath);

        data['fileInfo'] = {
          'originalName': file.filename,
          'savedAs': safeFileName,
          'size': file.size,
          'type': file.contentType,
        };
      }

      return ctx.json({'message': 'File uploaded successfully', 'data': data});
    } on ValidationError catch (e) {
      return ctx.json({
        'error': 'Validation failed',
        'errors': e.errors,
      }, statusCode: HttpStatus.unprocessableEntity);
    } catch (e) {
      return ctx.json({
        'error': 'Upload failed',
        'message': e.toString(),
      }, statusCode: HttpStatus.internalServerError);
    }
  });

  // Multiple files upload with validation
  engine.post('/upload/multiple', (ctx) async {
    final data = <String, dynamic>{};

    try {
      // Validate request data
      await ctx.validate({
        'category': 'required|string',
        'files': 'required|array|min:1',
        'files.*': 'file|max:5120', // Each file max 5MB
        'tags': 'array',
      });

      // Bind validated data
      await ctx.bind(data);

      // Process files
      final form = await ctx.multipartForm;
      final files = form.files.where((f) => f.name == 'files');
      final results = <Map<String, dynamic>>[];

      for (var file in files) {
        final safeFileName =
            DateTime.now().millisecondsSinceEpoch.toString() +
            path.extension(file.filename);
        final savePath = path.join('uploads', safeFileName);
        await ctx.saveUploadedFile(file, savePath);

        results.add({
          'originalName': file.filename,
          'savedAs': safeFileName,
          'size': file.size,
          'type': file.contentType,
        });
      }

      data['files'] = results;

      return ctx.json({'message': 'Files uploaded successfully', 'data': data});
    } on ValidationError catch (e) {
      return ctx.json({
        'error': 'Validation failed',
        'errors': e.errors,
      }, statusCode: HttpStatus.unprocessableEntity);
    } catch (e) {
      return ctx.json({
        'error': 'Upload failed',
        'message': e.toString(),
      }, statusCode: HttpStatus.internalServerError);
    }
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
  print('API Endpoints:');
  print('  POST /upload/single - Upload single file with validation');
  print('  POST /upload/multiple - Upload multiple files with validation');
}
