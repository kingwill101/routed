import 'package:pulumi/pulumi.dart' as pulumi;
import 'package:pulumi_cloudflare/index.dart' as cloudflare;

/// Pulumi configuration and resource graph for the Cloudflare auth example.
class CloudflareAuthStack extends pulumi.Stack {
  CloudflareAuthStack() {
    final config = pulumi.Config();
    final accountId = config.require('accountId');
    final workerName =
        config.get('workerName') ?? 'routed-cloudflare-auth-example';
    final databaseId = config.require('databaseId');
    final authOrigin = config.require('authOrigin');
    final wrapperPath =
        config.get('wrapperPath') ??
        '../.dart_tool/routed/deploy/cloudflare/worker.js';
    final dartBundlePath =
        config.get('dartBundlePath') ??
        '../.dart_tool/routed/deploy/cloudflare/worker.dart.js';
    final inheritExistingBindings =
        config.getBoolean('inheritExistingBindings') ?? true;

    final sessionKey = config.get('sessionKey');
    final bindings = <cloudflare.WorkerVersionBinding>[
      _plainTextBinding('AUTH_ORIGIN', authOrigin),
      cloudflare.WorkerVersionBinding(
        name: pulumi.Input.fromValue('AUTH_DB'),
        type: pulumi.Input.fromValue('d1'),
        databaseId: pulumi.Input.fromValue(databaseId),
      ),
      cloudflare.WorkerVersionBinding(
        name: pulumi.Input.fromValue('RATE_LIMIT_STORE'),
        type: pulumi.Input.fromValue('durable_object_namespace'),
        className: pulumi.Input.fromValue('CloudflareRateLimitStoreObject'),
      ),
      _sessionBinding(config, sessionKey, inheritExistingBindings),
    ];

    _addOptionalSocialBindings(
      config,
      bindings,
      publicKey: 'GITHUB_CLIENT_ID',
      secretKey: 'GITHUB_CLIENT_SECRET',
      inheritExistingBindings: inheritExistingBindings,
    );
    _addOptionalSocialBindings(
      config,
      bindings,
      publicKey: 'DROPBOX_CLIENT_ID',
      secretKey: 'DROPBOX_CLIENT_SECRET',
      inheritExistingBindings: inheritExistingBindings,
    );
    _addOptionalSocialBindings(
      config,
      bindings,
      publicKey: 'TELEGRAM_BOT_USERNAME',
      secretKey: 'TELEGRAM_BOT_TOKEN',
      inheritExistingBindings: inheritExistingBindings,
    );

    final migrations = _durableObjectMigration(config);
    final version = cloudflare.WorkerVersion(
      'workerVersion',
      args: cloudflare.WorkerVersionArgs(
        accountId: pulumi.Input.fromValue(accountId),
        workerId: pulumi.Input.fromValue(workerName),
        mainModule: pulumi.Input.fromValue('worker.js'),
        compatibilityDate: pulumi.Input.fromValue('2026-08-20'),
        compatibilityFlags: pulumi.Input.fromValue(['nodejs_compat']),
        modules: pulumi.Input.fromValue([
          cloudflare.WorkerVersionModule(
            name: pulumi.Input.fromValue('worker.js'),
            contentFile: pulumi.Input.fromValue(wrapperPath),
            contentType: pulumi.Input.fromValue(
              'application/javascript+module',
            ),
          ),
          cloudflare.WorkerVersionModule(
            name: pulumi.Input.fromValue('worker.dart.js'),
            contentFile: pulumi.Input.fromValue(dartBundlePath),
            contentType: pulumi.Input.fromValue('application/javascript'),
          ),
        ]),
        bindings: pulumi.Input.fromValue(bindings),
        migrations: migrations,
        annotations: pulumi.Input.fromValue(
          cloudflare.WorkerVersionAnnotations(
            workersMessage: pulumi.Input.fromValue(
              'Routed auth example deployment',
            ),
          ),
        ),
      ),
    );

    final deployment = cloudflare.WorkersDeployment(
      'deployment',
      args: cloudflare.WorkersDeploymentArgs(
        accountId: pulumi.Input.fromValue(accountId),
        scriptName: pulumi.Input.fromValue(workerName),
        strategy: pulumi.Input.fromValue('percentage'),
        versions: pulumi.Input.fromValue([
          cloudflare.WorkersDeploymentVersion(
            percentage: pulumi.Input.fromValue(100.0),
            versionId: version.id,
          ),
        ]),
      ),
    );

    _outputProperties = [
      pulumi.OutputProperty(
        'workerName',
        pulumi.Output.create<Object?>(workerName),
      ),
      pulumi.OutputProperty(
        'versionId',
        version.id.apply<Object?>((value) => value),
      ),
      pulumi.OutputProperty(
        'deploymentId',
        deployment.id.apply<Object?>((value) => value),
      ),
    ];
  }

