import 'dart:convert';

import 'client.dart';
import 'plugin.dart';
import 'saml.dart';
import 'saml_models.dart';

final class AuthSamlClientPlugin implements AuthClientPlugin<AuthSamlClient> {
  const AuthSamlClientPlugin();

  @override
  String get id => authSamlPluginId;

  @override
  AuthSamlClient install(AuthClientPluginContext context) =>
      AuthSamlClient(context.transport);
}

final class AuthSamlSignInRequest {
  const AuthSamlSignInRequest({
    this.providerId,
    this.verifiedDomain,
    this.organizationSlug,
    this.callbackUrl,
  });

  final String? providerId;
  final String? verifiedDomain;
  final String? organizationSlug;
  final Uri? callbackUrl;

  Map<String, dynamic> toJson() => {
    if (providerId != null) 'providerId': providerId,
    if (verifiedDomain != null) 'domain': verifiedDomain,
    if (organizationSlug != null) 'organizationSlug': organizationSlug,
    if (callbackUrl != null) 'callbackUrl': callbackUrl.toString(),
  };
}

/// Browser-submittable HTTP-POST AuthnRequest returned by the server plugin.
final class AuthSamlSignInForm {
  const AuthSamlSignInForm({
    required this.providerId,
    required this.destination,
    required this.fields,
  });

  final String providerId;
  final Uri destination;
  final Map<String, String> fields;

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

final class AuthSamlClient {
  const AuthSamlClient(this._transport);
  final AuthClientTransport _transport;

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
