import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('AuthPluginConformanceSuite', () {
    test('publishes stable independently runnable cases', () async {
      final suite = _suite(_validPlugin());
      const expectedIds = <String>[
        'composition.identifiers',
        'endpoints.identifiers',
        'endpoints.typed-contracts',
        'rate-limits.references',
        'clients.public-endpoints',
        'clients.installed-contracts',
        'endpoints.mutation-protection',
        'endpoints.operation-semantics',
      ];

      expect(suite.cases.map((value) => value.id), expectedIds);
      for (final conformanceCase in suite.cases) {
        final result = await conformanceCase.run();
        expect(result.isPassed, isTrue);
      }
    });

    test('conforms representative built-in plugin topology', () async {
      final store = InMemoryAuthStore();
      final webAuthnProvider = WebAuthnProvider(
        getUserInfo: (_, _, _) => null,
        getRelyingParty: (_, _) => const WebAuthnRelyingParty(
          id: 'example.com',
          name: 'Example',
          origin: 'https://example.com',
        ),
      );
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: <AuthProvider>[webAuthnProvider],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: <AuthServerPlugin<Object>>[
            PhoneNumberPlugin<Object>(
              store: InMemoryAuthPhoneNumberStore(),
              sendCode: (_) {},
              codeHashKey: '0123456789abcdef0123456789abcdef',
            ),
            EmailOtpPlugin<Object>(
              sendCode: (_) {},
              rateLimitHashKey: 'conformance-email-key-not-for-production-use',
            ),
            WebAuthnPlugin<Object>(provider: webAuthnProvider),
          ],
        ),
      );
      final suite = AuthPluginConformanceSuite<Object>.fromRuntime(runtime);

      for (final conformanceCase in suite.cases) {
        final result = await conformanceCase.run();
        expect(result.isPassed, isTrue, reason: conformanceCase.id);
      }
    });

    test('filters by stable case IDs and rejects unknown filters', () {
      final suite = _suite(_validPlugin());

      expect(
        suite
            .filtered(
              include: const <String>{
                'endpoints.identifiers',
                'clients.public-endpoints',
              },
              exclude: const <String>{'endpoints.identifiers'},
            )
            .map((value) => value.id),
        const <String>['clients.public-endpoints'],
      );
      expect(
        () => suite.filtered(include: const <String>{'endpoints.typo'}),
        throwsArgumentError,
      );
    });

    test('rejects unstable endpoint and client operation IDs', () async {
      final endpoint = _endpoint(
        id: 'unstable endpoint',
        method: AuthOperationMethod.get,
        path: '/unstable',
      );
      final suite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[endpoint],
          clientOperations: const <AuthClientOperationDescriptor>[
            AuthClientOperationDescriptor(
              id: 'unstable client',
              method: AuthOperationMethod.get,
              path: '/unstable',
            ),
          ],
        ),
      );

      await _expectCaseFailure(suite, 'endpoints.identifiers');
      await _expectCaseFailure(suite, 'clients.public-endpoints');
    });

    test('rejects non-canonical method and path keys', () async {
      final endpoint = _endpoint(
        id: 'sample.path',
        method: AuthOperationMethod.get,
        path: 'sample/path/',
      );
      final suite = _suite(
        _FixturePlugin(endpoints: <AuthEndpointDescriptor<Object>>[endpoint]),
      );

      await _expectCaseFailure(suite, 'endpoints.identifiers');
    });

    test('requires typed JSON-compatible endpoint contracts', () async {
      final untypedSuite = _suite(
        _FixturePlugin(
          endpoints: const <AuthEndpointDescriptor<Object>>[_UntypedEndpoint()],
        ),
      );
      await _expectCaseFailure(untypedSuite, 'endpoints.typed-contracts');

      final malformedSuite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.malformed',
              method: AuthOperationMethod.get,
              path: '/sample/malformed',
              requestSchema: <String, Object?>{'properties': Object()},
            ),
          ],
        ),
      );
      await _expectCaseFailure(malformedSuite, 'endpoints.typed-contracts');
    });

    test('matches rate-limit declarations and endpoint references', () async {
      const missing = AuthRateLimitOperation('sample', 'missing');
      final undeclaredSuite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.verify',
              method: AuthOperationMethod.post,
              path: '/sample/verify',
              rateLimitOperation: missing,
            ),
          ],
        ),
      );
      await _expectCaseFailure(undeclaredSuite, 'rate-limits.references');

      final unusedSuite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.status',
              method: AuthOperationMethod.get,
              path: '/sample/status',
            ),
          ],
          rateLimitOperations: const <AuthRateLimitOperation>[missing],
        ),
      );
      await _expectCaseFailure(unusedSuite, 'rate-limits.references');
    });

    test('requires client operations to match public endpoints', () async {
      final endpoint = _endpoint(
        id: 'sample.status',
        method: AuthOperationMethod.get,
        path: '/sample/status',
      );
      final suite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[endpoint],
          clientOperations: const <AuthClientOperationDescriptor>[
            AuthClientOperationDescriptor(
              id: 'sample.status',
              method: AuthOperationMethod.post,
              path: '/sample/status',
            ),
          ],
        ),
      );

      await _expectCaseFailure(suite, 'clients.public-endpoints');
    });

    test(
      'requires reverse client coverage or a documented exception',
      () async {
        final endpoint = _endpoint(
          id: 'sample.discovery',
          method: AuthOperationMethod.get,
          path: '/.well-known/sample',
        );
        final plugin = _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[endpoint],
        );

        await _expectCaseFailure(_suite(plugin), 'clients.public-endpoints');

        final excepted = _suite(
          plugin,
          publicEndpointClientExceptions: const <String, String>{
            'sample.discovery':
                'Protocol discovery is consumed by generic HTTP clients.',
          },
        );
        final result = await _case(excepted, 'clients.public-endpoints').run();
        expect(result.isPassed, isTrue);
      },
    );

    test('allows rate-limited anonymous verification without CSRF', () async {
      const operation = AuthRateLimitOperation('sample', 'verify');
      final suite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.verify',
              method: AuthOperationMethod.post,
              path: '/sample/verify',
              originPolicy: AuthOperationOriginPolicy.browser,
              rateLimitOperation: operation,
            ),
          ],
          rateLimitOperations: const <AuthRateLimitOperation>[operation],
        ),
      );

      final result = await _case(suite, 'endpoints.mutation-protection').run();
      expect(result.isPassed, isTrue);
    });

    test('rejects inconsistent browser mutation protection', () async {
      const operation = AuthRateLimitOperation('sample', 'update');
      final suite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.update',
              method: AuthOperationMethod.post,
              path: '/sample/update',
              authentication: AuthOperationAuthentication.session,
              originPolicy: AuthOperationOriginPolicy.browser,
              csrfPolicy: AuthOperationCsrfPolicy.none,
              rateLimitOperation: operation,
            ),
          ],
          rateLimitOperations: const <AuthRateLimitOperation>[operation],
        ),
      );

      await _expectCaseFailure(suite, 'endpoints.mutation-protection');
    });

    test('rejects missing and invalid mutation semantics', () async {
      final missing = _suite(
        const _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[],
          hostEndpoints: <AuthEndpointDescriptor<Object>>[
            _MissingSemanticsEndpoint(),
          ],
        ),
      );
      await _expectCaseFailure(missing, 'endpoints.operation-semantics');

      final missingAtomicReference = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.atomic',
              method: AuthOperationMethod.post,
              path: '/sample/atomic',
              semantics: const AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.durable(
                  atomicity: AuthMutationAtomicity.atomic,
                ),
                replaySafety: AuthMutationReplaySafety.singleUse,
              ),
            ),
          ],
        ),
      );
      await _expectCaseFailure(
        missingAtomicReference,
        'endpoints.operation-semantics',
      );
    });

    test('rejects invalid schema and atomic-operation references', () async {
      final undeclaredSchema = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.persist',
              method: AuthOperationMethod.post,
              path: '/sample/persist',
              semantics: const AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.durable(
                  atomicity: AuthMutationAtomicity.nonAtomic,
                  reference: AuthPersistenceOperationReference(
                    schemaId: 'missing',
                  ),
                ),
                replaySafety: AuthMutationReplaySafety.idempotent,
              ),
            ),
          ],
        ),
      );
      await _expectCaseFailure(
        undeclaredSchema,
        'endpoints.operation-semantics',
      );

      final undeclaredAtomicOperation = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.atomic',
              method: AuthOperationMethod.post,
              path: '/sample/atomic',
              semantics: const AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.durable(
                  atomicity: AuthMutationAtomicity.atomic,
                  reference: AuthPersistenceOperationReference(
                    schemaId: 'sample',
                    atomicOperationId: 'missing',
                  ),
                ),
                replaySafety: AuthMutationReplaySafety.singleUse,
              ),
            ),
          ],
          persistenceSchemas: const <AuthPersistenceSchema>[
            AuthPersistenceSchema(
              id: 'sample',
              entities: <AuthEntityDescriptor>[],
            ),
          ],
        ),
      );
      await _expectCaseFailure(
        undeclaredAtomicOperation,
        'endpoints.operation-semantics',
      );
    });

    test('rejects unsafe anonymous browser mutations', () async {
      const operation = AuthRateLimitOperation('sample', 'unsafe');
      final suite = _suite(
        _FixturePlugin(
          endpoints: <AuthEndpointDescriptor<Object>>[
            _endpoint(
              id: 'sample.unsafe',
              method: AuthOperationMethod.post,
              path: '/sample/unsafe',
              originPolicy: AuthOperationOriginPolicy.browser,
              rateLimitOperation: operation,
              semantics: const AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.session(),
                replaySafety: AuthMutationReplaySafety.unguarded,
              ),
            ),
          ],
          rateLimitOperations: const <AuthRateLimitOperation>[operation],
        ),
      );

      await _expectCaseFailure(suite, 'endpoints.operation-semantics');
    });

    test(
      'requires anonymous non-browser mutations to be rate limited',
      () async {
        final suite = _suite(
          _FixturePlugin(
            endpoints: <AuthEndpointDescriptor<Object>>[
              _endpoint(
                id: 'sample.verify',
                method: AuthOperationMethod.post,
                path: '/sample/verify',
              ),
            ],
          ),
        );

        await _expectCaseFailure(suite, 'endpoints.mutation-protection');
      },
    );
  });
}

