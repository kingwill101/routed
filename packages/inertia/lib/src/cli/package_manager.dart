/// Defines commands for package managers used by the CLI.
///
/// ```dart
/// final manager = InertiaPackageManager.parse('pnpm');
/// ```
class InertiaPackageManager {
  /// Creates a package manager configuration.
  const InertiaPackageManager({
    required this.command,
    required this.createCommand,
    required this.installArgs,
  });

  /// The executable name to run (e.g., `npm`, `pnpm`).
  final String command;

  /// The command used for project creation.
  final String createCommand;

  /// Default install arguments for dependencies.
  final List<String> installArgs;

  /// Returns arguments to create a Vite project.
  List<String> createArgs(String template, String output) {
    switch (command) {
      case 'pnpm':
        return ['create', 'vite', output, '--', '--template', template];
      case 'yarn':
        return ['create', 'vite', output, '--template', template];
      case 'bun':
        return ['create', 'vite', output, '--template', template];
      case 'npm':
      default:
        return ['create', 'vite@latest', output, '--', '--template', template];
    }
  }

  /// Returns arguments to install [deps].
  List<String> addArgs(List<String> deps) {
    switch (command) {
      case 'pnpm':
      case 'yarn':
      case 'bun':
        return ['add', ...deps];
      case 'npm':
      default:
        return ['install', ...deps];
    }
  }

  /// Parses [value] into a package manager configuration.
  static InertiaPackageManager parse(String? value) {
    switch (value) {
      case 'pnpm':
        return const InertiaPackageManager(
          command: 'pnpm',
          createCommand: 'pnpm',
          installArgs: ['install'],
        );
      case 'yarn':
        return const InertiaPackageManager(
          command: 'yarn',
          createCommand: 'yarn',
          installArgs: ['install'],
        );
      case 'bun':
        return const InertiaPackageManager(
          command: 'bun',
          createCommand: 'bun',
          installArgs: ['install'],
        );
      case 'npm':
      default:
        return const InertiaPackageManager(
          command: 'npm',
          createCommand: 'npm',
          installArgs: ['install'],
        );
    }
  }
}
