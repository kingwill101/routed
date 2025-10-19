import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:routed/routed.dart';

void main() async {
  final engine = Engine(
    config: EngineConfig(
      multipart: MultipartConfig(
          maxFileSize: 10 * 1024 * 1024, // 10MB
          allowedExtensions: {'.jpg', '.png', '.pdf'},
          uploadDirectory: 'uploads'),
    ),
  );
  engine.useViewEngine(LiquidViewEngine(
    directory: 'templates',
  ));

  // Ensure uploads directory exists
  await Directory('uploads').create(recursive: true);

  // Serve upload form
  engine.get('/', (ctx) {
    return ctx.html('upload_form.liquid', data: {
      'page_title': 'File Upload Example',
      'max_size': '10MB',
      'allowed_types': 'JPG, PNG, PDF'
    });
  });

  // Handle file upload
  engine.post('/upload', (ctx) async {
    try {
      final file = await ctx.formFile('file');

      if (file == null) {
        return ctx.json({'error': 'No file uploaded'}, statusCode: 400);
      }

      // Get additional form data
      final description = await ctx.postForm('description');

      // Save file with original name
      final fileName = file.filename;
      final savePath =
          ctx.engineConfig.fileSystem.path.join('uploads', fileName);
      await ctx.saveUploadedFile(file, savePath);

      return ctx.json({
        'message': 'File uploaded successfully',
        'filename': fileName,
        'size': file.size,
        'type': file.contentType,
        'description': description
      });
    } catch (e) {
      return ctx
          .json({'error': 'Upload failed: ${e.toString()}'}, statusCode: 500);
    }
  });

  // List uploaded files
  engine.get('/files', (ctx) {
    final dir = ctx.engineConfig.fileSystem.directory('uploads');
    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => {
              'name': path.basename(f.path),
              'size': f.lengthSync(),
              'modified': f.lastModifiedSync().toIso8601String()
            })
        .toList();

    return ctx.html('file_list.liquid',
        data: {'page_title': 'Uploaded Files', 'files': files});
  });

  // Serve uploaded files
  engine.get('/files/:filename', (ctx) async {
    final filename = ctx.param('filename');
    final filePath = path.join('uploads', filename);

    if (!File(filePath).existsSync()) {
      return ctx.json({'error': 'File not found'}, statusCode: 404);
    }

    return ctx.file(filePath);
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
}
