import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Response> deleteRecipe(EngineContext ctx) async {
  final id = ctx.mustGetParam('id');

  try {
    if (!await RecipeService.delete(id)) {
      return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
    }
    return ctx.string('Recipe deleted', statusCode: HttpStatus.noContent);
  } catch (e) {
    return ctx.string(
      'Error deleting recipe',
      statusCode: HttpStatus.internalServerError,
    );
  }
}
