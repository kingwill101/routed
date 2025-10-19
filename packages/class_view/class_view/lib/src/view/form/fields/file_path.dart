import 'dart:io';

import 'package:path/path.dart' as path_lib;

import '../validation.dart';
import 'choice.dart';

/// A field that allows choosing from files in a given directory.
class FilePathField extends ChoiceField<String> {
  /// The absolute path to the directory to list files from.
  final String path;

  /// A regular expression pattern that the filenames must match.
  final String? match;

  /// Whether to recursively include files in subdirectories.
  final bool recursive;

  /// Whether to include directories in the list of choices.
  final bool allowFolders;

  /// Whether to include files in the list of choices.
  final bool allowFiles;

  FilePathField({
    required this.path,
    this.match,
    this.recursive = false,
    this.allowFolders = false,
    this.allowFiles = true,
    super.required = true,
    super.widget,
    super.label,
    super.initial,
    super.helpText,
    super.errorMessages,
    super.showHiddenInitial,
    super.validators,
    super.localize = false,
    super.disabled = false,
    super.labelSuffix,
  }) : super(choices: []) {
    // Check if directory exists
    if (!Directory(path).existsSync()) {
      throw FileSystemException('Directory not found', path);
    }

    // Build choices
    choices.clear();
    choices.addAll(_buildChoices());
  }

  List<List<dynamic>> _buildChoices() {
    final dir = Directory(path);
    final List<List<dynamic>> choices = [];
    final RegExp? matchPattern = match != null ? RegExp(match!) : null;

    void addEntry(FileSystemEntity entity, String relativePath) {
      final basename = path_lib.basename(entity.path);
      // For top-level entries, just use the basename
      // For nested entries, use the relative path with the basename
      final displayPath = relativePath.isEmpty
          ? basename
          : '$relativePath/$basename';
      final relativeDisplayPath = path_lib
          .normalize(displayPath)
          .replaceAll(r'\', '/');

      if (entity is Directory && allowFolders) {
        choices.add([entity.path, relativeDisplayPath]);
      } else if (entity is File && allowFiles) {
        if (matchPattern == null || matchPattern.hasMatch(basename)) {
          choices.add([entity.path, relativeDisplayPath]);
        }
      }
    }

    if (recursive) {
      dir.listSync(recursive: true, followLinks: false).forEach((entity) {
        final relativePath = path_lib.relative(
          path_lib.dirname(entity.path),
          from: path,
        );
        addEntry(entity, relativePath);
      });
    } else {
      dir.listSync(followLinks: false).forEach((entity) {
        addEntry(entity, '');
      });
    }

    choices.sort((a, b) => (a[1] as String).compareTo(b[1] as String));
    return choices;
  }

  @override
  String? toDart(dynamic value) {
    if (value == null || value == '') {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?['required'] ?? defaultErrorMessages['required']!,
          ],
        });
      }
      return null;
    }

    final stringValue = value.toString();

    // Check if the value is in the list of choices
    if (!choices.any((choice) => choice[0] == stringValue)) {
      throw ValidationError({
        'invalid': ['$stringValue is not one of the available choices.'],
      });
    }

    // Ensure the path exists and is within the base directory
    final normalizedPath = path_lib.normalize(stringValue);
    if (!normalizedPath.startsWith(path) ||
        !FileSystemEntity.isFileSync(normalizedPath)) {
      throw ValidationError({
        'invalid': ['$stringValue is not one of the available choices.'],
      });
    }

    return stringValue;
  }
}
