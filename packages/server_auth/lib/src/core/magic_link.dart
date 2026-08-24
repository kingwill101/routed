import 'dart:async';

import 'authentication_methods.dart';
import 'email_auth_backend.dart';
import 'plugin.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'users.dart' show authUserIsDisabled;

/// Rate-limit operation for requesting magic links.
const AuthRateLimitOperation authMagicLinkSendRateLimitOperation =
    AuthRateLimitOperation('magic_link', 'send');

/// Rate-limit operation for consuming magic links.
const AuthRateLimitOperation authMagicLinkVerifyRateLimitOperation =
    AuthRateLimitOperation('magic_link', 'verify');

/// Delivers a transient raw magic-link token after persistence commits.
typedef AuthMagicLinkSender<TContext> =
    FutureOr<void> Function(AuthMagicLinkDelivery<TContext> delivery);

/// The only public boundary that receives a raw magic-link token.
///
/// Delivery implementations must not log or persist [token]. The backend has
/// already committed a digest-only record when this callback runs.
final class AuthMagicLinkDelivery<TContext> {
  /// Creates the transient payload passed to [AuthMagicLinkSender].
  ///
  /// [token] is a raw one-time secret. Delivery must not log or persist it;
  /// the backend stores only its digest before this callback runs.
  const AuthMagicLinkDelivery({
    required this.context,
    required this.providerId,
    required this.email,
    required this.token,
    required this.callbackUrl,
    required this.expiresAt,
  });

  /// Application context for the delivery operation.
  final TContext context;

  /// Provider identifier used by the callback route.
  final String providerId;

  /// Canonical recipient email address.
  final String email;

  /// Raw one-time token for the message link.
  final String token;

  /// Callback URL to embed in the message.
  final String callbackUrl;

  /// UTC time after which [token] is invalid.
  final DateTime expiresAt;
}

