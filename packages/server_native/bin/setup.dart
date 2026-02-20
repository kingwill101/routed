/// Downloads the prebuilt server_native library for a target platform.
///
/// Usage:
///   dart run server_native:setup [--tag server-native-prebuilt-v0.1.2] [--platform linux-x64]
///
/// By default this resolves the latest prebuilt-only release and host platform.
library;

import 'dart:convert';
import 'dart:io';

const _repo = 'kingwill101/routed';
const _defaultTag = 'latest';
const _prebuiltTagPrefix = 'server-native-prebuilt-v';
const _artifactPrefix = 'server_native';
const _supportedPlatforms = <String>{
  'linux-x64',
  'linux-arm64',
  'macos-arm64',
  'macos-x64',
  'windows-x64',
  'windows-arm64',
  'android-arm64',
  'android-armv7',
  'android-x64',
  'ios-arm64',
  'ios-sim-arm64',
  'ios-sim-x64',
};

Future<void> main(List<String> args) async {
  var tag = _defaultTag;
  String? platform;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tag':
      case '-t':
        tag = args[++i];
      case '--platform':
      case '-p':
        platform = args[++i];
      case '--help':
      case '-h':
        stdout.writeln(
          'Usage: dart run server_native:setup [options]\n'
          '\n'
          'Downloads a prebuilt server_native library to:\n'
          '  .prebuilt/<platform>/\n'
          '\n'
          'Options:\n'
          '  --tag, -t       Binary release tag '
          '(default: latest prebuilt release)\n'
          '  --platform, -p  e.g. linux-x64 (default: host platform)\n',
        );
        return;
    }
  }

  platform ??= _hostPlatform();
  if (!_supportedPlatforms.contains(platform)) {
    stderr.writeln(
      'Unsupported platform "$platform".\n'
      'Supported: ${_supportedPlatforms.join(', ')}',
    );
    exitCode = 1;
    return;
  }

  final filename = '$_artifactPrefix-$platform.tar.gz';
  final projectRoot = _findProjectRoot(Directory.current);
  final outDir = Directory('${projectRoot.path}/.prebuilt/$platform')
    ..createSync(recursive: true);

  stdout.writeln('server_native setup');
  stdout.writeln('  Repo:     $_repo');
  stdout.writeln('  Tag:      $tag');
  stdout.writeln('  Platform: $platform');
  stdout.writeln('  Artifact: $filename');
  stdout.writeln('  Target:   ${outDir.path}');
  stdout.writeln('');

  try {
    await _downloadAndExtract(tag: tag, filename: filename, outDir: outDir);
    stdout.writeln('Done. Build hooks will now prefer this prebuilt artifact.');
  } on Exception catch (error) {
    stderr.writeln('Failed: $error');
    exitCode = 1;
  }
}

Future<void> _downloadAndExtract({
  required String tag,
  required String filename,
  required Directory outDir,
}) async {
  final resolvedTag = tag == _defaultTag
      ? await _latestPrebuiltTag(requiredAssetName: filename)
      : tag;
  final ghArgs = <String>[
    'release',
    'download',
    resolvedTag,
    '--repo',
    _repo,
    '--pattern',
    filename,
    '--dir',
    outDir.path,
    '--clobber',
  ];
  final ghResult = await Process.run('gh', ghArgs);

  final tarPath = '${outDir.path}/$filename';
  if (ghResult.exitCode != 0) {
    final encodedTag = Uri.encodeComponent(resolvedTag);
    final url =
        'https://github.com/$_repo/releases/download/$encodedTag/$filename';
    stdout.writeln('  gh CLI failed, falling back to curl...');
    final curlResult = await Process.run('curl', [
      '-fSL',
      '--retry',
      '3',
      '-o',
      tarPath,
      url,
    ]);
    if (curlResult.exitCode != 0) {
      throw Exception(
        'Download failed.\n'
        'gh stderr:\n${ghResult.stderr}\n'
        'curl stderr:\n${curlResult.stderr}',
      );
    }
  }

  final extractResult = await Process.run('tar', [
    'xzf',
    tarPath,
    '-C',
    outDir.path,
  ]);
  if (extractResult.exitCode != 0) {
    throw Exception('tar extract failed: ${extractResult.stderr}');
  }

  File(tarPath).deleteSync();

  final extracted = outDir.listSync().whereType<File>().toList();
  if (extracted.isEmpty) {
    throw Exception('No files extracted to ${outDir.path}');
  }
  for (final file in extracted) {
    stdout.writeln('  Extracted: ${file.path}');
  }
}

Future<String> _latestPrebuiltTag({required String requiredAssetName}) async {
  final url = Uri.https(
    'api.github.com',
    '/repos/$_repo/releases',
    <String, String>{'per_page': '100'},
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'server_native-setup');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'Failed to resolve release tags (${response.statusCode})',
      );
    }
    final body = await utf8.decodeStream(response);
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw Exception('Unexpected releases payload');
    }

    String? fallbackWithAsset;
    for (final release in decoded) {
      if (release is! Map<String, Object?>) {
        continue;
      }
      final tag = release['tag_name'];
      if (tag is! String || tag.isEmpty) {
        continue;
      }
      final assets = release['assets'];
      final hasAsset =
          assets is List &&
          assets.any(
            (asset) =>
                asset is Map<String, Object?> &&
                asset['name'] == requiredAssetName,
          );
      if (!hasAsset) {
        continue;
      }
      if (tag.startsWith(_prebuiltTagPrefix)) {
        return tag;
      }
      fallbackWithAsset ??= tag;
    }

    if (fallbackWithAsset != null) {
      return fallbackWithAsset;
    }

    throw Exception(
      'No release found with asset "$requiredAssetName". '
      'Create a prebuilt release with tag prefix "$_prebuiltTagPrefix".',
    );
  } finally {
    client.close(force: true);
  }
}

String _hostPlatform() {
  final os = Platform.operatingSystem;
  final arch = _hostArch();
  return switch (os) {
    'linux' => 'linux-$arch',
    'macos' => 'macos-$arch',
    'windows' => 'windows-$arch',
    _ => '$os-$arch',
  };
}

String _hostArch() {
  if (Platform.isWindows) {
    final value = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
    return value.toUpperCase().contains('ARM') ? 'arm64' : 'x64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  return switch (machine) {
    'x86_64' || 'amd64' => 'x64',
    'aarch64' || 'arm64' => 'arm64',
    _ => machine,
  };
}

Directory _findProjectRoot(Directory start) {
  var directory = start.absolute;

  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        (Directory('${directory.path}/packages').existsSync() ||
            Directory('${directory.path}/pkgs').existsSync())) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }

  directory = start.absolute;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return start;
    }
    directory = parent;
  }
}
