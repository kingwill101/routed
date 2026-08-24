import 'dart:async';

import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/plugin.dart';

/// Stable identifier for the SAML server plugin and persistence schema.
const String authSamlPluginId = 'saml_sso';

/// NameID formats accepted by the SAML connection policy.
enum AuthSamlNameIdFormat {
  /// A persistent identifier assigned by the identity provider.
  persistent('urn:oasis:names:tc:SAML:2.0:nameid-format:persistent'),

  /// An identifier containing an email address.
  emailAddress('urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'),

  /// An identifier whose format is not otherwise specified.
  unspecified('urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified');

  /// Creates a format backed by its SAML URI.
  const AuthSamlNameIdFormat(this.uri);

  /// The SAML URI identifying this format.
  final String uri;
}

/// Immutable application-owned SAML trust configuration.
final class AuthSamlConnection {
  /// Creates a validated connection configuration.
  ///
  /// The identity-provider certificate is pinned in [idpSigningCertificate].
  AuthSamlConnection({
    required this.providerId,
    required this.idpEntityId,
    required this.idpSsoUrl,
    required this.idpSigningCertificate,
    required this.spEntityId,
    required this.assertionConsumerServiceUrl,
    Set<String> verifiedDomains = const <String>{},
    this.organizationSlug,
    this.nameIdFormat = AuthSamlNameIdFormat.persistent,
  }) : verifiedDomains = Set<String>.unmodifiable(
         verifiedDomains.map(_normalizeDomain),
       ) {
    _requireProviderId(providerId);
    _requireIdentifier(idpEntityId, 'idpEntityId');
    _requireIdentifier(spEntityId, 'spEntityId');
    _requireHttps(idpSsoUrl, 'idpSsoUrl');
    _requireHttps(assertionConsumerServiceUrl, 'assertionConsumerServiceUrl');
    if (idpSigningCertificate.trim().isEmpty ||
        idpSigningCertificate.length > 32768) {
      throw ArgumentError.value(
        '<redacted>',
        'idpSigningCertificate',
        'must contain one bounded pinned certificate',
      );
    }
    final slug = organizationSlug?.trim() ?? '';
    if (organizationSlug != null && slug.isEmpty) {
      throw ArgumentError.value(organizationSlug, 'organizationSlug');
    }
  }

  /// Path-safe identifier used to select this connection.
  final String providerId;

  /// Entity identifier asserted by the identity provider.
  final String idpEntityId;

  /// HTTPS endpoint that receives SAML authentication requests.
  final Uri idpSsoUrl;

  /// PEM-encoded certificate pinned for response signature verification.
  final String idpSigningCertificate;

  /// Service-provider entity identifier advertised to the identity provider.
  final String spEntityId;

  /// HTTPS endpoint that receives SAML assertions.
  final Uri assertionConsumerServiceUrl;

  /// Lowercase DNS domains allowed to select this connection.
  final Set<String> verifiedDomains;

  /// Optional organization slug associated with this connection.
  final String? organizationSlug;

  /// NameID format required from assertions for this connection.
  final AuthSamlNameIdFormat nameIdFormat;
}

/// Typed, application-owned catalog for immutable SAML connections.
abstract interface class AuthSamlConnectionCatalog {
  /// Finds a connection by its provider identifier.
  FutureOr<AuthSamlConnection?> findByProviderId(String providerId);

  /// Finds a connection containing [domain] in [AuthSamlConnection.verifiedDomains].
  FutureOr<AuthSamlConnection?> findByVerifiedDomain(String domain);

  /// Finds a connection by its organization slug.
  FutureOr<AuthSamlConnection?> findByOrganizationSlug(String slug);
}

/// Selects one lookup key for a SAML connection.
sealed class AuthSamlConnectionSelector {
  /// Creates a selector base value.
  const AuthSamlConnectionSelector();

  /// Selects a connection by provider identifier.
  const factory AuthSamlConnectionSelector.providerId(String value) =
      AuthSamlProviderSelector;

  /// Selects a connection by verified domain.
  const factory AuthSamlConnectionSelector.verifiedDomain(String value) =
      AuthSamlVerifiedDomainSelector;

  /// Selects a connection by organization slug.
  const factory AuthSamlConnectionSelector.organizationSlug(String value) =
      AuthSamlOrganizationSelector;
}

/// A connection selector containing a provider identifier.
final class AuthSamlProviderSelector extends AuthSamlConnectionSelector {
  /// Creates a provider-identifier selector.
  const AuthSamlProviderSelector(this.value);

  /// The provider identifier to look up.
  final String value;
}

