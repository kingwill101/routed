import 'dart:convert';

import 'client.dart';
import 'plugin.dart';
import 'saml.dart';
import 'saml_models.dart';

/// Adds the opt-in SAML client operations to an [AuthClient].
final class AuthSamlClientPlugin implements AuthClientPlugin<AuthSamlClient> {
  /// Creates a SAML client plugin.
  const AuthSamlClientPlugin();

  /// The stable identifier used to install this plugin.
  @override
  String get id => authSamlPluginId;

  /// Installs a client backed by the transport in [context].
  @override
  AuthSamlClient install(AuthClientPluginContext context) =>
      AuthSamlClient(context.transport);
}

/// Selects a SAML connection for a sign-in request.
final class AuthSamlSignInRequest {
  /// Creates a request using exactly one of the supported connection selectors.
  const AuthSamlSignInRequest({
    this.providerId,
    this.verifiedDomain,
    this.organizationSlug,
    this.callbackUrl,
  });

  /// An explicit SAML provider identifier.
  final String? providerId;

  /// A verified email domain used to locate a SAML connection.
  final String? verifiedDomain;

  /// An organization slug used to locate a SAML connection.
  final String? organizationSlug;

  /// The application callback to use after authentication.
  final Uri? callbackUrl;

  /// Encodes the request for the SAML sign-in endpoint.
  Map<String, dynamic> toJson() => {
    if (providerId != null) 'providerId': providerId,
    if (verifiedDomain != null) 'domain': verifiedDomain,
    if (organizationSlug != null) 'organizationSlug': organizationSlug,
    if (callbackUrl != null) 'callbackUrl': callbackUrl.toString(),
  };
}

/// Browser-submittable HTTP-POST AuthnRequest returned by the server plugin.
final class AuthSamlSignInForm {
  /// Creates a validated browser-submittable SAML form.
  const AuthSamlSignInForm({
    required this.providerId,
    required this.destination,
    required this.fields,
  });

  /// The provider that created the form.
  final String providerId;

  /// The IdP endpoint to which the browser form is submitted.
  final Uri destination;

  /// The form fields, including `SAMLRequest` and `RelayState`.
  final Map<String, String> fields;

  /// Decodes and validates a server response into a sign-in form.
  ///
  /// Throws a [FormatException] when the response is not an HTTPS HTTP-POST
  /// SAML form containing the required fields.
  factory AuthSamlSignInForm.fromJson(Map<String, dynamic> json) {
    final providerId = json['providerId']?.toString().trim() ?? '';
    final destination = Uri.tryParse(json['destination']?.toString() ?? '');
    final binding = json['binding']?.toString();
    final rawFields = json['fields'];
    if (providerId.isEmpty ||
        destination == null ||
        destination.scheme != 'https' ||
        binding != 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST' ||
        rawFields is! Map) {
      throw const FormatException('Invalid SAML sign-in response');
    }
    final fields = <String, String>{};
    for (final entry in rawFields.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Invalid SAML sign-in fields');
      }
      fields[entry.key as String] = entry.value as String;
    }
    if (!fields.containsKey('SAMLRequest') ||
        !fields.containsKey('RelayState')) {
      throw const FormatException('Invalid SAML sign-in fields');
    }
    return AuthSamlSignInForm(
      providerId: providerId,
      destination: destination,
      fields: Map<String, String>.unmodifiable(fields),
    );
  }
}

/// Client operations exposed by the SAML server plugin.
final class AuthSamlClient {
  /// Creates a client using [transport] for HTTP operations.
  const AuthSamlClient(this._transport);

  final AuthClientTransport _transport;

  /// Starts SAML sign-in and returns the form to submit to the IdP.
  Future<AuthSamlSignInForm> signIn(AuthSamlSignInRequest request) async {
    final response = await _transport.mutate(
      'POST',
      const AuthRoutePath('/sso/saml/sign-in'),
      request.toJson(),
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid SAML sign-in response');
    }
    return AuthSamlSignInForm.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// Fetches service-provider metadata for [providerId].
  ///
  /// Throws an [ArgumentError] when [providerId] is blank.
  Future<String> serviceProviderMetadata(String providerId) async {
    final normalized = providerId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(providerId, 'providerId');
    final response = await _transport.request(
      'GET',
      const AuthRoutePath(
        '/sso/saml/metadata/{providerId}',
        parameters: <AuthRouteParameterKey>[authSamlProviderIdRouteParameter],
      ),
      pathParameters: <AuthRouteParameterKey, String>{
        authSamlProviderIdRouteParameter: normalized,
      },
    );
    return response.body;
  }
}