  static cloudflare.WorkerVersionBinding _secretTextBinding(
    String key,
    String value,
    pulumi.Config config,
  ) {
    if (!config.isSecret(key)) {
      throw pulumi.ConfigException(
        "Configuration '$key' must be set with 'pulumi config set --secret'.",
      );
    }
    return cloudflare.WorkerVersionBinding(
      name: pulumi.Input.fromValue(key),
      type: pulumi.Input.fromValue('secret_text'),
      text: pulumi.secretInput(pulumi.Input.fromValue(value)),
    );
  }

  static cloudflare.WorkerVersionBinding _sessionBinding(
    pulumi.Config config,
    String? value,
    bool inheritExistingBindings,
  ) {
    if (value != null) {
      return _secretTextBinding('SESSION_KEY', value, config);
    }
    if (inheritExistingBindings) {
      return _inheritBinding('SESSION_KEY');
    }
    throw pulumi.ConfigException(
      "Missing 'sessionKey'. Set it with 'pulumi config set --secret' "
      "or enable 'inheritExistingBindings'.",
    );
  }

  static cloudflare.WorkerVersionBinding _inheritBinding(String key) {
    return cloudflare.WorkerVersionBinding(
      name: pulumi.Input.fromValue(key),
      type: pulumi.Input.fromValue('inherit'),
      versionId: pulumi.Input.fromValue('latest'),
    );
  }

  static cloudflare.WorkerVersionBinding _plainTextBinding(
    String name,
    String value,
  ) {
    return cloudflare.WorkerVersionBinding(
      name: pulumi.Input.fromValue(name),
      type: pulumi.Input.fromValue('plain_text'),
      text: pulumi.Input.fromValue(value),
    );
  }

  static void _addOptionalSocialBindings(
    pulumi.Config config,
    List<cloudflare.WorkerVersionBinding> bindings, {
    required String publicKey,
    required String secretKey,
    required bool inheritExistingBindings,
  }) {
    final publicValue = config.get(publicKey);
    final secretValue = config.get(secretKey);
    if (publicValue == null && secretValue == null) {
      if (inheritExistingBindings) {
        bindings
          ..add(_inheritBinding(publicKey))
          ..add(_inheritBinding(secretKey));
      }
      return;
    }
    if (publicValue == null || secretValue == null) {
      throw pulumi.ConfigException(
        "Both '$publicKey' and '$secretKey' are required together.",
      );
    }
    if (!config.isSecret(secretKey)) {
      throw pulumi.ConfigException(
        "Configuration '$secretKey' must be set with 'pulumi config set --secret'.",
      );
    }
    bindings.add(_plainTextBinding(publicKey, publicValue));
    bindings.add(_secretTextBinding(secretKey, secretValue, config));
  }

  static pulumi.Input<cloudflare.WorkerVersionMigrations?>?
  _durableObjectMigration(pulumi.Config config) {
    if (config.getBoolean('applyDurableObjectMigration') != true) {
      return null;
    }
    final newTag = config.get('durableObjectMigrationTag') ?? 'routed-auth-v1';
    final oldTag = config.get('durableObjectMigrationOldTag');
    return pulumi.Input.fromValue(
      cloudflare.WorkerVersionMigrations(
        newSqliteClasses: pulumi.Input.fromValue([
          'CloudflareRateLimitStoreObject',
        ]),
        newTag: pulumi.Input.fromValue(newTag),
        oldTag: oldTag == null ? null : pulumi.Input.fromValue(oldTag),
      ),
    );
  }

  @override
  List<pulumi.OutputProperty> getOutputProperties() => _outputProperties;

  late final List<pulumi.OutputProperty> _outputProperties;
}

/// Starts the Pulumi deployment program.
Future<void> main() async {
  await pulumi.Deployment.runOrThrow(() => CloudflareAuthStack());
}
