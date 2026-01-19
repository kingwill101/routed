import 'package:routed/routed.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleProvider', () {
    test('creates provider with required options', () {
      final provider = googleProvider(
        GoogleProviderOptions(
          clientId: 'google-client-id',
          clientSecret: 'google-client-secret',
          redirectUri: 'https://example.com/auth/callback/google',
        ),
      );

      expect(provider.id, equals('google'));
      expect(provider.name, equals('Google'));
      expect(provider.type, equals(AuthProviderType.oidc));
      expect(provider.clientId, equals('google-client-id'));
    });

    test('default scopes include openid, profile, email', () {
      final options = GoogleProviderOptions(
        clientId: 'id',
        clientSecret: 'secret',
        redirectUri: 'https://example.com/callback',
      );

      expect(options.scopes, containsAll(['openid', 'profile', 'email']));
    });

    test('parses Google profile correctly', () {
      final profile = GoogleProfile.fromJson({
        'sub': '123456789',
        'email': 'user@gmail.com',
        'email_verified': true,
        'name': 'Test User',
        'picture': 'https://lh3.googleusercontent.com/photo',
        'given_name': 'Test',
        'family_name': 'User',
        'locale': 'en',
        'hd': 'example.com',
      });

      expect(profile.sub, equals('123456789'));
      expect(profile.email, equals('user@gmail.com'));
      expect(profile.emailVerified, isTrue);
      expect(profile.name, equals('Test User'));
      expect(profile.givenName, equals('Test'));
      expect(profile.familyName, equals('User'));
      expect(profile.hd, equals('example.com'));
    });

    test('profile toJson roundtrip', () {
      final original = GoogleProfile(
        sub: 'sub-123',
        email: 'test@example.com',
        name: 'Test',
      );

      final json = original.toJson();
      final restored = GoogleProfile.fromJson(json);

      expect(restored.sub, equals(original.sub));
      expect(restored.email, equals(original.email));
      expect(restored.name, equals(original.name));
    });

    test('maps profile to AuthUser', () {
      final provider = googleProvider(
        GoogleProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'https://example.com/callback',
        ),
      );

      final profile = GoogleProfile(
        sub: 'google-user-123',
        email: 'user@gmail.com',
        name: 'Gmail User',
        picture: 'https://photo.url',
      );

      final user = provider.mapProfile(profile);

      expect(user.id, equals('google-user-123'));
      expect(user.email, equals('user@gmail.com'));
      expect(user.name, equals('Gmail User'));
      expect(user.image, equals('https://photo.url'));
    });
  });

  group('DiscordProvider', () {
    test('creates provider with required options', () {
      final provider = discordProvider(
        DiscordProviderOptions(
          clientId: 'discord-client-id',
          clientSecret: 'discord-client-secret',
          redirectUri: 'https://example.com/auth/callback/discord',
        ),
      );

      expect(provider.id, equals('discord'));
      expect(provider.name, equals('Discord'));
      expect(provider.type, equals(AuthProviderType.oauth));
    });

    test('parses Discord profile correctly', () {
      final profile = DiscordProfile.fromJson({
        'id': '80351110224678912',
        'username': 'Nelly',
        'discriminator': '1337',
        'global_name': 'Nelly',
        'avatar': 'a_d5efa99b3eeaa7dd43acca82f5692432',
        'email': 'nelly@discord.com',
        'verified': true,
        'locale': 'en-US',
      });

      expect(profile.id, equals('80351110224678912'));
      expect(profile.username, equals('Nelly'));
      expect(profile.globalName, equals('Nelly'));
      expect(profile.email, equals('nelly@discord.com'));
      expect(profile.verified, isTrue);
    });

    test('avatar URL construction', () {
      final profile = DiscordProfile.fromJson({
        'id': '12345',
        'username': 'User',
        'avatar': 'abc123',
      });

      expect(profile.avatarUrl, contains('cdn.discordapp.com'));
      expect(profile.avatarUrl, contains('12345'));
      expect(profile.avatarUrl, contains('abc123'));
    });

    test('maps profile to AuthUser', () {
      final provider = discordProvider(
        DiscordProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'https://example.com/callback',
        ),
      );

      final profile = DiscordProfile(
        id: 'discord-123',
        username: 'DiscordUser',
        globalName: 'Display Name',
        email: 'user@discord.com',
        avatar: 'avatar-hash',
      );

      final user = provider.mapProfile(profile);

      expect(user.id, equals('discord-123'));
      expect(user.email, equals('user@discord.com'));
      expect(user.name, equals('Display Name'));
    });
  });

  group('MicrosoftEntraProvider', () {
    test('creates provider with required options', () {
      final provider = microsoftEntraProvider(
        MicrosoftEntraProviderOptions(
          clientId: 'ms-client-id',
          clientSecret: 'ms-client-secret',
          redirectUri: 'https://example.com/auth/callback/microsoft',
        ),
      );

      expect(provider.id, equals('microsoft-entra-id'));
      expect(provider.name, equals('Microsoft Entra ID'));
      expect(provider.type, equals(AuthProviderType.oidc));
    });

    test('parses Microsoft profile correctly', () {
      final profile = MicrosoftEntraProfile.fromJson({
        'sub': 'AAAAAAAAABBBBBBBBBCCCCCCCCCddddddd',
        'email': 'user@contoso.com',
        'name': 'John Doe',
        'preferred_username': 'john.doe@contoso.com',
        'given_name': 'John',
        'family_name': 'Doe',
        'oid': 'oid-123',
        'tid': 'tenant-123',
      });

      expect(profile.sub, equals('AAAAAAAAABBBBBBBBBCCCCCCCCCddddddd'));
      expect(profile.email, equals('user@contoso.com'));
      expect(profile.preferredUsername, equals('john.doe@contoso.com'));
      expect(profile.oid, equals('oid-123'));
      expect(profile.tid, equals('tenant-123'));
    });
  });

  group('AppleProvider', () {
    test('creates provider with required options', () {
      final provider = appleProvider(
        AppleProviderOptions(
          clientId: 'com.example.app',
          clientSecret: 'apple-client-secret',
          redirectUri: 'https://example.com/auth/callback/apple',
        ),
      );

      expect(provider.id, equals('apple'));
      expect(provider.name, equals('Apple'));
      expect(provider.type, equals(AuthProviderType.oidc));
    });

    test('parses Apple profile correctly', () {
      final profile = AppleProfile.fromJson({
        'sub': '000123.abc.456',
        'email': 'user@privaterelay.appleid.com',
        'email_verified': 'true',
        'is_private_email': 'true',
      });

      expect(profile.sub, equals('000123.abc.456'));
      expect(profile.email, equals('user@privaterelay.appleid.com'));
      expect(profile.emailVerified, isTrue);
      expect(profile.isPrivateEmail, isTrue);
    });

    test('uses form_post response mode', () {
      final provider = appleProvider(
        AppleProviderOptions(
          clientId: 'com.example.app',
          clientSecret: 'secret',
          redirectUri: 'https://example.com/callback',
        ),
      );

      expect(
        provider.authorizationParams['response_mode'],
        equals('form_post'),
      );
    });
  });

  group('TwitterProvider', () {
    test('creates provider with required options', () {
      final provider = twitterProvider(
        TwitterProviderOptions(
          clientId: 'twitter-client-id',
          clientSecret: 'twitter-client-secret',
          redirectUri: 'https://example.com/auth/callback/twitter',
        ),
      );

      expect(provider.id, equals('twitter'));
      expect(provider.name, equals('Twitter'));
      expect(provider.type, equals(AuthProviderType.oauth));
    });

    test('parses Twitter profile correctly', () {
      final profile = TwitterProfile.fromJson({
        'data': {
          'id': '2244994945',
          'name': 'Twitter Dev',
          'username': 'TwitterDev',
          'profile_image_url':
              'https://pbs.twimg.com/profile_images/880136122604507136/xHrnqf1T_normal.jpg',
        },
      });

      expect(profile.id, equals('2244994945'));
      expect(profile.name, equals('Twitter Dev'));
      expect(profile.username, equals('TwitterDev'));
    });
  });

  group('FacebookProvider', () {
    test('creates provider with required options', () {
      final provider = facebookProvider(
        FacebookProviderOptions(
          clientId: 'fb-app-id',
          clientSecret: 'fb-app-secret',
          redirectUri: 'https://example.com/auth/callback/facebook',
        ),
      );

      expect(provider.id, equals('facebook'));
      expect(provider.name, equals('Facebook'));
      expect(provider.type, equals(AuthProviderType.oauth));
    });

    test('parses Facebook profile correctly', () {
      final profile = FacebookProfile.fromJson({
        'id': '10158675309',
        'name': 'John Smith',
        'email': 'john@example.com',
        'picture': {
          'data': {'url': 'https://platform-lookaside.fbsbx.com/photo.jpg'},
        },
      });

      expect(profile.id, equals('10158675309'));
      expect(profile.name, equals('John Smith'));
      expect(profile.email, equals('john@example.com'));
      expect(profile.picture?.url, contains('fbsbx.com'));
    });
  });

  group('GitLabProvider', () {
    test('creates provider with required options', () {
      final provider = gitlabProvider(
        GitLabProviderOptions(
          clientId: 'gitlab-app-id',
          clientSecret: 'gitlab-secret',
          redirectUri: 'https://example.com/auth/callback/gitlab',
        ),
      );

      expect(provider.id, equals('gitlab'));
      expect(provider.name, equals('GitLab'));
      expect(provider.type, equals(AuthProviderType.oauth));
    });

    test('parses GitLab profile correctly', () {
      final profile = GitLabProfile.fromJson({
        'id': 1,
        'username': 'john_smith',
        'email': 'john@example.com',
        'name': 'John Smith',
        'avatar_url':
            'https://gitlab.example.com/uploads/-/system/user/avatar/1/avatar.png',
        'web_url': 'https://gitlab.example.com/john_smith',
      });

      expect(profile.id, equals(1));
      expect(profile.username, equals('john_smith'));
      expect(profile.email, equals('john@example.com'));
    });

    test('supports self-hosted GitLab', () {
      final options = GitLabProviderOptions(
        clientId: 'id',
        clientSecret: 'secret',
        redirectUri: 'https://example.com/callback',
        baseUrl: 'https://gitlab.mycompany.com',
      );

      expect(options.baseUrl, equals('https://gitlab.mycompany.com'));
    });
  });

  group('SlackProvider', () {
    test('creates provider with required options', () {
      final provider = slackProvider(
        SlackProviderOptions(
          clientId: 'slack-client-id',
          clientSecret: 'slack-client-secret',
          redirectUri: 'https://example.com/auth/callback/slack',
        ),
      );

      expect(provider.id, equals('slack'));
      expect(provider.name, equals('Slack'));
      expect(provider.type, equals(AuthProviderType.oidc));
    });

    test('parses Slack profile correctly', () {
      final profile = SlackProfile.fromJson({
        'sub': 'U0R7JM',
        'https://slack.com/user_id': 'U0R7JM',
        'email': 'user@example.com',
        'email_verified': true,
        'name': 'Cal Henderson',
        'picture': 'https://secure.gravatar.com/avatar/xxx.jpg',
        'https://slack.com/team_id': 'T0R7GR',
        'https://slack.com/team_name': 'Slack',
      });

      expect(profile.sub, equals('U0R7JM'));
      expect(profile.email, equals('user@example.com'));
      expect(profile.name, equals('Cal Henderson'));
      expect(profile.slackTeamId, equals('T0R7GR'));
      expect(profile.slackTeamName, equals('Slack'));
    });
  });

  group('SpotifyProvider', () {
    test('creates provider with required options', () {
      final provider = spotifyProvider(
        SpotifyProviderOptions(
          clientId: 'spotify-client-id',
          clientSecret: 'spotify-client-secret',
          redirectUri: 'https://example.com/auth/callback/spotify',
        ),
      );

      expect(provider.id, equals('spotify'));
      expect(provider.name, equals('Spotify'));
      expect(provider.type, equals(AuthProviderType.oauth));
    });

    test('parses Spotify profile correctly', () {
      final profile = SpotifyProfile.fromJson({
        'id': 'wizzler',
        'display_name': 'JM Wizzler',
        'email': 'email@example.com',
        'images': [
          {'url': 'https://i.scdn.co/image/xxx'},
        ],
        'product': 'premium',
        'country': 'US',
      });

      expect(profile.id, equals('wizzler'));
      expect(profile.displayName, equals('JM Wizzler'));
      expect(profile.email, equals('email@example.com'));
      expect(profile.product, equals('premium'));
    });
  });

  group('LinkedInProvider', () {
    test('creates provider with required options', () {
      final provider = linkedInProvider(
        LinkedInProviderOptions(
          clientId: 'linkedin-client-id',
          clientSecret: 'linkedin-client-secret',
          redirectUri: 'https://example.com/auth/callback/linkedin',
        ),
      );

      expect(provider.id, equals('linkedin'));
      expect(provider.name, equals('LinkedIn'));
      expect(provider.type, equals(AuthProviderType.oidc));
    });

    test('parses LinkedIn profile correctly', () {
      final profile = LinkedInProfile.fromJson({
        'sub': 'yrZCpj2Z12',
        'email': 'hsimpson@linkedin.com',
        'email_verified': true,
        'name': 'Homer Simpson',
        'given_name': 'Homer',
        'family_name': 'Simpson',
        'picture': 'https://media.licdn.com/dms/image/xxx',
        'locale': 'en-US',
      });

      expect(profile.sub, equals('yrZCpj2Z12'));
      expect(profile.email, equals('hsimpson@linkedin.com'));
      expect(profile.name, equals('Homer Simpson'));
      expect(profile.givenName, equals('Homer'));
      expect(profile.familyName, equals('Simpson'));
    });
  });

  group('TwitchProvider', () {
    test('creates provider with required options', () {
      final provider = twitchProvider(
        TwitchProviderOptions(
          clientId: 'twitch-client-id',
          clientSecret: 'twitch-client-secret',
          redirectUri: 'https://example.com/auth/callback/twitch',
        ),
      );

      expect(provider.id, equals('twitch'));
      expect(provider.name, equals('Twitch'));
      expect(provider.type, equals(AuthProviderType.oidc));
    });

    test('parses Twitch profile correctly', () {
      final profile = TwitchProfile.fromJson({
        'sub': '713936733',
        'preferred_username': 'twitchuser',
        'email': 'user@twitch.tv',
        'email_verified': true,
        'picture':
            'https://static-cdn.jtvnw.net/user-default-pictures-uv/xxx.png',
      });

      expect(profile.sub, equals('713936733'));
      expect(profile.preferredUsername, equals('twitchuser'));
      expect(profile.email, equals('user@twitch.tv'));
    });

    test('does not use basic auth', () {
      final provider = twitchProvider(
        TwitchProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'https://example.com/callback',
        ),
      );

      expect(provider.useBasicAuth, isFalse);
    });
  });

  group('TelegramProvider', () {
    test('creates provider with required options', () {
      final provider = telegramProvider(
        TelegramProviderOptions(
          botToken: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
          botUsername: 'ExampleBot',
          redirectUri: 'https://example.com/auth/callback/telegram',
        ),
      );

      expect(provider.id, equals('telegram'));
      expect(provider.name, equals('Telegram'));
      // Telegram uses OAuth as closest match since it's widget-based
      expect(provider.type, equals(AuthProviderType.oauth));
    });

    test('parses Telegram profile correctly', () {
      final profile = TelegramProfile.fromJson({
        'id': 123456789,
        'first_name': 'John',
        'last_name': 'Doe',
        'username': 'johndoe',
        'photo_url': 'https://t.me/i/userpic/320/johndoe.jpg',
        'auth_date': 1609459200,
      });

      expect(profile.id, equals(123456789));
      expect(profile.firstName, equals('John'));
      expect(profile.lastName, equals('Doe'));
      expect(profile.username, equals('johndoe'));
      expect(profile.fullName, equals('John Doe'));
    });

    test('default auth date max age is 5 minutes', () {
      final options = TelegramProviderOptions(
        botToken: 'token',
        botUsername: 'bot',
        redirectUri: 'https://example.com/callback',
      );

      expect(options.authDateMaxAge, equals(const Duration(minutes: 5)));
    });
  });

  group('Provider type assignments', () {
    test('OIDC providers use oidc type', () {
      final google = googleProvider(
        GoogleProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final microsoft = microsoftEntraProvider(
        MicrosoftEntraProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final apple = appleProvider(
        AppleProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final slack = slackProvider(
        SlackProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final linkedin = linkedInProvider(
        LinkedInProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final twitch = twitchProvider(
        TwitchProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );

      expect(google.type, equals(AuthProviderType.oidc));
      expect(microsoft.type, equals(AuthProviderType.oidc));
      expect(apple.type, equals(AuthProviderType.oidc));
      expect(slack.type, equals(AuthProviderType.oidc));
      expect(linkedin.type, equals(AuthProviderType.oidc));
      expect(twitch.type, equals(AuthProviderType.oidc));
    });

    test('OAuth providers use oauth type', () {
      final discord = discordProvider(
        DiscordProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final twitter = twitterProvider(
        TwitterProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final facebook = facebookProvider(
        FacebookProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final gitlab = gitlabProvider(
        GitLabProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final spotify = spotifyProvider(
        SpotifyProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final telegram = telegramProvider(
        TelegramProviderOptions(
          botToken: 'token',
          botUsername: 'bot',
          redirectUri: 'uri',
        ),
      );
      final dropbox = dropboxProvider(
        DropboxProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );

      expect(discord.type, equals(AuthProviderType.oauth));
      expect(twitter.type, equals(AuthProviderType.oauth));
      expect(facebook.type, equals(AuthProviderType.oauth));
      expect(gitlab.type, equals(AuthProviderType.oauth));
      expect(spotify.type, equals(AuthProviderType.oauth));
      expect(telegram.type, equals(AuthProviderType.oauth));
      expect(dropbox.type, equals(AuthProviderType.oauth));
    });
  });

  group('DropboxProvider', () {
    test('creates provider with required options', () {
      final provider = dropboxProvider(
        DropboxProviderOptions(
          clientId: 'dropbox-client-id',
          clientSecret: 'dropbox-client-secret',
          redirectUri: 'https://example.com/auth/callback/dropbox',
        ),
      );

      expect(provider.id, equals('dropbox'));
      expect(provider.name, equals('Dropbox'));
      expect(provider.type, equals(AuthProviderType.oauth));
      expect(provider.clientId, equals('dropbox-client-id'));
    });

    test('default scopes include account_info.read', () {
      final options = DropboxProviderOptions(
        clientId: 'id',
        clientSecret: 'secret',
        redirectUri: 'https://example.com/callback',
      );

      expect(options.scopes, contains('account_info.read'));
    });

    test('default token access type is offline', () {
      final options = DropboxProviderOptions(
        clientId: 'id',
        clientSecret: 'secret',
        redirectUri: 'https://example.com/callback',
      );

      expect(options.tokenAccessType, equals('offline'));
    });

    test('parses Dropbox profile correctly', () {
      final profile = DropboxProfile.fromJson({
        'account_id': 'dbid:AAH4f99T0taONIb-OurWxbNQ6ywGRopQngc',
        'email': 'franz@dropbox.com',
        'email_verified': true,
        'name': {
          'given_name': 'Franz',
          'surname': 'Ferdinand',
          'familiar_name': 'Franz',
          'display_name': 'Franz Ferdinand',
          'abbreviated_name': 'FF',
        },
        'profile_photo_url': 'https://dl-web.dropbox.com/account_photo/get/xxx',
        'disabled': false,
        'country': 'US',
        'locale': 'en',
        'is_paired': true,
        'account_type': {'.tag': 'pro'},
      });

      expect(
        profile.accountId,
        equals('dbid:AAH4f99T0taONIb-OurWxbNQ6ywGRopQngc'),
      );
      expect(profile.email, equals('franz@dropbox.com'));
      expect(profile.emailVerified, isTrue);
      expect(profile.name, equals('Franz Ferdinand'));
      expect(profile.disabled, isFalse);
      expect(profile.country, equals('US'));
      expect(profile.locale, equals('en'));
      expect(profile.isPaired, isTrue);
      expect(profile.accountType, equals('pro'));
    });

    test('profile toJson roundtrip', () {
      final original = DropboxProfile(
        accountId: 'dbid:test123',
        email: 'test@dropbox.com',
        name: 'Test User',
        emailVerified: true,
      );

      final json = original.toJson();
      final restored = DropboxProfile.fromJson(json);

      expect(restored.accountId, equals(original.accountId));
      expect(restored.email, equals(original.email));
      expect(restored.name, equals(original.name));
    });

    test('maps profile to AuthUser', () {
      final provider = dropboxProvider(
        DropboxProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'https://example.com/callback',
        ),
      );

      final profile = DropboxProfile(
        accountId: 'dbid:user-123',
        email: 'user@dropbox.com',
        name: 'Dropbox User',
        profilePhotoUrl: 'https://photo.url',
      );

      final user = provider.mapProfile(profile);

      expect(user.id, equals('dbid:user-123'));
      expect(user.email, equals('user@dropbox.com'));
      expect(user.name, equals('Dropbox User'));
      expect(user.image, equals('https://photo.url'));
    });

    test('has userInfoRequest for POST-based userinfo endpoint', () {
      final provider = dropboxProvider(
        DropboxProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'https://example.com/callback',
        ),
      );

      // Dropbox requires POST, so userInfoRequest should be set
      expect(provider.userInfoRequest, isNotNull);
      expect(provider.userInfoEndpoint, isNotNull);
      expect(
        provider.userInfoEndpoint.toString(),
        equals('https://api.dropboxapi.com/2/users/get_current_account'),
      );
    });

    test('authorization params include token_access_type', () {
      final provider = dropboxProvider(
        DropboxProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'https://example.com/callback',
          tokenAccessType: 'offline',
        ),
      );

      expect(
        provider.authorizationParams['token_access_type'],
        equals('offline'),
      );
    });
  });

  group('userInfoRequest callback', () {
    test('providers without userInfoRequest use default GET behavior', () {
      // Most providers don't need custom userinfo requests
      final google = googleProvider(
        GoogleProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final discord = discordProvider(
        DiscordProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );
      final spotify = spotifyProvider(
        SpotifyProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );

      expect(google.userInfoRequest, isNull);
      expect(discord.userInfoRequest, isNull);
      expect(spotify.userInfoRequest, isNull);
    });

    test('Dropbox has userInfoRequest for POST endpoint', () {
      final dropbox = dropboxProvider(
        DropboxProviderOptions(
          clientId: 'id',
          clientSecret: 'secret',
          redirectUri: 'uri',
        ),
      );

      expect(dropbox.userInfoRequest, isNotNull);
    });
  });
}