AuthPluginConformanceSuite<Object> _suite(
  _FixturePlugin plugin, {
  Map<String, String> publicEndpointClientExceptions = const <String, String>{},
}) {
  final store = InMemoryAuthStore();
  final runtime = AuthRuntime<Object>(
    options: AuthOptions<Object>(
      providers: const <AuthProvider>[],
      store: store,
      storeMode: AuthStoreMode.ephemeral,
      plugins: <AuthServerPlugin<Object>>[plugin],
    ),
  );
  return AuthPluginConformanceSuite<Object>.fromRuntime(
    runtime,
    publicEndpointClientExceptions: publicEndpointClientExceptions,
  );
}

_FixturePlugin _validPlugin() {
  const verifyRateLimit = AuthRateLimitOperation('sample', 'verify');
  const updateRateLimit = AuthRateLimitOperation('sample', 'update');
  final endpoints = <AuthEndpointDescriptor<Object>>[
    _endpoint(
      id: 'sample.status',
      method: AuthOperationMethod.get,
      path: '/sample/status',
    ),
    _endpoint(
      id: 'sample.verify',
      method: AuthOperationMethod.post,
      path: '/sample/verify',
      rateLimitOperation: verifyRateLimit,
    ),
    _endpoint(
      id: 'sample.update',
      method: AuthOperationMethod.post,
      path: '/sample/update',
      authentication: AuthOperationAuthentication.session,
      originPolicy: AuthOperationOriginPolicy.browser,
      csrfPolicy: AuthOperationCsrfPolicy.required,
      rateLimitOperation: updateRateLimit,
    ),
  ];
  return _FixturePlugin(
    endpoints: endpoints,
    clientOperations: endpoints
        .map(
          (endpoint) => AuthClientOperationDescriptor(
            id: endpoint.id,
            method: endpoint.method,
            path: endpoint.path,
          ),
        )
        .toList(growable: false),
    rateLimitOperations: const <AuthRateLimitOperation>[
      verifyRateLimit,
      updateRateLimit,
    ],
  );
}