/// Opt-in email magic-link server plugin.
///
/// The plugin contributes provider metadata and host-owned route contracts.
/// Durable token replacement and token/user consumption are delegated to the
/// required [AuthMagicLinkBackend]. Email delivery and host session/cookie
/// issuance happen after those backend commits and are intentionally not part
/// of the database transaction.
final class MagicLinkPlugin<TContext> extends AuthProvider
    implements
        AuthMagicLinkProvider,
        AuthServerPlugin<TContext>,
        AuthHostEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  /// Creates an email magic-link provider.
  ///
  /// [sendMagicLink] runs after the digest record is committed. [id] must be
  /// route-safe and [tokenExpiry] must be positive; [tokenGenerator] is useful
  /// for controlled tests and must return a non-empty token.
  MagicLinkPlugin({
    super.id = 'email',
    super.name = 'Email',
    required this.sendMagicLink,
    this.tokenExpiry = const Duration(minutes: 15),
    this.tokenGenerator,
  }) : super(type: AuthProviderType.email) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'must be a route-safe provider identifier',
      );
    }
    if (tokenExpiry <= Duration.zero) {
      throw ArgumentError.value(
        tokenExpiry,
        'tokenExpiry',
        'must be greater than zero',
      );
    }
  }

  /// Callback that delivers the raw token after backend persistence.
  final AuthMagicLinkSender<TContext> sendMagicLink;

  /// Lifetime assigned to newly issued links.
  @override
  final Duration tokenExpiry;

  /// Optional token source used instead of secure random generation.
  @override
  final String Function()? tokenGenerator;

  late AuthMagicLinkBackend _backend;
  late AuthUserStore _users;
  bool _configured = false;

  /// Configured backend for atomic issue and consume operations.
  AuthMagicLinkBackend get backend {
    _ensureConfigured();
    return _backend;
  }

  /// Namespace used to inventory email-link authentication methods.
  @override
  String get authenticationMethodNamespace => 'email:$id';

  /// Declares the authentication-method data contributed by this plugin.
  @override
  AuthServerPluginDataContract get dataContract => AuthServerPluginDataContract(
    authenticationMethodNamespace: authenticationMethodNamespace,
  );

  /// Store used by authentication-method inventory queries.
  @override
  Object get authenticationMethodStore {
    _ensureConfigured();
    return _users;
  }

  /// Authentication-method kinds exposed by this provider.
  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.emailLink,
  };

  /// Configures the required typed backend and user store.
  ///
  /// Throws [StateError] when the host store does not implement
  /// [AuthMagicLinkBackend].
  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final store = context.store;
    if (store is! AuthMagicLinkBackend) {
      throw StateError(
        'MagicLinkPlugin requires an AuthMagicLinkBackend. Durable adapters '
        'must implement the typed command boundary transactionally.',
      );
    }
    _backend = store as AuthMagicLinkBackend;
    _users = store.users;
    _configured = true;
  }

  /// Returns this plugin as the authentication-method inventory contributor.
  @override
  AuthAuthenticationMethodInventoryContributor authenticationMethodInventory(
    AuthStore store,
  ) => this;

  /// Lists the active email-link method for [userId], when eligible.
  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async {
    _ensureConfigured();
    final user = await _users.findById(userId);
    return AuthAuthenticationMethodSnapshot.complete([
      if (user?.email?.isNotEmpty == true && !authUserIsDisabled(user!))
        AuthAuthenticationMethod.emailLink(providerId: id, userId: userId),
    ]);
  }

  /// Delivers a verification token supplied by the host email flow.
  ///
  /// The callback receives the raw token only after backend persistence has
  /// committed it.
  @override
  Future<void> sendVerification(
    AuthContext context,
    AuthEmailRequest request,
  ) => Future.sync(
    () => sendMagicLink(
      AuthMagicLinkDelivery<TContext>(
        context: context as TContext,
        providerId: id,
        email: request.email,
        token: request.token,
        callbackUrl: request.callbackUrl,
        expiresAt: request.expiresAt,
      ),
    ),
  );

  /// Host-owned POST request and GET callback route contracts.
  ///
  /// The host must implement transport and session issuance. The POST route is
  /// repeatable and CSRF-protected; the GET callback is single-use.
  @override
  Iterable<AuthEndpointDescriptor<TContext>> get hostEndpoints => [
    _hostEndpoint(
      id: 'magicLink.$id.send',
      method: AuthOperationMethod.post,
      path: AuthRoutePath('/signin/$id'),
      operation: authMagicLinkSendRateLimitOperation,
      replaySafety: AuthMutationReplaySafety.repeatable,
    ),
    _hostEndpoint(
      id: 'magicLink.$id.verify',
      method: AuthOperationMethod.get,
      path: AuthRoutePath('/callback/$id'),
      operation: authMagicLinkVerifyRateLimitOperation,
      replaySafety: AuthMutationReplaySafety.singleUse,
    ),
  ];

  TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>
  _hostEndpoint({
    required String id,
    required AuthOperationMethod method,
    required AuthRoutePath path,
    required AuthRateLimitOperation operation,
    required AuthMutationReplaySafety replaySafety,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: method,
    path: path,
    semantics: AuthOperationSemantics.mutation(
      persistence: const AuthMutationPersistence.durable(
        atomicity: AuthMutationAtomicity.nonAtomic,
        reference: AuthPersistenceOperationReference(schemaId: 'magic_link'),
      ),
      replaySafety: replaySafety,
    ),
    requestCodec: _mapCodec,
    responseCodec: _objectCodec,
    authentication: AuthOperationAuthentication.none,
    originPolicy: AuthOperationOriginPolicy.browser,
    csrfPolicy: method == AuthOperationMethod.post
        ? AuthOperationCsrfPolicy.required
        : AuthOperationCsrfPolicy.none,
    rateLimitOperation: operation,
    handler: (invocation, request) => throw UnsupportedError(
      'Magic-link transport and session issuance are implemented by the host.',
    ),
  );

  /// Client operation descriptors derived from [hostEndpoints].
  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations =>
      hostEndpoints.map(
        (endpoint) => AuthClientOperationDescriptor(
          id: endpoint.id,
          method: endpoint.method,
          path: endpoint.path,
        ),
      );

  /// Rate-limit operations required by the contributed routes.
  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => const [
    authMagicLinkSendRateLimitOperation,
    authMagicLinkVerifyRateLimitOperation,
  ];

  /// Digest-only persistence schema and atomic operation declarations.
  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: 'magic_link',
      entities: [
        AuthEntityDescriptor(
          id: 'auth_magic_link',
          fields: [
            AuthFieldDescriptor(name: 'provider_id', kind: 'string'),
            AuthFieldDescriptor(name: 'email', kind: 'email'),
            AuthFieldDescriptor(name: 'token_hash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'issued_at', kind: 'datetime'),
            AuthFieldDescriptor(name: 'expires_at', kind: 'datetime'),
          ],
          uniqueConstraints: [
            ['provider_id', 'email'],
          ],
          indexes: [
            ['expires_at'],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'magicLink.issue',
          description: 'Replace one provider/email digest atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'magicLink.consumeUser',
          description:
              'Consume one digest and resolve a verified local user atomically.',
        ),
      ],
    ),
  ];

  void _ensureConfigured() {
    if (!_configured) throw StateError('MagicLinkPlugin is not configured');
  }

  static final AuthOperationCodec<Map<String, dynamic>> _mapCodec =
      AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => Map<String, dynamic>.from(value),
        encode: (value) => value,
      );

  static final AuthOperationCodec<Object?> _objectCodec =
      AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      );
}
