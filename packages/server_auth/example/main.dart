import 'package:server_auth/server_auth.dart';

Future<void> main() async {
  runProviderExample();
  await runJwtExample();
  await runGateExample();
}

void runProviderExample() {
  final registry = AuthProviderRegistry.instance;
  registerAllAuthProviders(registry);

  final google = googleProvider(
    const GoogleProviderOptions(
      clientId: 'demo-google-client-id',
      clientSecret: 'demo-google-client-secret',
      redirectUri: 'https://example.com/auth/callback/google',
    ),
  );

  print('provider id = ${google.id}');
}

Future<void> runJwtExample() async {
  final sessionOptions = const JwtSessionOptions(
    secret: 'replace-with-a-strong-secret',
    issuer: 'example-app',
    audience: <String>['example-api'],
    maxAge: Duration(minutes: 30),
  );

  final issued = issueAuthJwtToken(
    options: sessionOptions,
    claims: <String, dynamic>{
      'sub': 'user_42',
      'roles': <String>['admin'],
    },
  );

  final verifier = JwtVerifier(options: sessionOptions.toVerifierOptions());
  final payload = await verifier.verifyToken(issued.token);
  print('jwt subject = ${payload.subject}');
}

Future<void> runGateExample() async {
  final gates = AuthGateService<Map<String, dynamic>>();
  gates.register(
    'posts.update',
    rolesGate(<String>['editor', 'admin'], any: true),
  );

  final principal = AuthPrincipal(id: 'user_42', roles: <String>['admin']);
  final allowed = await gates.can(
    'posts.update',
    context: <String, dynamic>{'resourceId': 'post_1'},
    principal: principal,
  );

  print('can update post = $allowed');
}
