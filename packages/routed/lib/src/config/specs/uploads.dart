import 'package:routed/src/engine/config.dart';
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
    return {
      'max_memory': _defaultMaxMemory,
      'max_file_size': _defaultMaxFileSize,
      'max_disk_usage': _defaultMaxDiskUsage,
      'allowed_extensions': _defaultAllowedExtensions,
      'directory': _defaultDirectory,
      'file_permissions': _defaultFilePermissions,
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
    final maxMemoryValue = map['max_memory'];
    final int maxMemory;
    if (maxMemoryValue == null) {
      maxMemory = _defaultMaxMemory;
    } else if (maxMemoryValue is int) {
      maxMemory = maxMemoryValue;
    } else {
      throw ProviderConfigException('uploads.max_memory must be an integer');
    }

    final maxFileSizeValue = map['max_file_size'];
    final int maxFileSize;
    if (maxFileSizeValue == null) {
      maxFileSize = _defaultMaxFileSize;
    } else if (maxFileSizeValue is int) {
      maxFileSize = maxFileSizeValue;
    } else {
      throw ProviderConfigException(
        'uploads.max_file_size must be an integer',
      );
    }

    final maxDiskUsageValue = map['max_disk_usage'];
    final int maxDiskUsage;
    if (maxDiskUsageValue == null) {
      maxDiskUsage = _defaultMaxDiskUsage;
    } else if (maxDiskUsageValue is int) {
      maxDiskUsage = maxDiskUsageValue;
    } else {
      throw ProviderConfigException(
        'uploads.max_disk_usage must be an integer',
      );
    }

    final allowedExtensionsValue = map['allowed_extensions'];
    final Set<String> allowedExtensions;
    if (allowedExtensionsValue == null) {
      allowedExtensions = _defaultAllowedExtensions.toSet();
    } else if (allowedExtensionsValue is List) {
      final collected = <String>[];
      for (var i = 0; i < allowedExtensionsValue.length; i += 1) {
        final entry = allowedExtensionsValue[i];
        if (entry is! String) {
          throw ProviderConfigException(
            'uploads.allowed_extensions[$i] must be a string',
          );
        }
        collected.add(entry);
      }
      allowedExtensions = collected.toSet();
    } else {
      throw ProviderConfigException('uploads.allowed_extensions must be a list');
    }

    final directoryValue = map['directory'];
    final String directory;
    if (directoryValue == null) {
      directory = _defaultDirectory;
    } else if (directoryValue is String) {
      directory = directoryValue;
    } else {
      throw ProviderConfigException('uploads.directory must be a string');
    }

    final filePermissionsValue = map['file_permissions'];
    final int filePermissions;
    if (filePermissionsValue == null) {
      filePermissions = _defaultFilePermissions;
    } else if (filePermissionsValue is int) {
      filePermissions = filePermissionsValue;
    } else {
      throw ProviderConfigException(
        'uploads.file_permissions must be an integer',
      );
    }

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
