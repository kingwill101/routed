import 'dart:async';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

Future<void> main(List<String> args) async {
  final engine = await createTodoApp();

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 4000;
  stdout.writeln('Todo demo listening on http://localhost:$port/');
  stdout.writeln(
    'Open multiple browser windows to see Turbo Streams in action.',
  );
  await engine.serve(port: port);
}

Future<Engine> createTodoApp({
  Directory? root,
  TodoRepository? repository,
  TurboStreamHub? hub,
}) async {
  final baseDir = root ?? Directory(p.dirname(Platform.script.toFilePath()));
  final templatesPath = p.join(baseDir.path, 'templates');
  final assetsPath = p.join(baseDir.path, 'public');

  final todoHub = hub ?? TurboStreamHub();
  final todoRepository = repository ?? TodoRepository.seed();

  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
  );

  engine.useViewEngine(LiquidViewEngine(directory: templatesPath));

  final assetsRouter = Router()..static('/assets', assetsPath);
  engine.use(assetsRouter);

  engine.ws('/ws/todos', TurboStreamSocketHandler(hub: todoHub));

  engine.get('/', (ctx) => _renderHome(ctx, todoRepository));
  engine.get('/todos', (ctx) => _renderList(ctx, todoRepository));
  engine.get('/todos/new', (ctx) => _renderForm(ctx));
  engine.get('/todos/{id}', (ctx) => _renderDetail(ctx, todoRepository));

  engine.post('/todos', (ctx) => _create(ctx, todoRepository, todoHub));
  engine.post(
    '/todos/{id}/toggle',
    (ctx) => _toggle(ctx, todoRepository, todoHub),
  );
  engine.post(
    '/todos/{id}/delete',
    (ctx) => _delete(ctx, todoRepository, todoHub),
  );

  await engine.initialize();
  return engine;
}

Future<Response> _renderHome(
  EngineContext ctx,
  TodoRepository repository,
) async {
  final todos = repository.all();
  final selectedId = int.tryParse(ctx.request.queryParameters['todo'] ?? '');
  final selected = selectedId != null
      ? repository.find(selectedId)
      : (todos.isNotEmpty ? todos.first : null);
  final signedTodosStream = signTurboStreamName(const ['todos']);
  final streamSourceTag = turboStreamSourceTag(streamables: const ['todos']);

  final listFrame = await _renderListFrame(
    ctx,
    repository,
    selectedId: selected?.id,
  );
  final detailFrame = await _renderDetailFrame(ctx, selected);
  final formFrame = await _renderFormFrame(
    ctx,
    values: const {'title': '', 'notes': ''},
    errors: const [],
  );

  final html = await _renderTemplate(
    ctx,
    'home.liquid',
    data: {
      'signed_stream': signedTodosStream,
      'stream_source': streamSourceTag,
      'list_frame': listFrame,
      'detail_frame': detailFrame,
      'form_frame': formFrame,
    },
  );

  return ctx.turboHtml(html);
}

Future<Response> _renderList(
  EngineContext ctx,
  TodoRepository repository,
) async {
  final selectedId = int.tryParse(ctx.request.queryParameters['todo'] ?? '');
  final frameHtml = await _renderListFrame(
    ctx,
    repository,
    selectedId: selectedId,
  );

  if (ctx.turbo.isFrameRequest) {
    return ctx.turboFrame(frameHtml);
  }
  return ctx.turboHtml(frameHtml);
}

Future<Response> _renderForm(EngineContext ctx) async {
  final frameHtml = await _renderFormFrame(
    ctx,
    values: const {'title': '', 'notes': ''},
    errors: const [],
  );

  if (ctx.turbo.isFrameRequest) {
    return ctx.turboFrame(frameHtml);
  }
  return ctx.turboHtml(frameHtml);
}

Future<Response> _renderDetail(
  EngineContext ctx,
  TodoRepository repository,
) async {
  final id = int.tryParse('${ctx.params['id'] ?? ''}');
  final todo = id != null ? repository.find(id) : null;
  final frameHtml = await _renderDetailFrame(ctx, todo);

  if (ctx.turbo.isFrameRequest) {
    return ctx.turboFrame(frameHtml);
  }
  return ctx.turboHtml(frameHtml);
}

