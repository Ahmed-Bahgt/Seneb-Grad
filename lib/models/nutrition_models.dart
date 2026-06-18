// Nutrition Facts Model
class NutritionFact {
  final String nutrient;
  final double amount;
  final double dailyValuePercent;
  final String unit;

  NutritionFact({
    required this.nutrient,
    required this.amount,
    required this.dailyValuePercent,
    required this.unit,
  });
}

// Ingredient Breakdown Model
class IngredientBreakdown {
  final String ingredient;
  final double weight;
  final double calories;
  final double carbs;
  final double protein;
  final double fat;

  IngredientBreakdown({
    required this.ingredient,
    required this.weight,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });
}

// Chat Message Model
class NutritionChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  NutritionChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

// Nutrition Analysis Result Model
class NutritionAnalysisResult {
  final List<NutritionFact> nutritionFacts;
  final List<IngredientBreakdown> ingredientBreakdown;
  final String ingredientsDetected;
  final Map<String, dynamic> rawEdamamData;

  NutritionAnalysisResult({
    required this.nutritionFacts,
    required this.ingredientBreakdown,
    required this.ingredientsDetected,
    required this.rawEdamamData,
  });
}
