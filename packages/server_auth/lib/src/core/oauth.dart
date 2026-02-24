import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Represents an exception that occurs during OAuth2 operations.
class OAuth2Exception implements Exception {
  OAuth2Exception(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'OAuth2Exception($statusCode): $message';
}

/// Represents the response from an OAuth2 token endpoint.
class OAuthTokenResponse {
  OAuthTokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.refreshToken,
    this.scope,
    required this.raw,
  });

  factory OAuthTokenResponse.fromJson(Map<String, dynamic> json) {
    return OAuthTokenResponse(
      accessToken: json['access_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: (json['expires_in'] is num)
          ? (json['expires_in'] as num).toInt()
          : null,
      refreshToken: json['refresh_token'] as String?,
      scope: json['scope'] as String?,
      raw: json,
    );
  }

  final String accessToken;
  final String tokenType;
  final int? expiresIn;
  final String? refreshToken;
  final String? scope;
  final Map<String, dynamic> raw;
}

/// Generic OAuth2 client for token exchange and userinfo requests.
class OAuth2Client {
  OAuth2Client({
    required this.tokenEndpoint,
    this.clientId,
    this.clientSecret,
    this.defaultHeaders = const <String, String>{},
    this.useBasicAuth = true,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final Uri tokenEndpoint;
  final String? clientId;
  final String? clientSecret;
  final Map<String, String> defaultHeaders;
  final bool useBasicAuth;
  final http.Client _httpClient;

  Future<OAuthTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
    String? codeVerifier,
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri.toString(),
      'scope': ?scope,
      'code_verifier': ?codeVerifier,
      'client_id': ?clientId,
      ...?additionalParameters,
    };
    return _sendTokenRequest(body);
  }

  Future<OAuthTokenResponse> clientCredentials({
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      'grant_type': 'client_credentials',
      'scope': ?scope,
      'client_id': ?clientId,
      ...?additionalParameters,
    };
    return _sendTokenRequest(body);
  }

  Future<OAuthTokenResponse> refreshToken({
    required String refreshToken,
    String? scope,
    Map<String, String>? additionalParameters,
  }) {
    final body = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': ?scope,
      'client_id': ?clientId,
      ...?additionalParameters,
    };
    return _sendTokenRequest(body);
  }

  Future<OAuthTokenResponse> _sendTokenRequest(Map<String, String> body) async {
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      ...defaultHeaders,
    };
    if (clientId != null && clientSecret != null && useBasicAuth) {
      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));
      headers['Authorization'] = 'Basic $credentials';
    }
    if (!useBasicAuth) {
      body.addAll({'client_id': ?clientId, 'client_secret': ?clientSecret});
    }

    final response = await _httpClient.post(
      tokenEndpoint,
      headers: headers,
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuth2Exception(
        'Token endpoint responded with ${response.statusCode}',
        response.statusCode,
      );
    }

    final responseBody = response.body.trim();
    if (responseBody.isEmpty) {
      throw OAuth2Exception('Token endpoint returned empty response');
    }

    final contentType =
        response.headers[HttpHeaders.contentTypeHeader]?.toLowerCase() ?? '';
    Map<String, dynamic> jsonResponse;
    if (contentType.contains('application/json') ||
        responseBody.startsWith('{')) {
      jsonResponse = json.decode(responseBody) as Map<String, dynamic>;
    } else {
      final parsed = Uri.splitQueryString(responseBody);
      jsonResponse = parsed.map((key, value) => MapEntry(key, value));
    }
    return OAuthTokenResponse.fromJson(jsonResponse);
  }

  Future<Map<String, dynamic>> fetchUserInfo(
    Uri endpoint,
    String accessToken,
  ) async {
    final response = await _httpClient.get(
      endpoint,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $accessToken',
        ...defaultHeaders,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuth2Exception(
        'Userinfo endpoint responded with ${response.statusCode}',
        response.statusCode,
      );
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }
}
