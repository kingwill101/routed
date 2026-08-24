import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:artisanal/args.dart';
import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:routed_cli/routed_cli.dart' show CliLogger;

import 'package:routed_cli/src/console/util/dart_exec.dart';
import 'package:routed_cli/src/console/util/pubspec.dart';

/// Whether [args] select a command that may be provided by the current project.
///
/// Global invocations and registered built-ins bypass project discovery so a
/// broken `lib/commands.dart` cannot prevent unrelated CLI functionality.
bool shouldLoadProjectCommands(
  Iterable<String> args,
  CommandRunner<void> runner,
) {
  final values = args.toList(growable: false);
  if (values.isEmpty) return false;
  final selection = values.firstWhere(
    (value) => !value.startsWith('-'),
    orElse: () => '',
  );
  if (selection.isEmpty || runner.commands.containsKey(selection)) {
    return false;
  }
  // The runner normalizes this documented nested spelling after parsing.
  if (selection == 'openapi' && values.contains('generate')) {
    return false;
  }
  return true;
}

/// Metadata describing a single option provided by a project command.
class ProjectCommandOption {
  /// Creates metadata for one project-command option.
  ProjectCommandOption({
    required this.name,
    required this.type,
    this.abbr,
    this.help,
    this.valueHelp,
    this.defaultsTo,
    this.allowed,
    this.allowedHelp,
    this.negatable,
    this.hideNegatedUsage,
    this.splitCommas,
    this.mandatory,
    this.hide,
    this.aliases = const <String>[],
  });

  /// Decodes option metadata from the project-command protocol.
  factory ProjectCommandOption.fromJson(Map<String, Object?> json) {
    return ProjectCommandOption(
      name: json['name']! as String,
      type: json['type']! as String,
      abbr: json['abbr'] as String?,
      help: json['help'] as String?,
      valueHelp: json['valueHelp'] as String?,
      defaultsTo: json['defaultsTo'],
      allowed: (json['allowed'] as List?)?.cast<String>(),
      allowedHelp: (json['allowedHelp'] as Map?)?.map(
        (key, value) => MapEntry(key as String, value as String),
      ),
      negatable: json['negatable'] as bool?,
      hideNegatedUsage: json['hideNegatedUsage'] as bool?,
      splitCommas: json['splitCommas'] as bool?,
      mandatory: json['mandatory'] as bool?,
      hide: json['hide'] as bool?,
      aliases: (json['aliases'] as List?)?.cast<String>() ?? const <String>[],
    );
  }

  /// Option name passed to the argument parser.
  final String name;

  /// Protocol type: `flag`, `single`, or `multiple`.
  final String type;

  /// Optional short spelling for the option.
  final String? abbr;

  /// Help text displayed by the parser.
  final String? help;

  /// Placeholder text displayed for value-taking options.
  final String? valueHelp;

  /// Default value supplied by the project command.
  final Object? defaultsTo;

  /// Values accepted by the option, when constrained.
  final List<String>? allowed;

  /// Help text associated with each allowed value.
  final Map<String, String>? allowedHelp;

  /// Whether a flag can be negated.
  final bool? negatable;

  /// Whether the negated spelling is hidden from usage output.
  final bool? hideNegatedUsage;

  /// Whether comma-separated values are split.
  final bool? splitCommas;

  /// Whether a value is required by the parser.
  final bool? mandatory;

  /// Whether the option is hidden from usage output.
  final bool? hide;

  /// Alternative names accepted by the parser.
  final List<String> aliases;

