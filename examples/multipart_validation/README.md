# Routed Multipart Validation Example

This example demonstrates form validation with file uploads using the routed package.

## Features Demonstrated

- Form data validation
- File validation
- Multiple file handling
- Validation error handling
- Data binding

## API Endpoints

### POST /upload/single
Upload a single file with metadata.

Request:
```
Content-Type: multipart/form-data
Body:
  - title: string (required, min length: 3)
  - description: string (optional)
  - file: File (required, max size: 5MB)
  - tags[]: string (optional array)
```

Success Response (200):
```json
{
  "message": "File uploaded successfully",
  "data": {
    "title": "Example Upload",
    "description": "Optional description",
    "tags": ["tag1", "tag2"],
    "fileInfo": {
      "originalName": "example.jpg",
      "savedAs": "1234567890.jpg",
      "size": 1024,
      "type": "image/jpeg"
    }
  }
}
```

### POST /upload/multiple
Upload multiple files with metadata.

Request:
```
Content-Type: multipart/form-data
Body:
  - category: string (required)
  - files[]: File (required, at least 1 file, each max 5MB)
  - tags[]: string (optional array)
```

Success Response (200):
```json
{
  "message": "Files uploaded successfully",
  "data": {
    "category": "documents",
    "tags": ["tag1", "tag2"],
    "files": [
      {
        "originalName": "doc1.pdf",
        "savedAs": "1234567890.pdf",
        "size": 1024,
        "type": "application/pdf"
      }
    ]
  }
}
```

### Validation Error Response (422):
```json
{
  "error": "Validation failed",
  "errors": {
    "title": ["The title field is required"],
    "file": ["The file must not be larger than 5MB"],
    "files": ["At least one file is required"]
  }
}
```

## Configuration

- Maximum file size: 5MB
- Allowed file types: JPG, PNG, PDF
- Upload directory: ./uploads

## Code Structure

- `bin/server.dart`: Server implementation with validation
- `uploads/`: Directory for uploaded files (created at runtime)
- `pubspec.yaml`: Project dependencies
