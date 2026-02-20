import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:server_native/src/generated/prebuilt_release.g.dart';

const _assetName = 'src/ffi.g.dart';
const _cratePath = 'native';
const _crateName = 'server_native';
const _prebuiltEnvVar = 'SERVER_NATIVE_PREBUILT';
const _projectPrebuiltRoot = '.dart_tool/server_native/prebuilt';
const _releaseRepo = 'kingwill101/routed';
const _releaseAssetPrefix = 'server_native';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;
    final linkMode = _linkMode(code.linkModePreference);
    final libraryName = code.targetOS
        .libraryFileName(_crateName, linkMode)
        .replaceAll('-', '_');
    final bundledLibUri = input.outputDirectory.resolve(libraryName);

    final prebuilt = await _findPrebuiltLibrary(input, code, libraryName);
    if (prebuilt != null) {
      stderr.writeln(
        '[server_native] using prebuilt native library: ${prebuilt.path}',
      );
      await prebuilt.copy(File.fromUri(bundledLibUri).path);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: _assetName,
          linkMode: linkMode,
          file: bundledLibUri,
        ),
      );
      return;
    }

    await const RustBuilder(
      assetName: _assetName,
      cratePath: _cratePath,
    ).run(input: input, output: output);
  });
}

Future<File?> _findPrebuiltLibrary(
  BuildInput input,
  CodeConfig code,
  String libraryName,
) async {
  final envPath = Platform.environment[_prebuiltEnvVar];
  if (envPath != null && envPath.isNotEmpty) {
    final file = File(envPath);
    if (file.existsSync()) {
      return file;
    }
    stderr.writeln(
      '[server_native] $_prebuiltEnvVar is set but file does not exist: $envPath',
    );
  }

  final platformLabel = _platformLabel(code);
  final projectRoot = _findProjectRoot(input.outputDirectory);
  if (projectRoot != null) {
    final candidates = <Uri>[
      projectRoot.resolve(
        '$_projectPrebuiltRoot/$serverNativePrebuiltReleaseTag/$platformLabel/$libraryName',
      ),
      projectRoot.resolve('$_projectPrebuiltRoot/$platformLabel/$libraryName'),
    ];
    for (final candidate in candidates) {
      final file = File.fromUri(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
  }

  final repoRoot = _findRepoRoot(input.packageRoot);
  if (repoRoot != null) {
    final candidates = <Uri>[
      repoRoot.resolve(
        '$_projectPrebuiltRoot/$serverNativePrebuiltReleaseTag/$platformLabel/$libraryName',
      ),
      repoRoot.resolve('$_projectPrebuiltRoot/$platformLabel/$libraryName'),
    ];
    for (final candidate in candidates) {
      final file = File.fromUri(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
  }

  final packagedCandidates = <Uri>[
    input.packageRoot.resolve(
      'native/prebuilt/$serverNativePrebuiltReleaseTag/$platformLabel/$libraryName',
    ),
    input.packageRoot.resolve('native/prebuilt/$platformLabel/$libraryName'),
    input.packageRoot.resolve('native/$platformLabel/$libraryName'),
  ];
  for (final candidate in packagedCandidates) {
    final file = File.fromUri(candidate);
    if (file.existsSync()) {
      return file;
    }
  }

  final downloaded = await _downloadPrebuiltLibrary(
    input: input,
    code: code,
    libraryName: libraryName,
    tag: serverNativePrebuiltReleaseTag,
  );
  if (downloaded != null) {
    stderr.writeln(
      '[server_native] downloaded prebuilt native library: ${downloaded.path}',
    );
    return downloaded;
  }

  return null;
}

Future<File?> _downloadPrebuiltLibrary({
  required BuildInput input,
  required CodeConfig code,
  required String libraryName,
  required String tag,
}) async {
  final platformLabel = _platformLabel(code);
  final projectRoot =
      _findProjectRoot(input.outputDirectory) ??
      _findRepoRoot(input.packageRoot);
  if (projectRoot == null) {
    return null;
  }

  final destinationDir = Directory.fromUri(
    projectRoot.resolve('$_projectPrebuiltRoot/$tag/$platformLabel/'),
  );
  destinationDir.createSync(recursive: true);
  final destinationFile = File('${destinationDir.path}/$libraryName');
  if (destinationFile.existsSync()) {
    return destinationFile;
  }

  final tarName = '$_releaseAssetPrefix-$platformLabel.tar.gz';
  final assetUrl = Uri.https(
    'github.com',
    '/$_releaseRepo/releases/download/${Uri.encodeComponent(tag)}/$tarName',
  );
  final tarFile = File('${destinationDir.path}/$tarName');

  try {
    final client = HttpClient();
    try {
      final request = await client.getUrl(assetUrl);
      request.headers.set(HttpHeaders.userAgentHeader, 'server_native-hook');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        stderr.writeln(
          '[server_native] prebuilt download skipped '
          '(${response.statusCode}) for $assetUrl',
        );
        return null;
      }
      final bytes = await response.expand((chunk) => chunk).toList();
      await tarFile.writeAsBytes(bytes);
    } finally {
      client.close(force: true);
    }

    final archiveBytes = GZipDecoder().decodeBytes(await tarFile.readAsBytes());
    final archive = TarDecoder().decodeBytes(archiveBytes);
    for (final file in archive.files.where((file) => file.isFile)) {
      final outputName = _archiveEntryBaseName(file.name);
      final outputFile = File('${destinationDir.path}/$outputName');
      await outputFile.writeAsBytes(file.content as List<int>);
    }

    if (destinationFile.existsSync()) {
      return destinationFile;
    }
  } catch (error) {
    stderr.writeln('[server_native] prebuilt download failed: $error');
  } finally {
    if (tarFile.existsSync()) {
      try {
        tarFile.deleteSync();
      } catch (_) {}
    }
  }

  return null;
}

String _archiveEntryBaseName(String name) {
  final normalized = name.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? normalized : segments.last;
}

LinkMode _linkMode(LinkModePreference preference) {
  return switch (preference) {
    LinkModePreference.dynamic ||
    LinkModePreference.preferDynamic => DynamicLoadingBundled(),
    LinkModePreference.static ||
    LinkModePreference.preferStatic => StaticLinking(),
    _ => throw UnsupportedError('Unsupported LinkModePreference: $preference'),
  };
}

String _platformLabel(CodeConfig code) {
  final os = switch (code.targetOS) {
    OS.linux => 'linux',
    OS.macOS => 'macos',
    OS.windows => 'windows',
    OS.android => 'android',
    OS.iOS => 'ios',
    _ => code.targetOS.toString(),
  };
  final arch = switch (code.targetArchitecture) {
    Architecture.x64 => 'x64',
    Architecture.arm64 => 'arm64',
    Architecture.arm when code.targetOS == OS.android => 'armv7',
    Architecture.arm => 'arm',
    Architecture.ia32 => 'x86',
    _ => code.targetArchitecture.toString(),
  };
  if (code.targetOS == OS.iOS &&
      code.targetArchitecture == Architecture.arm64 &&
      code.iOS.targetSdk == IOSSdk.iPhoneSimulator) {
    return 'ios-sim-arm64';
  }
  if (code.targetOS == OS.iOS && code.targetArchitecture == Architecture.x64) {
    return 'ios-sim-x64';
  }
  return '$os-$arch';
}

Uri? _findRepoRoot(Uri packageRoot) {
  var directory = Directory.fromUri(packageRoot).absolute;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        (Directory('${directory.path}/packages').existsSync() ||
            Directory('${directory.path}/pkgs').existsSync())) {
      return directory.uri;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}

Uri? _findProjectRoot(Uri outputDirectory) {
  var directory = Directory.fromUri(outputDirectory).absolute;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/.dart_tool').existsSync()) {
      return directory.uri;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}
