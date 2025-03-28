enum RecipeCategory { breakfast, lunch, dinner, dessert }

class Recipe {
  final String id;
  final String name;
  final String description;
  final List<String> ingredients;
  final String instructions;
  final int prepTime;
  final int cookTime;
  final RecipeCategory category;
  final String image;

  Recipe({
    required this.id,
    required this.name,
    required this.description,
    required this.ingredients,
    required this.instructions,
    required this.prepTime,
    required this.cookTime,
    required this.category,
    required this.image,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'ingredients': ingredients,
        'instructions': instructions,
        'prepTime': prepTime,
        'cookTime': cookTime,
        'category': category.name,
        'image': image,
      };

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      ingredients: List<String>.from(json['ingredients'] as List),
      instructions: json['instructions'] as String,
      prepTime: json['prepTime'] as int,
      cookTime: json['cookTime'] as int,
      category: RecipeCategory.values.byName(json['category']),
      image: json['image'] as String,
    );
  }

  Recipe copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? ingredients,
    String? instructions,
    int? prepTime,
    int? cookTime,
    RecipeCategory? category,
    String? image,
  }) {
    return Recipe(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ingredients: ingredients ?? this.ingredients,
      instructions: instructions ?? this.instructions,
      prepTime: prepTime ?? this.prepTime,
      cookTime: cookTime ?? this.cookTime,
      category: category ?? this.category,
      image: image ?? this.image,
    );
  }
}
