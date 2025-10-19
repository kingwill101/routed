import 'dart:io';

import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  // Set a simple cookie
  engine.get('/set-cookie', (ctx) {
    ctx.setCookie(
      'user',
      'john_doe',
      maxAge: 3600,
      path: '/',
      secure: true,
      sameSite: SameSite.none,
    );
    ctx.json({'message': 'Cookie set'});
  });

  // Set multiple cookies
  engine.get('/set-preferences', (ctx) {
    ctx.setCookie('theme', 'dark', maxAge: 86400);
    ctx.setCookie('language', 'en', maxAge: 86400);
    ctx.json({'message': 'Preferences set'});
  });

  // Read cookies
  engine.get('/get-cookies', (ctx) {
    final userCookie = ctx.cookie('user');
    final themeCookie = ctx.cookie('theme');
    final languageCookie = ctx.cookie('language');

    ctx.json({
      'cookies': {
        'user': userCookie,
        'theme': themeCookie,
        'language': languageCookie,
      },
    });
  });

  // Delete a cookie by setting maxAge to 0
  engine.get('/delete-cookie', (ctx) {
    ctx.setCookie('user', '', maxAge: 0);
    ctx.json({'message': 'Cookie deleted'});
  });

  // Example of using cookies for theme preference
  engine.get('/theme', (ctx) {
    final theme = ctx.cookie('theme') ?? 'light';
    ctx.json({
      'current_theme': theme,
      'message': 'Current theme preference: $theme',
    });
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