/// A connection selector containing a verified domain.
final class AuthSamlVerifiedDomainSelector extends AuthSamlConnectionSelector {
  /// Creates a verified-domain selector.
  const AuthSamlVerifiedDomainSelector(this.value);

  /// The domain to look up.
  final String value;
}

/// A connection selector containing an organization slug.
final class AuthSamlOrganizationSelector extends AuthSamlConnectionSelector {
  /// Creates an organization-slug selector.
  const AuthSamlOrganizationSelector(this.value);

  /// The organization slug to look up.
  final String value;
}

/// Stable external account key. Email attributes never participate in it.
final class AuthSamlAccountIdentity {
  /// Creates the stable identity extracted from a validated assertion.
  const AuthSamlAccountIdentity({
    required this.providerId,
    required this.idpEntityId,
    required this.nameId,
    required this.nameIdFormat,
  });

  /// The SAML provider identifier.
  final String providerId;

  /// The identity provider entity identifier.
  final String idpEntityId;

  /// The provider-issued NameID value.
  final String nameId;

  /// The provider-issued NameID format URI.
  final String nameIdFormat;

  /// A stable key suitable for account linking and provisioning.
  String get stableKey =>
      '$providerId\u0000$idpEntityId\u0000$nameIdFormat\u0000$nameId';
}

/// Inputs supplied to an application-owned SAML identity resolver.
final class AuthSamlIdentityInput<TContext> {
  /// Creates resolver input for one SAML authentication operation.
  const AuthSamlIdentityInput({
    required this.invocation,
    required this.connection,
    required this.identity,
    required this.attributes,
  });

  /// The surrounding authentication operation invocation.
  final AuthOperationInvocation<TContext> invocation;

  /// The validated SAML connection used for the assertion.
  final AuthSamlConnection connection;

  /// The stable provider identity extracted from the assertion.
  final AuthSamlAccountIdentity identity;

  /// SAML attributes grouped by attribute name.
  final Map<String, List<String>> attributes;
}

/// Application policy seam shared by SAML sign-in and future SCIM mapping.
///
/// Implementations may resolve or provision a user from the stable SAML
/// account key. They must not link by an unverified email attribute.
abstract interface class AuthSamlIdentityResolver<TContext> {
  /// Resolves an existing user or provisions a new one for [input].
  FutureOr<AuthUser> resolveOrProvision(AuthSamlIdentityInput<TContext> input);
}

/// Inputs supplied to an application-owned SAML assertion verifier.
final class AuthSamlVerificationInput {
  /// Creates verifier input for one parsed SAML response.
  const AuthSamlVerificationInput({
    required this.xml,
    required this.connection,
    required this.responseId,
    required this.assertionId,
  });

  /// The decoded SAML response XML.
  final String xml;

  /// The trusted connection whose certificate and audience are enforced.
  final AuthSamlConnection connection;

  /// The response identifier expected by the caller.
  final String responseId;

  /// The assertion identifier expected by the caller.
  final String assertionId;
}

/// Proof returned by an application-owned XMLDSig implementation.
///
/// The verifier must cryptographically validate the pinned IdP certificate and
/// return the exact IDs referenced by the validated signature. Returning IDs
/// discovered elsewhere in the document violates this contract.
final class AuthSamlSignatureProof {
  /// Creates proof describing the signed SAML object and algorithms.
  const AuthSamlSignatureProof({
    required this.signedResponseId,
    required this.signedAssertionId,
    required this.signatureAlgorithm,
    required this.digestAlgorithm,
    required this.canonicalizationAlgorithm,
  });

  /// The response ID referenced by a validated signature, if any.
  final String? signedResponseId;

  /// The assertion ID referenced by a validated signature, if any.
  final String? signedAssertionId;

  /// The XMLDSig signature algorithm URI.
  final String signatureAlgorithm;

  /// The XMLDSig digest algorithm URI.
  final String digestAlgorithm;

  /// The canonicalization algorithm URI.
  final String canonicalizationAlgorithm;
}

/// Verifies parsed SAML responses against an application-owned trust policy.
abstract interface class AuthSamlAssertionVerifier {
  /// Verifies [input] and returns the exact signed-reference proof.
  FutureOr<AuthSamlSignatureProof> verify(AuthSamlVerificationInput input);
}

/// Policy controlling whether IdP-initiated SAML responses are accepted.
sealed class AuthSamlIdpInitiatedPolicy {
  /// Creates a policy base value.
  const AuthSamlIdpInitiatedPolicy();

  /// Disables IdP-initiated responses.
  const factory AuthSamlIdpInitiatedPolicy.disabled() =
      AuthSamlIdpInitiatedDisabled;

