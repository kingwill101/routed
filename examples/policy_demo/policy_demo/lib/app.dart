import 'dart:io';

import 'package:routed/routed.dart';

class Project {
  const Project({required this.id, required this.name, required this.ownerId});

  final String id;
  final String name;
  final String ownerId;

  Project copyWith({String? name, String? ownerId}) {
    return Project(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'ownerId': ownerId};
}

class ProjectPolicy extends Policy<Project> {
  const ProjectPolicy();

  @override
  Future<bool> canView(AuthPrincipal? principal, Project resource) async {
    if (principal == null) return false;
    return principal.hasRole('admin') || principal.id == resource.ownerId;
  }

  @override
  Future<bool> canCreate(AuthPrincipal? principal) async {
    if (principal == null) return false;
    return principal.hasRole('admin') || principal.hasRole('editor');
  }

  @override
  Future<bool> canUpdate(AuthPrincipal? principal, Project resource) async {
    if (principal == null) return false;
    return principal.hasRole('admin') || principal.id == resource.ownerId;
  }

  @override
  Future<bool> canDelete(AuthPrincipal? principal, Project resource) async {
    if (principal == null) return false;
    return principal.hasRole('admin');
  }
}

Future<Engine> createEngine() async {
  final engine = await Engine.createFull(
    configOptions: const ConfigLoaderOptions(
      configDirectory: 'config',
      loadEnvFiles: false,
      includeEnvironmentSubdirectory: false,
    ),
  );

  final policyBindings = [
    PolicyBinding<Project>(
      policy: const ProjectPolicy(),
      abilityPrefix: 'project',
    ),
  ];

  engine.container.instance<AuthOptions>(
    AuthOptions(
      providers: [CredentialsProvider()],
      policies: PolicyOptions(bindings: policyBindings),
    ),
  );
  registerPoliciesWithHaigate(policyBindings);

  final users = <String, Map<String, dynamic>>{
    '1': {'id': '1', 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
    '2': {'id': '2', 'name': 'Alan Turing', 'email': 'alan@example.com'},
  };

  final projects = <String, Project>{
    '1': const Project(id: '1', name: 'Compiler', ownerId: 'ada'),
    '2': const Project(id: '2', name: 'Machine', ownerId: 'alan'),
  };

  engine.group(
    path: '/api/v1',
    builder: (router) {
      router.get('/health', (ctx) async {
        return ctx.json({'status': 'ok'});
      });

      router.get('/csrf', (ctx) async {
        final cookieName = ctx.engineConfig.security.csrfCookieName;
        var token = ctx.getSession<String>(cookieName) ?? '';
        if (token.isEmpty) {
          token = generateCsrfToken();
          ctx.setSession(cookieName, token);
          ctx.setCookie(
            cookieName,
            token,
            httpOnly: true,
            secure: false,
            sameSite: SameSite.lax,
            maxAge: const Duration(hours: 1).inSeconds,
          );
        }
        return ctx.json({'csrfToken': token});
      });

      router.post('/login', (ctx) async {
        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final id = payload['id']?.toString() ?? 'viewer';
        final role = payload['role']?.toString() ?? 'viewer';
        final principal = AuthPrincipal(id: id, roles: [role]);
        await SessionAuth.login(ctx, principal);
        ctx.session.regenerate();
        return ctx.json({'status': 'ok', 'principal': principal.toJson()});
      });

      router.get('/me', (ctx) async {
        final principal = SessionAuth.current(ctx);
        return ctx.json({'principal': principal?.toJson()});
      });

      router.get('/projects', (ctx) async {
        final visible = <Map<String, dynamic>>[];
        for (final project in projects.values) {
          final allowed = await Haigate.can(
            'project.view',
            ctx: ctx,
            payload: project,
          );
          if (allowed) {
            visible.add(project.toJson());
          }
        }
        return ctx.json({'data': visible});
      });

      router.post('/projects', (ctx) async {
        try {
          await Haigate.authorize('project.create', ctx: ctx);
        } on GateViolation {
          return ctx.json({
            'error': 'forbidden',
          }, statusCode: HttpStatus.forbidden);
        }

        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final id = (projects.length + 1).toString();
        final principal = SessionAuth.current(ctx);
        final created = Project(
          id: id,
          name: payload['name']?.toString() ?? 'project-$id',
          ownerId: principal?.id ?? 'system',
        );
        projects[id] = created;
        return ctx.json(created.toJson(), statusCode: HttpStatus.created);
      });

      router.get('/projects/{id}', (ctx) async {
        final id = ctx.mustGetParam<String>('id');
        final project = await ctx.fetchOr404(
          () async => projects[id],
          message: 'Project not found',
        );
        try {
          await Haigate.authorize('project.view', ctx: ctx, payload: project);
        } on GateViolation {
          return ctx.json({
            'error': 'forbidden',
          }, statusCode: HttpStatus.forbidden);
        }
        return ctx.json(project.toJson());
      });

      router.put('/projects/{id}', (ctx) async {
        final id = ctx.mustGetParam<String>('id');
        final project = await ctx.fetchOr404(
          () async => projects[id],
          message: 'Project not found',
        );
        try {
          await Haigate.authorize('project.update', ctx: ctx, payload: project);
        } on GateViolation {
          return ctx.json({
            'error': 'forbidden',
          }, statusCode: HttpStatus.forbidden);
        }

        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final updated = project.copyWith(name: payload['name']?.toString());
        projects[id] = updated;
        return ctx.json(updated.toJson());
      });

      router.get('/users', (ctx) async {
        return ctx.json({'data': users.values.toList()});
      });

      router.get('/users/{id}', (ctx) async {
        final id = ctx.mustGetParam<String>('id');
        final user = await ctx.fetchOr404(
          () async => users[id],
          message: 'User not found',
        );
        return ctx.json(user);
      });

      router.post('/users', (ctx) async {
        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final id = (users.length + 1).toString();
        final created = {
          'id': id,
          'name': payload['name'] ?? 'user-$id',
          'email': payload['email'] ?? 'user$id@example.com',
        };
        users[id] = created;
        return ctx.json(created, statusCode: HttpStatus.created);
      });
    },
  );

  return engine;
}
