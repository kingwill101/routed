import 'dart:async';

import 'models.dart';
import 'plugin.dart';

const String authSamlPluginId = 'saml_sso';

enum AuthSamlNameIdFormat {
  persistent('urn:oasis:names:tc:SAML:2.0:nameid-format:persistent'),
  emailAddress('urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'),
  unspecified('urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified');

  const AuthSamlNameIdFormat(this.uri);
  final String uri;
}

/// Immutable application-owned SAML trust configuration.
final class AuthSamlConnection {
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

  final String providerId;
  final String idpEntityId;
  final Uri idpSsoUrl;
  final String idpSigningCertificate;
  final String spEntityId;
  final Uri assertionConsumerServiceUrl;
  final Set<String> verifiedDomains;
  final String? organizationSlug;
  final AuthSamlNameIdFormat nameIdFormat;
}

/// Typed, application-owned catalog for immutable SAML connections.
abstract interface class AuthSamlConnectionCatalog {
  FutureOr<AuthSamlConnection?> findByProviderId(String providerId);
  FutureOr<AuthSamlConnection?> findByVerifiedDomain(String domain);
  FutureOr<AuthSamlConnection?> findByOrganizationSlug(String slug);
}

sealed class AuthSamlConnectionSelector {
  const AuthSamlConnectionSelector();
  const factory AuthSamlConnectionSelector.providerId(String value) =
      AuthSamlProviderSelector;
  const factory AuthSamlConnectionSelector.verifiedDomain(String value) =
      AuthSamlVerifiedDomainSelector;
  const factory AuthSamlConnectionSelector.organizationSlug(String value) =
      AuthSamlOrganizationSelector;
}

final class AuthSamlProviderSelector extends AuthSamlConnectionSelector {
  const AuthSamlProviderSelector(this.value);
  final String value;
}

final class AuthSamlVerifiedDomainSelector extends AuthSamlConnectionSelector {
  const AuthSamlVerifiedDomainSelector(this.value);
  final String value;
}

final class AuthSamlOrganizationSelector extends AuthSamlConnectionSelector {
  const AuthSamlOrganizationSelector(this.value);
  final String value;
}

/// Stable external account key. Email attributes never participate in it.
final class AuthSamlAccountIdentity {
  const AuthSamlAccountIdentity({
    required this.providerId,
    required this.idpEntityId,
    required this.nameId,
    required this.nameIdFormat,
  });

  final String providerId;
  final String idpEntityId;
  final String nameId;
  final String nameIdFormat;

  String get stableKey =>
      '$providerId\u0000$idpEntityId\u0000$nameIdFormat\u0000$nameId';
}

final class AuthSamlIdentityInput<TContext> {
  const AuthSamlIdentityInput({
    required this.invocation,
    required this.connection,
    required this.identity,
    required this.attributes,
  });

  final AuthOperationInvocation<TContext> invocation;
  final AuthSamlConnection connection;
  final AuthSamlAccountIdentity identity;
  final Map<String, List<String>> attributes;
}

/// Application policy seam shared by SAML sign-in and future SCIM mapping.
///
/// Implementations may resolve or provision a user from the stable SAML
/// account key. They must not link by an unverified email attribute.
abstract interface class AuthSamlIdentityResolver<TContext> {
  FutureOr<AuthUser> resolveOrProvision(AuthSamlIdentityInput<TContext> input);
}

final class AuthSamlVerificationInput {
  const AuthSamlVerificationInput({
    required this.xml,
    required this.connection,
    required this.responseId,
    required this.assertionId,
  });

  final String xml;
  final AuthSamlConnection connection;
  final String responseId;
  final String assertionId;
}

/// Proof returned by an application-owned XMLDSig implementation.
///
/// The verifier must cryptographically validate the pinned IdP certificate and
/// return the exact IDs referenced by the validated signature. Returning IDs
/// discovered elsewhere in the document violates this contract.
final class AuthSamlSignatureProof {
  const AuthSamlSignatureProof({
    required this.signedResponseId,
    required this.signedAssertionId,
    required this.signatureAlgorithm,
    required this.digestAlgorithm,
    required this.canonicalizationAlgorithm,
  });

  final String? signedResponseId;
  final String? signedAssertionId;
  final String signatureAlgorithm;
  final String digestAlgorithm;
  final String canonicalizationAlgorithm;
}

abstract interface class AuthSamlAssertionVerifier {
  FutureOr<AuthSamlSignatureProof> verify(AuthSamlVerificationInput input);
}

sealed class AuthSamlIdpInitiatedPolicy {
  const AuthSamlIdpInitiatedPolicy();
  const factory AuthSamlIdpInitiatedPolicy.disabled() =
      AuthSamlIdpInitiatedDisabled;
  const factory AuthSamlIdpInitiatedPolicy.fixedCallback(Uri callback) =
      AuthSamlIdpInitiatedFixedCallback;
}

final class AuthSamlIdpInitiatedDisabled extends AuthSamlIdpInitiatedPolicy {
  const AuthSamlIdpInitiatedDisabled();
}

final class AuthSamlIdpInitiatedFixedCallback
    extends AuthSamlIdpInitiatedPolicy {
  const AuthSamlIdpInitiatedFixedCallback(this.callback);
  final Uri callback;
}

final class AuthSamlRedirectPolicy {
  AuthSamlRedirectPolicy({
    this.allowRelative = true,
    Set<Uri> trustedOrigins = const <Uri>{},
  }) : trustedOrigins = Set<Uri>.unmodifiable(trustedOrigins.map(_originOnly));

  const AuthSamlRedirectPolicy.relativeOnly()
    : allowRelative = true,
      trustedOrigins = const <Uri>{};

  final bool allowRelative;
  final Set<Uri> trustedOrigins;

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

String normalizeAuthSamlDomain(String value) => _normalizeDomain(value);

String _normalizeDomain(String value) {
  final domain = value.trim().toLowerCase();
  if (domain.isEmpty ||
      domain.length > 253 ||
      domain.contains(RegExp(r'[^a-z0-9.-]')) ||
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
      normalized.contains(RegExp(r'[^A-Za-z0-9._-]'))) {
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