  /// Adds this option to [parser].
  void configureParserArg(ArgParser parser) {
    switch (type) {
      case 'flag':
        parser.addFlag(
          name,
          abbr: abbr,
          help: help,
          defaultsTo: defaultsTo is bool ? defaultsTo as bool? : null,
          negatable: negatable ?? true,
          hide: hide ?? false,
          hideNegatedUsage: hideNegatedUsage ?? false,
          aliases: aliases,
        );
      case 'single':
        parser.addOption(
          name,
          abbr: abbr,
          help: help,
          valueHelp: valueHelp,
          defaultsTo: defaultsTo is String ? defaultsTo as String? : null,
          allowed: allowed,
          allowedHelp: allowedHelp,
          mandatory: mandatory ?? false,
          hide: hide ?? false,
          aliases: aliases,
        );
      case 'multiple':
        parser.addMultiOption(
          name,
          abbr: abbr,
          help: help,
          valueHelp: valueHelp,
          allowed: allowed,
          allowedHelp: allowedHelp,
          defaultsTo: defaultsTo is List
              ? (defaultsTo! as List).map((e) => e.toString()).toList()
              : null,
          splitCommas: splitCommas ?? true,
          hide: hide ?? false,
          aliases: aliases,
        );
      default:
        throw ArgumentError('Unsupported option type "$type" for "$name".');
    }
  }
}

/// Metadata describing a discovered project command.
class ProjectCommandInfo {
  /// Creates metadata for a discovered project command.
  ProjectCommandInfo({
    required this.name,
    required this.description,
    required this.summary,
    required this.category,
    required this.hidden,
    required this.aliases,
    required this.options,
  });

  /// Decodes command metadata from the project-command protocol.
  factory ProjectCommandInfo.fromJson(Map<String, Object?> json) {
    final options = (json['options'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (dynamic value) =>
              ProjectCommandOption.fromJson(value as Map<String, Object?>),
        )
        .toList();
    return ProjectCommandInfo(
      name: json['name']! as String,
      description: json['description']! as String,
      summary: json['summary']! as String,
      category: json['category'] as String? ?? '',
      hidden: json['hidden'] as bool? ?? false,
      aliases: (json['aliases'] as List?)?.cast<String>() ?? const <String>[],
      options: options,
    );
  }

  /// Command name exposed to the top-level runner.
  final String name;

  /// Full command description.
  final String description;

  /// Short command summary.
  final String summary;

  /// Help category used by the command runner.
  final String category;

  /// Whether the command is hidden from usage output.
  final bool hidden;

  /// Alternative command names.
  final List<String> aliases;

  /// Options accepted by the command.
  final List<ProjectCommandOption> options;
}

/// Proxies project-defined commands so they can be exposed through the routed
/// CLI command runner.
class ProjectCommandProxy extends Command<void> {
  /// Creates a proxy for a project command described by [info].
  ProjectCommandProxy({
    required ProjectCommandInfo info,
    required ProjectCommandsLoader loader,
  }) : _info = info,
       _loader = loader {
    for (final option in info.options) {
      option.configureParserArg(argParser);
    }
  }

  final ProjectCommandInfo _info;
  final ProjectCommandsLoader _loader;

  @override
  String get name => _info.name;

  @override
  String get description => _info.description;

  @override
  String get summary => _info.summary;

  @override
  String get category => _info.category;

  @override
  bool get hidden => _info.hidden;

  @override
  List<String> get aliases => _info.aliases;

  @override
  Future<void> run() async {
    final commandArgs = argResults?.arguments ?? const <String>[];
    final exitCode = await _loader.runProjectCommand(_info.name, commandArgs);
    if (exitCode != 0) {
      io.exitCode = exitCode;
    }
  }
}

/// Handles discovery and execution of project-defined commands.
class ProjectCommandsLoader {
  /// Creates a project-command loader.
  ProjectCommandsLoader({CliLogger? logger, fs.FileSystem? fileSystem})
    : logger = logger ?? CliLogger(),
      fileSystem = fileSystem ?? const LocalFileSystem();

  /// Logger used for discovery and execution diagnostics.
  final CliLogger logger;

  /// Filesystem abstraction used for project discovery.
  final fs.FileSystem fileSystem;

  String get _scriptRelativePath =>
      p.join('.dart_tool', 'routed', 'project_commands_runner.dart');

  List<ProjectCommandInfo>? _cached;

