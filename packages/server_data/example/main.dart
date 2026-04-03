import 'dart:io';

import 'package:server_data/server_data.dart';

Future<void> main() async {
  await runCacheExample();
  runStorageExample();
  await runSessionExample();
  await runRateLimitExample();
}

Future<void> runCacheExample() async {
  final cacheManager = DataCacheManager(prefix: 'demo:')
    ..registerStore('default', {'driver': 'array'});

  final repository = cacheManager.store('default');
  await repository.put('status', 'ok', const Duration(seconds: 30));
  final status = await repository.get('status');
  print('cache status = $status');
}

void runStorageExample() {
  final storage = StorageManager()
    ..registerDisk('local', LocalStorageDisk(root: 'storage/app'))
    ..setDefault('local');

  final path = storage.resolve('avatars/alice.png');
  print('storage path = $path');
}

Future<void> runSessionExample() async {
  final sessionStore = MemorySessionStore(
    codecs: [SecureCookie(key: SecureCookie.generateKey())],
    defaultOptions: SessionOptions(maxAge: 120),
  );

  final response = DemoSessionResponse();
  final session = Session(
    name: 'demo_session',
    options: SessionOptions(maxAge: 120),
  );
  session.setValue('user_id', 'user_42');

  await sessionStore.write(DemoSessionRequest(), response, session);
  final cookie = response.cookies.singleWhere(
    (cookie) => cookie.name == 'demo_session',
  );
  final loaded = await sessionStore.read(
    DemoSessionRequest(cookies: [cookie]),
    'demo_session',
  );

  print('session user_id = ${loaded.getValue<String>('user_id')}');
}

Future<void> runRateLimitExample() async {
  final repository = RepositoryImpl(ArrayStore(), 'rate_limit', '');
  final backend = CacheRateLimiterBackend(repository: repository);

  final policy = CompiledRateLimitPolicy(
    name: 'api',
    matcher: RequestMatcher(method: 'GET', pattern: '/api/**'),
    keyResolver: const IpKeyResolver(),
    algorithm: buildBucketConfig(
      capacity: 2,
      refillInterval: const Duration(seconds: 30),
    ),
    backend: backend,
    failover: RateLimitFailoverMode.local,
  );

  final service = RateLimitService([policy]);
  final request = DemoRateLimitRequest(
    method: 'GET',
    path: '/api/users',
    clientIP: '127.0.0.1',
  );

  for (var attempt = 1; attempt <= 3; attempt++) {
    final blocked = await service.check(request);
    if (blocked == null) {
      print('rate limit attempt $attempt = allowed');
    } else {
      print(
        'rate limit attempt $attempt = blocked '
        '(retry after ${blocked.retryAfter.inSeconds}s)',
      );
    }
  }

  await service.dispose();
}

class DemoSessionRequest implements SessionRequest {
  DemoSessionRequest({List<Cookie>? cookies}) : cookies = cookies ?? <Cookie>[];

  @override
  final List<Cookie> cookies;

  @override
  String header(String name) => '';
}

class DemoSessionResponse implements SessionResponse {
  final List<Cookie> cookies = <Cookie>[];

  @override
  void setCookie(
    String name,
    dynamic value, {
    int? maxAge,
    String path = '/',
    String domain = '',
    bool secure = false,
    bool httpOnly = false,
    SameSite? sameSite,
  }) {
    final cookie = Cookie(name, value.toString())
      ..path = path
      ..maxAge = maxAge
      ..secure = secure
      ..httpOnly = httpOnly
      ..sameSite = sameSite;
    if (domain.isNotEmpty) {
      cookie.domain = domain;
    }
    cookies.removeWhere((existing) => existing.name == name);
    cookies.add(cookie);
  }
}

class DemoRateLimitRequest implements RateLimitRequest {
  const DemoRateLimitRequest({
    required this.method,
    required this.path,
    required this.clientIP,
  });

  @override
  final String method;

  @override
  final String path;

  @override
  final String clientIP;

  @override
  String get remoteAddr => clientIP;

  @override
  String header(String name) => '';
}
