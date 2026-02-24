import 'package:server_auth/server_auth.dart';

Future<void> main() async {
  runProviderExample();
  await runJwtExample();
  await runBearerAdapterExample();
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

class _ExampleRequestContext {
  final Map<String, Object?> attributes = <String, Object?>{};

  void setAttribute(String key, Object? value) {
    attributes[key] = value;
  }
}

Future<void> runBearerAdapterExample() async {
  final sessionOptions = const JwtSessionOptions(
    secret: 'replace-with-a-strong-secret',
    issuer: 'example-app',
    audience: <String>['example-api'],
    maxAge: Duration(minutes: 30),
  );
  final issued = issueAuthJwtToken(
    options: sessionOptions,
    claims: <String, dynamic>{'sub': 'user_99'},
  );

  final verifier = JwtVerifier(options: sessionOptions.toVerifierOptions());
  final context = _ExampleRequestContext();
  await verifyJwtBearerAuthorizationAndWriteAttributes<_ExampleRequestContext>(
    authorizationHeader: 'Bearer ${issued.token}',
    verifier: verifier,
    setAttribute: context.setAttribute,
    context: context,
    onVerified: (payload, ctx) {
      ctx.setAttribute('verified_sub', payload.subject);
    },
  );

  print('jwt attr subject = ${context.attributes[jwtSubjectAttribute]}');
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