  /// Discovers and describes commands from the current project.
  Future<List<ProjectCommandInfo>> loadProjectCommands(String usage) async {
    if (_cached != null) {
      return _cached!;
    }

    final projectRoot = await _findProjectRoot();
    if (projectRoot == null) {
      _cached = const [];
      return _cached!;
    }

    final commandsEntry = fileSystem.file(
      p.join(projectRoot.path, 'lib', 'commands.dart'),
    );
    if (!commandsEntry.existsSync()) {
      _cached = const [];
      return _cached!;
    }

    final packageName = await readPackageName(projectRoot);
    if (packageName == null || packageName.isEmpty) {
      _cached = const [];
      return _cached!;
    }

    final scriptFile = fileSystem.file(
      p.join(projectRoot.path, _scriptRelativePath),
    );
    await scriptFile.parent.create(recursive: true);
    await scriptFile.writeAsString(_buildRunnerScript(packageName));

    final result = await _runDescribe(projectRoot);
    if (result.exitCode != 0) {
      final errorMessage = result.stderr.trim().isEmpty
          ? 'Failed to load project commands (exit code ${result.exitCode}).'
          : result.stderr.trim();
      throw UsageException(errorMessage, usage);
    }

    final decoded = _decodeDescribeOutput(result.stdout, usage);
    final commands =
        (decoded['commands'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (dynamic entry) =>
                  ProjectCommandInfo.fromJson(entry as Map<String, Object?>),
            )
            .toList();

    _cached = commands;
    return commands;
  }

  /// Whether a non-empty command list has already been loaded.
  bool get hasCachedCommands => _cached != null && _cached!.isNotEmpty;

  /// Runs a project command and returns its process exit code.
  Future<int> runProjectCommand(
    String commandName,
    List<String> commandArgs,
  ) async {
    final projectRoot = await _findProjectRoot();
    if (projectRoot == null) {
      logger.error('Unable to locate project root to run "$commandName".');
      return 64;
    }

    final scriptFile = fileSystem.file(
      p.join(projectRoot.path, _scriptRelativePath),
    );
    if (!scriptFile.existsSync()) {
      logger.error(
        'Project command runner not found. Run any routed CLI command once '
        'to regenerate it.',
      );
      return 64;
    }

    final process = await startDartProcess([
      'run',
      _scriptRelativePath,
      '--run',
      commandName,
      ...commandArgs,
    ], workingDirectory: projectRoot.path);

    await Future.wait([
      io.stdout.addStream(process.stdout),
      io.stderr.addStream(process.stderr),
    ]);

    return process.exitCode;
  }

  /// Registers [commands] with [runner], rejecting name conflicts.
  void registerWithRunner(
    CommandRunner<void> runner,
    List<ProjectCommandInfo> commands,
    String usage,
  ) {
    if (commands.isEmpty) {
      return;
    }

    final existingNames = runner.commands.keys.toSet();
    for (final command in commands) {
      final hasConflict =
          existingNames.contains(command.name) ||
          command.aliases.any(existingNames.contains);
      if (hasConflict) {
        throw UsageException(
          'Project command "${command.name}" conflicts with an existing '
          'command.',
          usage,
        );
      }

      runner.addCommand(ProjectCommandProxy(info: command, loader: this));
      existingNames
        ..add(command.name)
        ..addAll(command.aliases);
    }
  }

  Map<String, Object?> _decodeDescribeOutput(String output, String usage) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      throw UsageException('Project command runner produced no output.', usage);
    }

    Map<String, Object?>? decoded;
    try {
      final json = jsonDecode(trimmed);
      if (json is Map<String, Object?>) {
        decoded = json;
      }
    } on FormatException {
      // Fall back to extracting the last JSON object from mixed output.
    }

    if (decoded == null) {
      final start = trimmed.lastIndexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        final slice = trimmed.substring(start, end + 1);
        final json = jsonDecode(slice);
        if (json is Map<String, Object?>) {
          decoded = json;
        }
      }
    }

    if (decoded == null) {
      throw UsageException(
        'Failed to parse project command metadata output.',
        usage,
      );
    }

