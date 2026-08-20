/// Protocol version shared by the deployed Worker and the local runner.
const deployedWorkerAuthProtocolVersion = 1;

/// Header carrying the one-purpose conformance token.
const deployedWorkerAuthTokenHeader = 'X-Routed-Auth-Conformance-Token';

/// One public Routed auth contract exercised by the deployed Worker harness.
enum DeployedWorkerAuthSuite {
  session('session'),
  jwt('jwt'),
  plugins('plugins'),
  externalProviders('external-providers'),
  webAuthn('webauthn');

  const DeployedWorkerAuthSuite(this.id);

  final String id;

  static DeployedWorkerAuthSuite parse(String value) {
    final normalized = value.trim().toLowerCase();
    return values.firstWhere(
      (suite) => suite.id == normalized,
      orElse: () => throw const FormatException('Unknown auth suite.'),
    );
  }
}
