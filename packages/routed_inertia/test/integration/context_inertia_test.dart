import 'package:inertia_dart/inertia.dart';
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

    response
        .assertStatus(200)
        .assertJsonPath('props.name', 'Ada')
        .assertJsonPath('props.lazy', 'Lazy');
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
