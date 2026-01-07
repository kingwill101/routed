import 'package:routed/src/engine/config.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

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
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    var maxMemory = _defaultMaxMemory;
    var maxFileSize = _defaultMaxFileSize;
    var maxDiskUsage = _defaultMaxDiskUsage;
    var allowedExtensions = _defaultAllowedExtensions;
    var directory = _defaultDirectory;
    var filePermissions = _defaultFilePermissions;
    if (context is UploadsConfigContext) {
      final multipart = context.engineConfig.multipart;
      maxMemory = multipart.maxMemory;
      maxFileSize = multipart.maxFileSize;
      maxDiskUsage = multipart.maxDiskUsage;
      allowedExtensions = multipart.allowedExtensions.toList(growable: false);
      directory = multipart.uploadDirectory;
      filePermissions = multipart.filePermissions;
    }
    return {
      'max_memory': maxMemory,
      'max_file_size': maxFileSize,
      'max_disk_usage': maxDiskUsage,
      'allowed_extensions': allowedExtensions,
      'directory': directory,
      'file_permissions': filePermissions,
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('max_memory'),
        type: 'int',
        description: 'Maximum in-memory bytes before buffering to disk.',
        defaultValue: _defaultMaxMemory,
      ),
      ConfigDocEntry(
        path: path('max_file_size'),
        type: 'int',
        description: 'Maximum accepted upload size in bytes.',
        defaultValue: _defaultMaxFileSize,
      ),
      ConfigDocEntry(
        path: path('max_disk_usage'),
        type: 'int',
        description:
            'Maximum cumulative bytes written to disk per request before uploads are rejected.',
        defaultValue: _defaultMaxDiskUsage,
      ),
      ConfigDocEntry(
        path: path('allowed_extensions'),
        type: 'list<string>',
        description: 'Whitelisted file extensions for uploads.',
        defaultValue: _defaultAllowedExtensions,
      ),
      ConfigDocEntry(
        path: path('directory'),
        type: 'string',
        description: 'Directory where uploaded files are stored.',
        defaultValue: _defaultDirectory,
      ),
      ConfigDocEntry(
        path: path('file_permissions'),
        type: 'int',
        description: 'Permissions to apply to uploaded files.',
        defaultValue: _defaultFilePermissions,
      ),
    ];
  }

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
