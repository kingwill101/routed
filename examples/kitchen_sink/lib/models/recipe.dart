import 'dart:convert';

import 'package:ormed/ormed.dart';

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

  factory Recipe.fromRow(AdHocRow row) {
    final rawIngredients = row['ingredients']?.toString() ?? '[]';
    return Recipe(
      id: row['id']!.toString(),
      name: row['name']!.toString(),
      description: row['description']?.toString() ?? '',
      ingredients: (jsonDecode(rawIngredients) as List).cast<String>(),
      instructions: row['instructions']?.toString() ?? '',
      prepTime: (row['prep_time'] as num?)?.toInt() ?? 0,
      cookTime: (row['cook_time'] as num?)?.toInt() ?? 0,
      category: RecipeCategory.values.byName(row['category']!.toString()),
      image: row['image']?.toString() ?? '',
    );
  }

  Map<String, Object?> toStorage() => {
    'id': id,
    'name': name,
    'description': description,
    'ingredients': jsonEncode(ingredients),
    'instructions': instructions,
    'prep_time': prepTime,
    'cook_time': cookTime,
    'category': category.name,
    'image': image,
  };

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
