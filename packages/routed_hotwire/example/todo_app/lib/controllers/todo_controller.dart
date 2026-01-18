import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

import '../repositories/todo_repository.dart';

class TodoController {
  TodoController({required this.repository, required this.hub});

  final TodoRepository repository;
  final TurboStreamHub hub;

  Future<Response> home(EngineContext ctx) => _renderHome(ctx, repository);

  Future<Response> list(EngineContext ctx) => _renderList(ctx, repository);

  Future<Response> form(EngineContext ctx) => _renderForm(ctx);

  Future<Response> detail(EngineContext ctx) => _renderDetail(ctx, repository);

  Future<Response> create(EngineContext ctx) => _create(ctx, repository, hub);

  Future<Response> toggle(EngineContext ctx) => _toggle(ctx, repository, hub);

  Future<Response> delete(EngineContext ctx) => _delete(ctx, repository, hub);
}

Future<Response> _renderHome(
  EngineContext ctx,
  TodoRepository repository,
) async {
  final todos = repository.all();
  final selectedId = int.tryParse(ctx.query('todo')?.toString() ?? '');
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
  final selectedId = int.tryParse(ctx.query('todo')?.toString() ?? '');
  final frameHtml = await _renderListFrame(
    ctx,
    repository,
    selectedId: selectedId,
  );
  return ctx.turboHtml(frameHtml);
}

Future<Response> _renderForm(EngineContext ctx) async {
  final frameHtml = await _renderFormFrame(
    ctx,
    values: const {'title': '', 'notes': ''},
    errors: const [],
  );
  return ctx.turboHtml(frameHtml);
}

Future<Response> _renderDetail(
  EngineContext ctx,
  TodoRepository repository,
) async {
  final id = int.tryParse('${ctx.params['id'] ?? ''}');
  final todo = id != null ? repository.find(id) : null;
  final frameHtml = await _renderDetailFrame(ctx, todo);
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
    return ctx.turboSeeOther('/?todo=${todo?.id ?? ''}');
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

  final deleted = repository.delete(id);
  final listFrame = await _renderListFrame(ctx, repository);
  final detailFrame = await _renderDetailFrame(ctx, null);

  final fragments = [
    turboStreamReplace(target: 'todo_list', html: listFrame),
    turboStreamReplace(target: 'todo_detail', html: detailFrame),
  ];

  hub.broadcast('todos', fragments);

  if (!ctx.turbo.isStreamRequest) {
    return ctx.turboSeeOther('/');
  }

  final responseFragments = <String>[
    turboStreamReplace(target: 'todo_list', html: listFrame),
  ];

  if (deleted != null) {
    responseFragments.add(turboStreamRemove(target: 'todo_${deleted.id}'));
    responseFragments.add(
      turboStreamReplace(target: 'todo_detail', html: detailFrame),
    );
  }

  return ctx.turboStream(joinTurboStreams(responseFragments));
}

Future<String> _renderListFrame(
  EngineContext ctx,
  TodoRepository repository, {
  int? selectedId,
}) async {
  final todos = repository.all();
  final content = await _renderTemplate(
    ctx,
    'todos/list.liquid',
    data: {
      'todos_list': todos
          .map((todo) => todo.toMap(selectedId: selectedId))
          .toList(),
      'selected_id': selectedId,
    },
  );

  return _renderTemplate(
    ctx,
    'todos/list_frame.liquid',
    data: {'content': content},
  );
}

Future<String> _renderDetailFrame(EngineContext ctx, Todo? todo) async {
  final content = await _renderDetailContent(ctx, todo);
  return _renderTemplate(
    ctx,
    'todos/detail_frame.liquid',
    data: {'content': content},
  );
}

Future<String> _renderFormFrame(
  EngineContext ctx, {
  required Map<String, String> values,
  required List<String> errors,
}) async {
  final content = await _renderTemplate(
    ctx,
    'todos/form.liquid',
    data: {'values': values, 'errors': errors},
  );

  return _renderTemplate(
    ctx,
    'todos/form_frame.liquid',
    data: {'content': content},
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
  if (engine == null) {
    throw StateError('View engine not available for template rendering');
  }
  return engine.viewEngine.renderFile(templateName, data);
}
