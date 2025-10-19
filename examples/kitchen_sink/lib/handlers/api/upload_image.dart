import 'package:kitchen_sink_example/consts.dart';
import 'package:routed/routed.dart';

Future<Object> uploadImage(EngineContext ctx) async {
  final id = ctx.param('id');

  try {
    final recipeIndex = recipes.indexWhere((r) => r.id == id);
    if (recipeIndex == -1) {
      return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
    }

    final imageFile = await ctx.formFile('image');

    if (imageFile == null) {
      return ctx.string('No image uploaded', statusCode: HttpStatus.badRequest);
    }
    final imageName = '${uuid.v4()}.${imageFile.filename.split('.').last}';
    final filePath = 'public/images/$imageName';
    await ctx.saveUploadedFile(imageFile, filePath);
    // For simplicity, we'll just store the filename and type.
    recipes[recipeIndex] = recipes[recipeIndex].copyWith(
      image: '/images/$imageName',
    );
    ctx.removeCache(
      '${kRecipeCacheKeyPrefix}_$id',
      store: 'array',
    ); // Invalidate the recipe cache
    ctx.removeCache(
      kAllRecipesCacheKey,
      store: 'array',
    ); // Invalidate the cache
    return ctx.redirect('/');
  } catch (e) {
    return ctx.string(
      'Error: ${e.toString()}',
      statusCode: HttpStatus.badRequest,
    );
  }
}