Future<Response> _create(
  EngineContext ctx,
  TodoRepository repository,
  TurboStreamHub hub,
) async {
  final title = (await ctx.postForm('title')).trim();
  final notes = (await ctx.postForm('notes')).trim();

  if (title.isEmpty) {
    final formFrame = await _renderFormFrame(
      ctx,
      values: {'title': title, 'notes': notes},
      errors: const ['Please provide a title for the task.'],
    );

    final fragments = [
      turboStreamReplace(target: 'todo_form', html: formFrame),
    ];

    return ctx.turboStream(joinTurboStreams(fragments));
  }

  final todo = repository.create(
    title: title,
    notes: notes.isEmpty ? null : notes,
  );

  final listFrame = await _renderListFrame(
    ctx,
    repository,
    selectedId: todo.id,
  );
  final detailFrame = await _renderDetailFrame(ctx, todo);
  final formFrame = await _renderFormFrame(
    ctx,
    values: const {'title': '', 'notes': ''},
    errors: const [],
  );

  final fragments = [
    turboStreamReplace(target: 'todo_list', html: listFrame),
    turboStreamReplace(target: 'todo_detail', html: detailFrame),
    turboStreamReplace(target: 'todo_form', html: formFrame),
  ];

  hub.broadcast('todos', fragments);

  if (!ctx.turbo.isStreamRequest) {
    return ctx.turboSeeOther('/');
  }

  return ctx.turboStream(joinTurboStreams(fragments));
}

Future<Response> _toggle(
  EngineContext ctx,
  TodoRepository repository,
  TurboStreamHub hub,
) async {
  final id = int.tryParse('${ctx.params['id'] ?? ''}');
  if (id == null) {
    return ctx.turboSeeOther('/');
  }

  final todo = repository.toggle(id);
  final listFrame = await _renderListFrame(
    ctx,
    repository,
    selectedId: todo?.id,
  );
  final detailFrame = await _renderDetailFrame(ctx, todo);

  final fragments = [
    turboStreamReplace(target: 'todo_list', html: listFrame),
    turboStreamReplace(target: 'todo_detail', html: detailFrame),
  ];

  hub.broadcast('todos', fragments);

  if (!ctx.turbo.isStreamRequest) {
    return ctx.turboSeeOther('/');
  }

  return ctx.turboStream(joinTurboStreams(fragments));
}

Future<Response> _delete(
  EngineContext ctx,
  TodoRepository repository,
  TurboStreamHub hub,
) async {
  final id = int.tryParse('${ctx.params['id'] ?? ''}');
  if (id == null) {
    return ctx.turboSeeOther('/');
  }

  final removed = repository.delete(id);
  if (!removed) {
    if (!ctx.turbo.isStreamRequest) {
      return ctx.turboSeeOther('/');
    }
    return ctx.turboStream('');
  }

  final remaining = repository.all();
  final nextSelected = remaining.isNotEmpty ? remaining.first : null;

  final listFrame = await _renderListFrame(
    ctx,
    repository,
    selectedId: nextSelected?.id,
  );
  final detailFrame = await _renderDetailFrame(ctx, nextSelected);

  final fragments = [
    turboStreamReplace(target: 'todo_list', html: listFrame),
    turboStreamReplace(target: 'todo_detail', html: detailFrame),
  ];

  hub.broadcast('todos', fragments);

  if (!ctx.turbo.isStreamRequest) {
    return ctx.turboSeeOther('/');
  }

  return ctx.turboStream(joinTurboStreams(fragments));
}

String _wrapFrame(String id, String inner) =>
    '<turbo-frame id="$id">$inner</turbo-frame>';

Future<String> _renderListFrame(
  EngineContext ctx,
  TodoRepository repository, {
  int? selectedId,
}) async {
  final content = await _renderListContent(
    ctx,
    repository,
    selectedId: selectedId,
  );
  return _wrapFrame('todo_list', content);
}

