import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/provider/config_utils.dart';

import '../spec.dart';

const int _defaultMaxMemory = 32 * 1024 * 1024;
const int _defaultMaxFileSize = 10 * 1024 * 1024;
const int _defaultMaxDiskUsage = 32 * 1024 * 1024;
const List<String> _defaultAllowedExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'pdf',
];
const String _defaultDirectory = 'uploads';
const int _defaultFilePermissions = 750;

class UploadsConfigSpec extends ConfigSpec<MultipartConfig> {
  const UploadsConfigSpec();

  @override
  String get root => 'uploads';

  @override
  Schema? get schema =>
      ConfigSchema.object(
        title: 'Uploads Configuration',
        description: 'Multipart request and file upload settings.',
        properties: {
          'max_memory': ConfigSchema.integer(
        description: 'Maximum in-memory bytes before buffering to disk.',
        defaultValue: _defaultMaxMemory,
      ),
          'max_file_size': ConfigSchema.integer(
        description: 'Maximum accepted upload size in bytes.',
        defaultValue: _defaultMaxFileSize,
      ),
          'max_disk_usage': ConfigSchema.integer(
        description:
            'Maximum cumulative bytes written to disk per request before uploads are rejected.',
        defaultValue: _defaultMaxDiskUsage,
      ),
          'allowed_extensions': ConfigSchema.list(
        description: 'Whitelisted file extensions for uploads.',
            items: ConfigSchema.string(),
        defaultValue: _defaultAllowedExtensions,
      ),
          'directory': ConfigSchema.string(
        description: 'Directory where uploaded files are stored.',
        defaultValue: _defaultDirectory,
      ),
          'file_permissions': ConfigSchema.integer(
        description: 'Permissions to apply to uploaded files.',
        defaultValue: _defaultFilePermissions,
      ),
        },
      );

  @override
  MultipartConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final maxMemory =
        parseIntLike(
          map['max_memory'],
          context: 'uploads.max_memory',
          throwOnInvalid: true,
        ) ??
        _defaultMaxMemory;

    final maxFileSize =
        parseIntLike(
          map['max_file_size'],
          context: 'uploads.max_file_size',
          throwOnInvalid: true,
        ) ??
        _defaultMaxFileSize;

    final maxDiskUsage =
        parseIntLike(
          map['max_disk_usage'],
          context: 'uploads.max_disk_usage',
          throwOnInvalid: true,
        ) ??
        _defaultMaxDiskUsage;

    final allowedExtensions =
        (parseStringList(
              map['allowed_extensions'],
              context: 'uploads.allowed_extensions',
              allowEmptyResult: true,
              throwOnInvalid: true,
            ) ??
            _defaultAllowedExtensions)
            .map((entry) => entry.toLowerCase())
            .toSet();

    final directory =
        parseStringLike(
          map['directory'],
          context: 'uploads.directory',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        _defaultDirectory;

    final filePermissions =
        parseIntLike(
          map['file_permissions'],
          context: 'uploads.file_permissions',
          throwOnInvalid: true,
        ) ??
        _defaultFilePermissions;

    return MultipartConfig(
      maxMemory: maxMemory,
      maxFileSize: maxFileSize,
      maxDiskUsage: maxDiskUsage,
      allowedExtensions: allowedExtensions,
      uploadDirectory: directory,
      filePermissions: filePermissions,
    );
  }

  @override
  Map<String, dynamic> toMap(MultipartConfig value) {
    return {
      'max_memory': value.maxMemory,
      'max_file_size': value.maxFileSize,
      'max_disk_usage': value.maxDiskUsage,
      'allowed_extensions': value.allowedExtensions.toList(),
      'directory': value.uploadDirectory,
      'file_permissions': value.filePermissions,
    };
  }
}

class UploadsConfigContext extends ConfigSpecContext {
  const UploadsConfigContext({
    required this.engineConfig,
    super.config,
  });

  final EngineConfig engineConfig;
}