TypedAuthEndpointDescriptor<Object, Map<String, dynamic>, Object?> _endpoint({
  required String id,
  required AuthOperationMethod method,
  required String path,
  AuthOperationAuthentication authentication = AuthOperationAuthentication.none,
  AuthOperationOriginPolicy originPolicy = AuthOperationOriginPolicy.none,
  AuthOperationCsrfPolicy csrfPolicy = AuthOperationCsrfPolicy.none,
  AuthRateLimitOperation? rateLimitOperation,
  AuthOperationSemantics? semantics,
  Map<String, Object?> requestSchema = const <String, Object?>{
    'type': 'object',
  },
}) {
  return TypedAuthEndpointDescriptor<Object, Map<String, dynamic>, Object?>(
    id: id,
    method: method,
    path: path,
    semantics:
        semantics ??
        (method == AuthOperationMethod.get
            ? const AuthOperationSemantics.readOnly()
            : const AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.boundedEphemeral(),
                replaySafety: AuthMutationReplaySafety.repeatable,
              )),
    requestCodec: AuthOperationCodec<Map<String, dynamic>>(
      decode: (value) => value,
      encode: (value) => value,
      schema: requestSchema,
    ),
    responseCodec: AuthOperationCodec<Object?>(
      decode: (value) => value,
      encode: (value) => value,
      schema: const <String, Object?>{'type': 'object'},
    ),
    authentication: authentication,
    originPolicy: originPolicy,
    csrfPolicy: csrfPolicy,
    rateLimitOperation: rateLimitOperation,
    handler: (invocation, request) => const <String, Object?>{'ok': true},
  );
}

