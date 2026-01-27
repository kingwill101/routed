library;

import 'dart:convert';
import 'dart:io';

import 'package:artisanal/artisanal.dart';
import 'package:artisanal/args.dart';
import 'package:inertia_dart/inertia_dart.dart';
import 'package:inertia_dart/src/cli/inertia_cli.dart';
import 'package:path/path.dart' as p;

/// Bootstraps a full Inertia stack for CLI smoke testing.
///
/// This script scaffolds a client, installs Inertia, and optionally starts
/// the dev server and a dart:io test server.
///
/// ```bash
/// dart run tool/bootstrap.dart --framework react
/// ```
///
/// Runs the bootstrap workflow for Inertia CLI validation.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'framework',
      abbr: 'f',
      defaultsTo: 'react',
      allowed: const ['react', 'vue', 'svelte'],
      help: 'Framework adapter to test (react, vue, svelte).',
    )
    ..addOption(
      'package-manager',
      abbr: 'p',
      defaultsTo: 'npm',
      allowed: const ['npm', 'pnpm', 'yarn', 'bun'],
      help: 'Package manager used during bootstrap.',
    )
    ..addOption(
      'name',
      defaultsTo: 'inertia_bootstrap',
      help: 'Project name to scaffold.',
    )
    ..addOption('output', help: 'Directory to create the project inside.')
    ..addFlag('cleanup', help: 'Remove the generated project after the run.')
    ..addFlag(
      'skip-dev-server',
      help: 'Skip running the Vite dev server bootstrap.',
    )
    ..addFlag('skip-server', help: 'Skip running the dart:io server bootstrap.')
    ..addOption(
      'dev-timeout',
      defaultsTo: '20',
      help: 'Seconds to wait for the Vite dev server hot file.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final results = parser.parse(args);
  if (results['help'] == true) {
    stdout.writeln('Usage: dart run tool/bootstrap.dart [options]');
    stdout.writeln(parser.usage);
    return;
  }

  final framework = results['framework'] as String;
  final manager = results['package-manager'] as String;
  final name = results['name'] as String;
  final output = results['output'] as String?;
  final cleanup = results['cleanup'] == true;
  final skipDevServer = results['skip-dev-server'] == true;
  final skipServer = results['skip-server'] == true;
  final devTimeoutSeconds =
      int.tryParse(results['dev-timeout'] as String? ?? '') ?? 20;

  final console = Console();
  final baseDir = output != null
      ? Directory(p.normalize(output))
      : await Directory.systemTemp.createTemp('inertia_bootstrap_');
  final projectDir = Directory(p.join(baseDir.path, name));

  console.title('Inertia CLI Bootstrap');
  console.twoColumnDetail('Framework', framework);
  console.twoColumnDetail('Package Manager', manager);
  console.twoColumnDetail('Output', projectDir.path);
  console.newLine();

  final cli = InertiaCli(
    stdoutSink: stdout,
    stderrSink: stderr,
    workingDirectory: baseDir,
  );

  var exitCode = await cli.run([
    'create',
    name,
    '--framework',
    framework,
    '--package-manager',
    manager,
    '--force',
  ]);

  if (exitCode != 0) {
    stderr.writeln('Create step failed with exit code $exitCode');
    exit(exitCode);
  }

  exitCode = await cli.run([
    'install',
    '--framework',
    framework,
    '--package-manager',
    manager,
    '--path',
    projectDir.path,
  ]);

  if (exitCode != 0) {
    stderr.writeln('Install step failed with exit code $exitCode');
    exit(exitCode);
  }

  console.success('Bootstrap complete.');
  console.writeln('Project at: ${projectDir.path}');

  final hotFile = File(p.join(projectDir.path, 'public', 'hot'));
  Process? devProcess;
  if (!skipDevServer) {
    final devResult = await console.task(
      'Starting Vite dev server',
      run: () async {
        devProcess = await _startDevServer(manager, projectDir);
        final ready = await _waitForHotFile(
          hotFile,
          Duration(seconds: devTimeoutSeconds),
        );
        return ready ? TaskResult.success : TaskResult.failure;
      },
    );
    if (devResult == TaskResult.failure) {
      stderr.writeln('Dev server failed to start.');
      exit(1);
    }
  }

  HttpServer? server;
  if (!skipServer) {
    final serverResult = await console.task(
      'Starting dart:io Inertia server',
      run: () async {
        server = await _startInertiaServer(console);
        final ok = await _probeServer(server!);
        return ok ? TaskResult.success : TaskResult.failure;
      },
    );
    if (serverResult == TaskResult.failure) {
      stderr.writeln('Inertia HttpServer probe failed.');
      exit(1);
    }
  }

  if (server != null) {
    await server!.close(force: true);
  }

  if (devProcess != null) {
    await _stopProcess(devProcess!);
  }

  if (cleanup) {
    await console.task(
      'Cleaning up project directory',
      run: () async {
        await projectDir.delete(recursive: true);
        return TaskResult.success;
      },
    );
  }
}

/// Starts the Vite dev server process.
Future<Process> _startDevServer(String manager, Directory projectDir) async {
  final args = _runScriptArgs(manager, 'dev');
  return Process.start(
    manager,
    args,
    workingDirectory: projectDir.path,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
}

/// Builds a package-manager script invocation for [script].
List<String> _runScriptArgs(String manager, String script) {
  switch (manager) {
    case 'pnpm':
    case 'yarn':
    case 'bun':
      return ['run', script];
    case 'npm':
    default:
      return ['run', script];
  }
}

/// Attempts to gracefully stop a process before force killing it.
Future<void> _stopProcess(Process process) async {
  process.kill(ProcessSignal.sigterm);
  final exited = await process.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () => -1,
  );
  if (exited == -1) {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}

/// Waits for the Vite hot file to be created and populated.
Future<bool> _waitForHotFile(File file, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (file.existsSync()) {
      final contents = file.readAsStringSync().trim();
      if (contents.isNotEmpty) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

/// Starts a minimal dart:io server that returns Inertia responses.
Future<HttpServer> _startInertiaServer(Console console) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    final inertiaRequest = inertiaRequestFromHttp(request);
    final context = inertiaRequest.createContext();
    final page = InertiaResponseFactory().buildPageData(
      component: 'Home',
      props: {'title': 'Inertia HttpServer'},
      url: inertiaRequest.url,
      context: context,
    );

    final response = inertiaRequest.isInertia
        ? InertiaResponse.json(page)
        : InertiaResponse.html(
            page,
            '<div id="app" data-page="${jsonEncode(page.toJson())}"></div>',
          );
    await writeInertiaResponse(request.response, response);
  });

  console.twoColumnDetail('HttpServer', 'http://127.0.0.1:${server.port}');
  return server;
}

/// Probes the running server and returns `true` on a 200 response.
Future<bool> _probeServer(HttpServer server) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    request.headers.set('X-Inertia', 'true');
    final response = await request.close();
    return response.statusCode == 200;
  } finally {
    client.close(force: true);
  }
}
