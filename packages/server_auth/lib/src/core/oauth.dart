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