Future<void> _expectCaseFailure(
  AuthPluginConformanceSuite<Object> suite,
  String id,
) async {
  await expectLater(
    _case(suite, id).run(),
    throwsA(
      isA<AuthPluginConformanceFailure>().having(
        (failure) => failure.caseId,
        'caseId',
        id,
      ),
    ),
  );
}

AuthPluginConformanceCase _case(
  AuthPluginConformanceSuite<Object> suite,
  String id,
) => suite.cases.singleWhere((value) => value.id == id);

final class _FixturePlugin
    implements
        AuthServerPlugin<Object>,
        AuthEndpointContributor<Object>,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthPersistenceContributor,
        AuthHostEndpointContributor<Object> {
  const _FixturePlugin({
    required this.endpoints,
    this.clientOperations = const <AuthClientOperationDescriptor>[],
    this.rateLimitOperations = const <AuthRateLimitOperation>[],
    this.persistenceSchemas = const <AuthPersistenceSchema>[],
    this.hostEndpoints = const <AuthEndpointDescriptor<Object>>[],
  });

  @override
  String get id => 'sample';

  @override
  final Iterable<AuthEndpointDescriptor<Object>> endpoints;

  @override
  final Iterable<AuthClientOperationDescriptor> clientOperations;

  @override
  final Iterable<AuthRateLimitOperation> rateLimitOperations;

  @override
  final Iterable<AuthPersistenceSchema> persistenceSchemas;

  @override
  final Iterable<AuthEndpointDescriptor<Object>> hostEndpoints;

  @override
  void configure(AuthServerPluginContext<Object> context) {}
}

final class _UntypedEndpoint implements AuthEndpointDescriptor<Object> {
  const _UntypedEndpoint();

  @override
  String get id => 'sample.untyped';

  @override
  AuthOperationMethod get method => AuthOperationMethod.get;

  @override
  String get path => '/sample/untyped';

  @override
  AuthOperationSemantics get semantics =>
      const AuthOperationSemantics.readOnly();

  @override
  AuthOperationAuthentication get authentication =>
      AuthOperationAuthentication.none;

  @override
  AuthOperationOriginPolicy get originPolicy => AuthOperationOriginPolicy.none;

  @override
  AuthOperationCsrfPolicy get csrfPolicy => AuthOperationCsrfPolicy.none;

  @override
  AuthRateLimitOperation? get rateLimitOperation => null;

  @override
  bool get serverOnly => false;

  @override
  Object? invoke(
    AuthOperationInvocation<Object> invocation,
    Map<String, dynamic> input,
  ) => null;
}

final class _MissingSemanticsEndpoint
    implements AuthEndpointDescriptor<Object>, AuthEndpointContractDescriptor {
  const _MissingSemanticsEndpoint();

  @override
  String get id => 'sample.missingSemantics';
  @override
  AuthOperationMethod get method => AuthOperationMethod.post;
  @override
  String get path => '/sample/missing-semantics';
  @override
  AuthOperationSemantics get semantics =>
      throw StateError('Mutation semantics were not declared.');
  @override
  AuthOperationAuthentication get authentication =>
      AuthOperationAuthentication.none;
  @override
  AuthOperationOriginPolicy get originPolicy => AuthOperationOriginPolicy.none;
  @override
  AuthOperationCsrfPolicy get csrfPolicy => AuthOperationCsrfPolicy.none;
  @override
  AuthRateLimitOperation? get rateLimitOperation => null;
  @override
  bool get serverOnly => true;
  @override
  AuthOperationContract get requestCodec => _missingSemanticsCodec;
  @override
  AuthOperationContract get responseCodec => _missingSemanticsCodec;
  @override
  Object? invoke(
    AuthOperationInvocation<Object> invocation,
    Map<String, dynamic> input,
  ) => const <String, Object?>{};
}

final AuthOperationCodec<Map<String, dynamic>> _missingSemanticsCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: (value) => value,
      encode: (value) => value,
    );
