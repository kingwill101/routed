import 'package:property_testing/property_testing.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: '
    '${result.error ?? 'unknown failure'}; input=${result.failingInput}; '
    'seed=${result.seed}';

void main() {
  test(
    'hostile SCIM bearer values stay outside verification and errors',
    () async {
      final generator = Gen.frequency<String>([
        (6, Chaos.string(minLength: 0, maxLength: 160)),
        (
          4,
          Gen.oneOf<String>([
            '',
            'token',
            'token\r\nSet-Cookie: leaked=1',
            'token\u0000suffix',
            'token with spaces',
            'a' * 65,
            'valid-token_123',
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(generator, (candidate) async {
        final resolver = _RecordingResolver();
        final runtime = AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const <AuthProvider>[],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            plugins: <AuthServerPlugin<Object>>[
              ScimPlugin<Object>(
                store: const _NoopScimStore(),
                tokenResolver: resolver,
                options: AuthScimOptions(maximumBearerTokenLength: 64),
              ),
            ],
          ),
        );
        final fixture = AuthPluginEndpointFixture<Object>(
          endpoints: runtime.registry.endpoints,
          invocation: (_) =>
              AuthOperationInvocation<Object>(context: Object(), user: null),
        );
        final response = await fixture.respond(
          AuthTestHttpRequest(
            method: 'GET',
            uri: Uri.parse(
              'https://example.test/auth/scim/v2/ServiceProviderConfig',
            ),
            headers: <String, String>{'authorization': 'Bearer $candidate'},
            body: '',
          ),
        );

        expect(response.statusCode, 401);
        expect(response.body, isNot(contains('Set-Cookie')));
        expect(response.body, isNot(contains('leaked')));
        final valid =
            candidate.isNotEmpty &&
            candidate.length <= 64 &&
            RegExp(r'^[A-Za-z0-9\-._~+/]+=*$').hasMatch(candidate);
        expect(resolver.tokens, valid ? <String>[candidate] : isEmpty);
      }, PropertyConfig(numTests: 300, seed: 20260820));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test(
    'hostile SCIM filters either fail closed or stay strictly bounded',
    () async {
      final generator = Gen.frequency<String>([
        (7, Chaos.string(minLength: 0, maxLength: 700)),
        (
          3,
          Gen.oneOf<String>([
            'userName eq "user@example.test"',
            'emails.value eq "user@example.test"',
            'displayName co "user"',
            'userName eq "value\r\nheader"',
            'id eq "${'a' * 257}"',
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(generator, (source) {
        try {
          final filter = AuthScimUserFilter.parse(source);
          expect(filter.value, isNotEmpty);
          expect(filter.value.length, lessThanOrEqualTo(256));
          expect(
            filter.value.codeUnits,
            everyElement(allOf(greaterThanOrEqualTo(0x20), isNot(0x7f))),
          );
          expect(
            AuthScimUserFilterAttribute.values,
            contains(filter.attribute),
          );
        } on FormatException catch (error) {
          expect(error.toString(), isNot(contains(source)));
        }
      }, PropertyConfig(numTests: 500, seed: 20260821));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );
}

final class _RecordingResolver implements AuthScimBearerTokenResolver<Object> {
  final List<String> tokens = <String>[];

  @override
  AuthScimConnectionIdentity? resolve(
    AuthScimBearerTokenRequest<Object> request,
  ) {
    tokens.add(request.token);
    return null;
  }
}

final class _NoopScimStore implements AuthScimProvisioningStore {
  const _NoopScimStore();

  @override
  AuthScimUserPage listUsers(
    AuthScimProvisioningContext context,
    AuthScimListUsersQuery query,
  ) => AuthScimUserPage(resources: const <AuthScimUser>[], totalResults: 0);

  @override
  AuthScimUser? findUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) => null;

  @override
  AuthScimUser createUser(
    AuthScimProvisioningContext context,
    AuthScimUserData user,
  ) => throw const AuthScimConflictException();

  @override
  AuthScimUser? replaceUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimUserData user,
  ) => null;

  @override
  AuthScimUser? patchUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimPatchDocument patch,
  ) => null;

  @override
  AuthScimUser? tombstoneUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) => null;
}
