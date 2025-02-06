# Routed Multipart Example

This example demonstrates file uploads and multipart form handling in the routed package.

## Features Demonstrated

- File upload handling
- Multipart form configuration
- File size limits
- File type restrictions
- File storage and serving
- Form data processing
- Error handling

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. Visit http://localhost:3000 in your browser
3. Upload files using the form
4. View uploaded files at http://localhost:3000/files

## Configuration

The example includes:
- Maximum file size: 10MB
- Allowed file types: JPG, PNG, PDF
- Upload directory: ./uploads

## Code Structure

- `bin/server.dart`: Server implementation
- `templates/`: Liquid templates for UI
- `uploads/`: Directory for uploaded files (created at runtime)
- `pubspec.yaml`: Project dependencies