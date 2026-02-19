import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

const _assetName = 'src/ffi.g.dart';
const _cratePath = 'native';
const _crateName = 'routed_ffi_native';
const _prebuiltEnvVar = 'SERVER_NATIVE_PREBUILT';

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

    final prebuilt = _findPrebuiltLibrary(input, code, libraryName);
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

File? _findPrebuiltLibrary(
  BuildInput input,
  CodeConfig code,
  String libraryName,
) {
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
  final packagedCandidates = <Uri>[
    input.packageRoot.resolve('native/$platformLabel/$libraryName'),
    input.packageRoot.resolve('native/prebuilt/$platformLabel/$libraryName'),
  ];
  for (final candidate in packagedCandidates) {
    final file = File.fromUri(candidate);
    if (file.existsSync()) {
      return file;
    }
  }

  final repoRoot = _findRepoRoot(input.packageRoot);
  if (repoRoot != null) {
    final file = File.fromUri(
      repoRoot.resolve('.prebuilt/$platformLabel/$libraryName'),
    );
    if (file.existsSync()) {
      return file;
    }
  }

  final projectRoot = _findProjectRoot(input.outputDirectory);
  if (projectRoot != null) {
    final file = File.fromUri(
      projectRoot.resolve('.prebuilt/$platformLabel/$libraryName'),
    );
    if (file.existsSync()) {
      return file;
    }
  }

  return null;
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
