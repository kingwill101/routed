import 'dart:async';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';
import 'package:routed_inertia/routed_inertia.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  engineTest('ctx.inertia renders json and headers', (engine, client) async {
    engine.get('/dashboard', (ctx) {
      return ctx.inertia('Dashboard', props: {'name': 'Ada'}, version: '1.0');
    });

    final response = await client.get(
      '/dashboard',
      headers: {
        'X-Inertia': ['true'],
      },
    );

    response
        .assertStatus(200)
        .assertHeaderContains('X-Inertia', 'true')
        .assertHeaderContains('Vary', 'X-Inertia')
        .assertJsonPath('component', 'Dashboard')
        .assertJsonPath('props.name', 'Ada')
        .assertJsonPath('version', '1.0');
  });

  engineTest('ctx.inertia resolves async props', (engine, client) async {
    engine.get('/async', (ctx) {
      return ctx.inertia(
        'Async',
        props: {
          'user': Future.value({'name': 'Ada'}),
          'lazy': LazyProp(() async => 'Lazy'),
        },
      );
    });

    final response = await client.get(
      '/async',
      headers: {
        'X-Inertia': ['true'],
        'X-Inertia-Partial-Component': ['Async'],
        'X-Inertia-Partial-Data': ['user,lazy'],
      },
    );

    response
        .assertStatus(200)
        .assertJsonPath('props.user.name', 'Ada')
        .assertJsonPath('props.lazy', 'Lazy');
  });

  engineTest('ctx.inertia url honors forwarded prefix', (engine, client) async {
    engine.get('/prefixed', (ctx) {
      return ctx.inertia('Prefixed', props: const {});
    });

    final response = await client.get(
      '/prefixed?filter=a',
      headers: {
        'X-Inertia': ['true'],
        'X-Forwarded-Prefix': ['/sub/directory'],
      },
    );

    response
        .assertStatus(200)
        .assertJsonPath('url', '/sub/directory/prefixed?filter=a');
  });

  engineTest('ctx.inertia avoids double prefix', (engine, client) async {
    engine.get('/subpath/product/123', (ctx) {
      return ctx.inertia('Product', props: const {});
    });

    final response = await client.get(
      '/subpath/product/123',
      headers: {
        'X-Inertia': ['true'],
        'X-Forwarded-Prefix': ['/subpath'],
      },
    );

    response.assertStatus(200).assertJsonPath('url', '/subpath/product/123');
  });

  engineTest('ctx.inertia merges shared props', (engine, client) async {
    engine.get('/shared', (ctx) {
      ctx.inertiaShare({'app': 'Routed'});
      return ctx.inertia('Shared', props: {'user': 'Ada'});
    });

    final response = await client.get(
      '/shared',
      headers: {
        'X-Inertia': ['true'],
      },
    );

    response
        .assertStatus(200)
        .assertJsonPath('props.app', 'Routed')
        .assertJsonPath('props.user', 'Ada');
  });

  engineTest('partial reload requires component match', (engine, client) async {
    engine.get('/partial', (ctx) {
      return ctx.inertia(
        'Partial',
        props: {'name': 'Ada', 'lazy': LazyProp(() => 'Lazy')},
      );
    });

    final response = await client.get(
      '/partial',
      headers: {
        'X-Inertia': ['true'],
        'X-Inertia-Partial-Data': ['name'],
        'X-Inertia-Partial-Component': ['Other'],
      },
    );

    response.assertStatus(200).assertJsonPath('props.name', 'Ada');
    final json = response.json() as Map<String, dynamic>;
    final props = json['props'] as Map<String, dynamic>;
    expect(props.containsKey('lazy'), isFalse);
  });

  engineTest('reset keys remove merge props', (engine, client) async {
    engine.get('/merge', (ctx) {
      return ctx.inertia('Merge', props: {'merge': MergeProp(() => 'value')});
    });

    final response = await client.get(
      '/merge',
      headers: {
        'X-Inertia': ['true'],
        'X-Inertia-Partial-Data': ['merge'],
        'X-Inertia-Partial-Component': ['Merge'],
        'X-Inertia-Reset': ['merge'],
      },
    );

    response.assertStatus(200);
    final json = response.json() as Map<String, dynamic>;
    expect(
      json['mergeProps'] == null || (json['mergeProps'] as List).isEmpty,
      isTrue,
    );
  });

  engineTest('history flags are applied', (engine, client) async {
    engine.get('/history', (ctx) {
      ctx.inertiaEncryptHistory();
      ctx.inertiaClearHistory();
      return ctx.inertia('History', props: const {});
    });

    final response = await client.get(
      '/history',
      headers: {
        'X-Inertia': ['true'],
      },
    );

    response
        .assertStatus(200)
        .assertJsonPath('encryptHistory', true)
        .assertJsonPath('clearHistory', true);
  });

  engineTest('history defaults are false', (engine, client) async {
    engine.get('/history-default', (ctx) {
      return ctx.inertia('History', props: const {});
    });

    final response = await client.get(
      '/history-default',
      headers: {
        'X-Inertia': ['true'],
      },
    );

    response
        .assertStatus(200)
        .assertJsonPath('encryptHistory', false)
        .assertJsonPath('clearHistory', false);
  });

  engineTest('history encrypts from config', (engine, client) async {
    engine.get('/history-config', (ctx) {
      ctx.container.instance<InertiaConfig>(_historyConfig(encrypt: true));
      return ctx.inertia('History', props: const {});
    });

    final response = await client.get(
      '/history-config',
      headers: {
        'X-Inertia': ['true'],
      },
    );

    response.assertStatus(200).assertJsonPath('encryptHistory', true);
  });

  engineTest('history config can be overridden per request', (
    engine,
    client,
  ) async {
    engine.get('/history-override', (ctx) {
      ctx.container.instance<InertiaConfig>(_historyConfig(encrypt: true));
      ctx.inertiaEncryptHistory(false);
      return ctx.inertia('History', props: const {});
    });

    final response = await client.get(
      '/history-override',
      headers: {
        'X-Inertia': ['true'],
      },
    );

    response.assertStatus(200).assertJsonPath('encryptHistory', false);
  });

  engineTest('flash data is included', (engine, client) async {
    engine.get('/flash', (ctx) {
      ctx.inertiaFlash('notice', 'Saved');
      return ctx.inertia('Flash', props: const {});
    });

    final response = await client.get(
      '/flash',
      headers: {
        'X-Inertia': ['true'],
      },
    );

    response.assertStatus(200).assertJsonPath('flash.notice', 'Saved');
  });

  engineTest('error bag selection maps errors', (engine, client) async {
    engine.get('/errors', (ctx) {
      ctx.inertiaErrors({'email': 'Required'});
      return ctx.inertia('Errors', props: const {});
    });

    final response = await client.get(
      '/errors',
      headers: {
        'X-Inertia': ['true'],
        'X-Inertia-Error-Bag': ['login'],
      },
    );

    response
        .assertStatus(200)
        .assertJsonPath('props.errors.login.email', 'Required');
  });

  engineTest('SSR response is injected into HTML', (engine, client) async {
    final gateway = _FakeSsrGateway();
    engine.get('/ssr', (ctx) {
      return ctx.inertia(
        'Ssr',
        props: {'title': 'SSR'},
        ssrEnabled: true,
        ssrGateway: gateway,
        htmlBuilder: (page, ssr) {
          return '<html><body>${ssr?.body}</body></html>';
        },
      );
    });

    final response = await client.get('/ssr');
    response.assertStatus(200).assertBodyContains('SSR body');
  });
}

InertiaConfig _historyConfig({required bool encrypt}) {
  return InertiaConfig(
    version: '',
    rootView: null,
    history: InertiaHistoryConfig(encrypt: encrypt),
    ssr: const InertiaSsrSettings(),
    assets: const InertiaAssetsConfig(),
  );
}

class _FakeSsrGateway implements SsrGateway {
  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<SsrResponse> render(String pageJson) async {
    return const SsrResponse(
      body: '<div>SSR body</div>',
      head: '<title>SSR</title>',
    );
  }
}