    return decoded;
  }

  Future<_ProcessResult> _runDescribe(fs.Directory projectRoot) async {
    final process = await startDartProcess([
      'run',
      _scriptRelativePath,
      '--describe',
    ], workingDirectory: projectRoot.path);

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .listen(stdoutBuffer.write)
          .asFuture<void>(),
      process.stderr
          .transform(utf8.decoder)
          .listen(stderrBuffer.write)
          .asFuture<void>(),
    ]);

    final exitCode = await process.exitCode;

    return _ProcessResult(
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }

  Future<fs.Directory?> _findProjectRoot() async {
    var current = fileSystem.currentDirectory.absolute;
    for (var i = 0; i < 10; i++) {
      final pubspec = fileSystem.file(p.join(current.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        return current;
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
    return null;
  }

  String _buildRunnerScript(String packageName) {
    return '''
// Generated by routed. Do not edit by hand.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:$packageName/commands.dart' as project_commands;

Future<void> main(List<String> args) async {
  final commands = await _loadCommands();
  if (args.isEmpty || args.first == '--describe') {
    _printMetadata(commands);
    return;
  }

  if (args.first == '--run') {
    if (args.length < 2) {
      stderr.writeln(
        'Missing command name for project command execution.',
      );
      exit(64);
    }
    final commandName = args[1];
    final rest = args.sublist(2);
    await _executeCommand(commands, commandName, rest);
    return;
  }

  stderr.writeln('Unsupported arguments: \${args.join(' ')}');
  exit(64);
}

Future<List<Command<void>>> _loadCommands() async {
  final result = await Future.sync(
    () => project_commands.buildProjectCommands(),
  );
  if (result is! List) {
    stderr.writeln(
      'Expected buildProjectCommands() to return List<Command<void>>.',
    );
    exit(64);
  }

  final commands = <Command<void>>[];
  for (final entry in result) {
    if (entry is Command<void>) {
      commands.add(entry);
    } else if (entry is Command) {
      commands.add(entry as Command<void>);
    } else {
      stderr.writeln(
        'Invalid command returned from buildProjectCommands(): \${entry.runtimeType}.',
      );
      exit(64);
    }
  }
  return commands;
}

void _printMetadata(List<Command<void>> commands) {
  final payload = {
    'commands': commands.map(_describeCommand).toList(),
  };
  stdout.write(jsonEncode(payload));
}

Future<void> _executeCommand(
  List<Command<void>> commands,
  String commandName,
  List<String> args,
) async {
  final runner = CommandRunner<void>(
    '$packageName',
    'Project commands for $packageName.',
  );
  for (final command in commands) {
    runner.addCommand(command);
  }

  try {
    await runner.run([commandName, ...args]);
  } on UsageException catch (error) {
    stderr.writeln(error);
    exit(64);
  }
}

Map<String, Object?> _describeCommand(Command<void> command) {
  return {
    'name': command.name,
    'description': command.description,
    'summary': command.summary,
    'category': command.category,
    'hidden': command.hidden,
    'aliases': command.aliases,
    'options': command.argParser.options.values
        .where((option) => option.name != 'help')
        .map(_describeOption)
        .toList(),
  };
}

Map<String, Object?> _describeOption(dynamic option) {
  return {
    'name': option.name,
    'abbr': option.abbr,
    'help': option.help,
    'valueHelp': option.valueHelp,
    'allowed': option.allowed,
    'allowedHelp': option.allowedHelp
        ?.map((key, value) => MapEntry(key, value.toString())),
    'defaultsTo': _normalizeDefault(option.defaultsTo),
    'negatable': option.negatable,
    'hideNegatedUsage': option.hideNegatedUsage,
    'type': option.isFlag
        ? 'flag'
        : option.isSingle
            ? 'single'
            : 'multiple',
    'splitCommas': option.splitCommas,
    'mandatory': option.mandatory,
    'hide': option.hide,
    'aliases': option.aliases,
  };
}

Object? _normalizeDefault(Object? value) {
  if (value == null) return null;
  if (value is num || value is bool || value is String) {
    return value;
  }
  if (value is Iterable) {
    return value.map((item) => _normalizeDefault(item)).toList();
  }
  return value.toString();
}
''';
  }
}

class _ProcessResult {
  _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