  /// Accepts IdP-initiated responses only for [callback].
  const factory AuthSamlIdpInitiatedPolicy.fixedCallback(Uri callback) =
      AuthSamlIdpInitiatedFixedCallback;
}

/// Policy value that disables IdP-initiated SAML responses.
final class AuthSamlIdpInitiatedDisabled extends AuthSamlIdpInitiatedPolicy {
  /// Creates the disabled policy.
  const AuthSamlIdpInitiatedDisabled();
}

/// Policy value that sends IdP-initiated responses to one callback.
final class AuthSamlIdpInitiatedFixedCallback
    extends AuthSamlIdpInitiatedPolicy {
  /// Creates a policy using [callback].
  const AuthSamlIdpInitiatedFixedCallback(this.callback);

  /// The fixed callback URI.
  final Uri callback;
}

/// Allow-list policy for SAML callback URIs.
final class AuthSamlRedirectPolicy {
  /// Creates a policy allowing relative callbacks and [trustedOrigins].
  AuthSamlRedirectPolicy({
    this.allowRelative = true,
    Set<Uri> trustedOrigins = const <Uri>{},
  }) : trustedOrigins = Set<Uri>.unmodifiable(trustedOrigins.map(_originOnly));

  /// Creates a policy that accepts only root-relative callback paths.
  const AuthSamlRedirectPolicy.relativeOnly()
    : allowRelative = true,
      trustedOrigins = const <Uri>{};

  /// Whether root-relative callback paths are accepted.
  final bool allowRelative;

  /// Trusted URI origins allowed for absolute callbacks.
  final Set<Uri> trustedOrigins;

  /// Validates [candidate], falling back to [fallback] when it is blank.
  ///
  /// Throws a [FormatException] when the candidate is not allowed by this
  /// policy.
  Uri project(String? candidate, {required Uri fallback}) {
    final value = candidate?.trim() ?? '';
    if (value.isEmpty) return _validateFixed(fallback);
    final uri = Uri.tryParse(value);
    if (uri == null || uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw const FormatException('invalid_saml_callback');
    }
    if (!uri.hasScheme && !uri.hasAuthority) {
      if (!allowRelative ||
          !uri.path.startsWith('/') ||
          uri.path.startsWith('//')) {
        throw const FormatException('invalid_saml_callback');
      }
      return uri;
    }
    if (!trustedOrigins.contains(_originOnly(uri))) {
      throw const FormatException('invalid_saml_callback');
    }
    return uri;
  }

  Uri _validateFixed(Uri callback) {
    if (!callback.hasScheme && allowRelative && callback.path.startsWith('/')) {
      return callback;
    }
    if (trustedOrigins.contains(_originOnly(callback))) {
      return callback;
    }
    throw const FormatException('invalid_saml_callback');
  }
}

/// Normalizes and validates a SAML verified domain.
///
/// Throws an [ArgumentError] when [value] is not a bounded DNS domain.
String normalizeAuthSamlDomain(String value) => _normalizeDomain(value);

String _normalizeDomain(String value) {
  final domain = value.trim().toLowerCase();
  if (domain.isEmpty ||
      domain.length > 253 ||
      domain.contains(RegExp('[^a-z0-9.-]')) ||
      domain.startsWith('.') ||
      domain.endsWith('.') ||
      domain.contains('..')) {
    throw ArgumentError.value(value, 'domain', 'must be a DNS domain');
  }
  return domain;
}

void _requireIdentifier(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 512 ||
      normalized.contains(RegExp(r'[\x00-\x1f]'))) {
    throw ArgumentError.value(value, name, 'must be a bounded identifier');
  }
}

void _requireProviderId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 128 ||
      normalized.contains(RegExp('[^A-Za-z0-9._-]'))) {
    throw ArgumentError.value(
      value,
      'providerId',
      'must be a path-safe identifier',
    );
  }
}

void _requireHttps(Uri value, String name) {
  if (value.scheme != 'https' ||
      !value.hasAuthority ||
      value.userInfo.isNotEmpty ||
      value.hasFragment) {
    throw ArgumentError.value(value, name, 'must be an absolute HTTPS URI');
  }
}

Uri _originOnly(Uri value) {
  if (!value.hasScheme || !value.hasAuthority || value.userInfo.isNotEmpty) {
    throw ArgumentError.value(value, 'origin', 'must be absolute');
  }
  return Uri(
    scheme: value.scheme.toLowerCase(),
    host: value.host.toLowerCase(),
    port: value.hasPort ? value.port : null,
  );
}