Future<String> _renderFormFrame(
  EngineContext ctx, {
  required Map<String, Object?> values,
  required List<String> errors,
}) async {
  final content = await _renderFormContent(ctx, values: values, errors: errors);
  return _wrapFrame('todo_form', content);
}

Future<String> _renderDetailFrame(EngineContext ctx, Todo? todo) async {
  final content = await _renderDetailContent(ctx, todo);
  return _wrapFrame('todo_detail', content);
}

Future<String> _renderListContent(
  EngineContext ctx,
  TodoRepository repository, {
  int? selectedId,
}) async {
  final todos = repository.all();
  final todosData = todos
      .map((todo) => todo.toMap(selectedId: selectedId))
      .toList(growable: false);

  return _renderTemplate(
    ctx,
    'todos/list.liquid',
    data: {
      'todos_list': todosData,
      'selected_id': selectedId,
      'todo_count': todosData.length,
    },
  );
}

Future<String> _renderFormContent(
  EngineContext ctx, {
  required Map<String, Object?> values,
  required List<String> errors,
}) {
  return _renderTemplate(
    ctx,
    'todos/form.liquid',
    data: {'values': values, 'errors': errors},
  );
}

Future<String> _renderDetailContent(EngineContext ctx, Todo? todo) {
  return _renderTemplate(
    ctx,
    'todos/detail.liquid',
    data: {'todo': todo?.toMap()},
  );
}

Future<String> _renderTemplate(
  EngineContext ctx,
  String templateName, {
  Map<String, dynamic> data = const {},
}) async {
  final engine = ctx.engine;
  if (engine == null || engine.viewEngine == null) {
    throw StateError('View engine not available for template rendering');
  }
  return engine.viewEngine.renderFile(templateName, data);
}

class Todo {
  Todo({
    required this.id,
    required this.title,
    required this.createdAt,
    this.notes,
    this.completed = false,
  });

  final int id;
  String title;
  String? notes;
  bool completed;
  final DateTime createdAt;

  Map<String, Object?> toMap({int? selectedId}) {
    return {
      'id': id,
      'title': title,
      'notes': notes,
      'completed': completed,
      'created_at': createdAt.toIso8601String(),
      'formatted_created_at': DateFormat.yMMMd().format(createdAt.toLocal()),
      'is_selected': selectedId == id,
    };
  }
}

class TodoRepository {
  TodoRepository._(this._todos, this._nextId);

  final List<Todo> _todos;
  int _nextId;

  factory TodoRepository.seed() {
    final now = DateTime.now();
    final seed = <Todo>[
      Todo(
        id: 1,
        title: 'Sketch landing page',
        notes: 'Rough draft for the marketing site hero',
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      Todo(
        id: 2,
        title: 'Wire up Turbo Streams',
        notes: 'Hook the todo list to routed_hotwire',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
      Todo(
        id: 3,
        title: 'Polish copy',
        notes: 'Review CTA wording with the team',
        createdAt: now.subtract(const Duration(minutes: 1)),
        completed: true,
      ),
    ];
    seed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return TodoRepository._(seed, seed.length + 1);
  }

  List<Todo> all() {
    final copy = List<Todo>.from(_todos);
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  Todo? find(int id) {
    for (final todo in _todos) {
      if (todo.id == id) {
        return todo;
      }
    }
    return null;
  }

  Todo create({required String title, String? notes}) {
    final todo = Todo(
      id: _nextId++,
      title: title,
      notes: notes,
      createdAt: DateTime.now(),
    );
    _todos.add(todo);
    return todo;
  }

  Todo? toggle(int id) {
    final todo = find(id);
    if (todo == null) return null;
    final updated = Todo(
      id: todo.id,
      title: todo.title,
      notes: todo.notes,
      completed: !todo.completed,
      createdAt: todo.createdAt,
    );
    final index = _todos.indexWhere((element) => element.id == id);
    if (index != -1) {
      _todos[index] = updated;
    }
    return updated;
  }

  bool delete(int id) {
    final index = _todos.indexWhere((todo) => todo.id == id);
    if (index == -1) return false;
    _todos.removeAt(index);
    return true;
  }
}
