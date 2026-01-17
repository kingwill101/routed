import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:routed/routed.dart';

const List<Map<String, String>> recipeCategoryOptions = [
  {'value': 'breakfast', 'label': 'Breakfast'},
  {'value': 'lunch', 'label': 'Lunch'},
  {'value': 'dinner', 'label': 'Dinner'},
  {'value': 'dessert', 'label': 'Dessert'},
];

Map<String, dynamic> buildViewData(
  EngineContext ctx, [
  Map<String, dynamic> overrides = const {},
]) {
  final csrfCookieName = ctx.engineConfig.security.csrfCookieName;
  final csrfToken = ctx.getSession<String>(csrfCookieName) ?? '';

  final errors = _extractErrors(ctx);
  final oldInput = _extractOldInput(ctx);
  final flashes = _extractFlashes(ctx);

  final baseRoutes = <String, String>{
    'home': ctx.route('web.recipe.home'),
    'save': ctx.route('web.recipe.save'),
  };

  final base = <String, dynamic>{
    'app': {'name': 'Kitchen Sink'},
    'routes': baseRoutes,
    'csrf': {'token': csrfToken, 'field': '_csrf', 'header': 'x-csrf-token'},
    'flashes': flashes,
    'errors': errors,
    'old': oldInput,
    'recipe_categories': recipeCategoryOptions,
  };

  final merged = <String, dynamic>{...base, ...overrides};

  if (overrides['routes'] is Map) {
    merged['routes'] = {
      ...baseRoutes,
      ...(overrides['routes'] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    };
  }

  return merged;
}

Map<String, dynamic> recipeView(EngineContext ctx, Recipe recipe) {
  final data = recipe.toJson();
  final id = data['id'] as String;
  final ingredients = (data['ingredients'] as List)
      .map((e) => e.toString())
      .toList();

  return <String, dynamic>{
    ...data,
    'ingredients': ingredients.join(', '),
    'ingredients_list': ingredients,
    'show_url': ctx.route('web.recipe.show', {'id': id}),
    'edit_url': ctx.route('web.recipe.edit', {'id': id}),
    'delete_url': ctx.route('web.recipe.delete', {'id': id}),
  };
}

Map<String, List<String>> _extractErrors(EngineContext ctx) {
  final result = <String, List<String>>{};
  final raw = ctx.getSession<dynamic>('errors');
  ctx.removeSession('errors');

  if (raw is Map) {
    raw.forEach((key, value) {
      if (key == null) return;
      final field = key.toString();
      if (value is List) {
        result[field] = value.map((item) => item.toString()).toList();
      } else if (value != null) {
        result[field] = [value.toString()];
      }
    });
  }

  return result;
}

Map<String, String> _extractOldInput(EngineContext ctx) {
  final result = <String, String>{};
  final raw = ctx.getSession<dynamic>('old');
  ctx.removeSession('old');

  if (raw is Map) {
    raw.forEach((key, value) {
      if (key == null) return;
      final field = key.toString();
      if (value is List) {
        result[field] = value.map((item) => item.toString()).join(', ');
      } else if (value != null) {
        result[field] = value.toString();
      } else {
        result[field] = '';
      }
    });
  }

  return result;
}

List<Map<String, String>> _extractFlashes(EngineContext ctx) {
  final flashes = ctx.getFlashMessages(withCategories: true);
  final messages = <Map<String, String>>[];

  for (final entry in flashes) {
    if (entry is List && entry.isNotEmpty) {
      final category = entry.first?.toString() ?? 'info';
      final message = entry.length > 1 && entry[1] != null
          ? entry[1].toString()
          : '';
      if (message.isNotEmpty) {
        messages.add({'category': category, 'message': message});
      }
    } else if (entry != null) {
      final message = entry.toString();
      if (message.isNotEmpty) {
        messages.add({'category': 'info', 'message': message});
      }
    }
  }

  return messages;
}
