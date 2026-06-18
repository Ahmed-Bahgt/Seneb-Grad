import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'open_food_facts_service.dart';
import 'gemini_service.dart';

// ─────────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────────

/// One row from the Egyptian CSV (per 100 g).
class EgyptianFoodRow {
  final String food;
  final double refuse;
  final double water;
  final double energy;
  final double protein;
  final double fat;
  final double ash;
  final double fiber;
  final double carbs;
  final double sodium;
  final double potassium;
  final double calcium;
  final double phosphorus;
  final double magnesium;
  final double iron;
  final double zinc;
  final double copper;
  final double vitaminA;
  final double vitaminC;
  final double thiamin;
  final double riboflavin;

  const EgyptianFoodRow({
    required this.food,
    required this.refuse,
    required this.water,
    required this.energy,
    required this.protein,
    required this.fat,
    required this.ash,
    required this.fiber,
    required this.carbs,
    required this.sodium,
    required this.potassium,
    required this.calcium,
    required this.phosphorus,
    required this.magnesium,
    required this.iron,
    required this.zinc,
    required this.copper,
    required this.vitaminA,
    required this.vitaminC,
    required this.thiamin,
    required this.riboflavin,
  });

  factory EgyptianFoodRow.fromCsvRow(List<String> cols) {
    double d(int i) => double.tryParse(cols[i].trim()) ?? 0.0;
    return EgyptianFoodRow(
      food: cols[0].trim(),
      refuse: d(1),
      water: d(2),
      energy: d(3),
      protein: d(4),
      fat: d(5),
      ash: d(6),
      fiber: d(7),
      carbs: d(8),
      sodium: d(9),
      potassium: d(10),
      calcium: d(11),
      phosphorus: d(12),
      magnesium: d(13),
      iron: d(14),
      zinc: d(15),
      copper: d(16),
      vitaminA: d(17),
      vitaminC: d(18),
      thiamin: d(19),
      riboflavin: d(20),
    );
  }
}

/// Aggregated nutrition result for a whole meal.
class EgyptianNutritionResult {
  double energy = 0;
  double protein = 0;
  double fat = 0;
  double ash = 0;
  double fiber = 0;
  double carbs = 0;
  double sodium = 0;
  double potassium = 0;
  double calcium = 0;
  double phosphorus = 0;
  double magnesium = 0;
  double iron = 0;
  double zinc = 0;
  double copper = 0;
  double vitaminA = 0;
  double vitaminC = 0;
  double thiamin = 0;
  double riboflavin = 0;
  double water = 0;

  /// Ingredient breakdown list for display.
  final List<Map<String, dynamic>> ingredientRows = [];

  /// List of foods not found in the dataset.
  final List<String> notFound = [];

  void addScaled(EgyptianFoodRow row, double grams) {
    final f = grams / 100.0;
    energy += row.energy * f;
    protein += row.protein * f;
    fat += row.fat * f;
    ash += row.ash * f;
    fiber += row.fiber * f;
    carbs += row.carbs * f;
    sodium += row.sodium * f;
    potassium += row.potassium * f;
    calcium += row.calcium * f;
    phosphorus += row.phosphorus * f;
    magnesium += row.magnesium * f;
    iron += row.iron * f;
    zinc += row.zinc * f;
    copper += row.copper * f;
    vitaminA += row.vitaminA * f;
    vitaminC += row.vitaminC * f;
    thiamin += row.thiamin * f;
    riboflavin += row.riboflavin * f;
    water += row.water * f;
  }

  /// Nutrition facts as ordered list for table display.
  List<MapEntry<String, String>> get tableEntries => [
        MapEntry('ENERGY (Kcal)', energy.toStringAsFixed(1)),
        MapEntry('PROTEIN (g)', protein.toStringAsFixed(1)),
        MapEntry('FAT (g)', fat.toStringAsFixed(1)),
        MapEntry('CARBOHYDRATE (g)', carbs.toStringAsFixed(1)),
        MapEntry('FIBER (g)', fiber.toStringAsFixed(1)),
        MapEntry('SODIUM (mg)', sodium.toStringAsFixed(1)),
        MapEntry('POTASSIUM (mg)', potassium.toStringAsFixed(1)),
        MapEntry('CALCIUM (mg)', calcium.toStringAsFixed(1)),
        MapEntry('PHOSPHORUS (mg)', phosphorus.toStringAsFixed(1)),
        MapEntry('MAGNESIUM (mg)', magnesium.toStringAsFixed(1)),
        MapEntry('IRON (mg)', iron.toStringAsFixed(2)),
        MapEntry('ZINC (mg)', zinc.toStringAsFixed(2)),
        MapEntry('COPPER (mg)', copper.toStringAsFixed(2)),
        MapEntry('VITAMIN A (µg)', vitaminA.toStringAsFixed(1)),
        MapEntry('VITAMIN C (mg)', vitaminC.toStringAsFixed(1)),
        MapEntry('THIAMIN (mg)', thiamin.toStringAsFixed(2)),
        MapEntry('RIBOFLAVIN (mg)', riboflavin.toStringAsFixed(2)),
        MapEntry('WATER (g)', water.toStringAsFixed(1)),
        MapEntry('ASH (g)', ash.toStringAsFixed(1)),
      ];

  /// Simple health score 0–100 matching the notebook's logic.
  int get healthScore {
    int score = 100;
    if (energy > 800) score -= 15;
    if (fat > 35) score -= 15;
    if (carbs > 100) score -= 10;
    if (sodium > 1500) score -= 20;
    if (protein > 20) score += 5;
    return score.clamp(0, 100);
  }
}

// ─────────────────────────────────────────────
//  DETECTED FOOD ITEM (editable quantity)
// ─────────────────────────────────────────────

/// A food item detected from the image.
/// Only [quantity] is mutable; [unit] and [foodName] are locked.
class DetectedFoodItem {
  double quantity;
  final String unit;
  final String foodName;

  DetectedFoodItem({
    required this.quantity,
    required this.unit,
    required this.foodName,
  });

  @override
  String toString() => '${quantity.toStringAsFixed(2)} $unit $foodName';
}

// ─────────────────────────────────────────────
//  MAIN SERVICE
// ─────────────────────────────────────────────

class EgyptianNutritionService {
  static EgyptianNutritionService? _instance;
  factory EgyptianNutritionService() =>
      _instance ??= EgyptianNutritionService._();
  EgyptianNutritionService._();

  /// All rows keyed by lower-case food name.
  final Map<String, EgyptianFoodRow> _db = {};
  bool _loaded = false;

  // ── unit → grams conversion (same as notebook) ──────────────────
  static const Map<String, double> _unitToGrams = {
    'g': 1.0,
    'gram': 1.0,
    'grams': 1.0,
    'kg': 1000.0,
    'oz': 28.35,
    'cup': 180.0,
    'cups': 180.0,
    'tbsp': 15.0,
    'tablespoon': 15.0,
    'tsp': 5.0,
    'teaspoon': 5.0,
    'piece': 100.0,
    'pieces': 100.0,
    'serving': 100.0,
  };

  // ─────────────────────────────────────────────────────────────────
  //  LOAD
  // ─────────────────────────────────────────────────────────────────

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/data/egyptian_nutrition.csv');
    _parseCSV(raw);
    _loaded = true;
  }

  void _parseCSV(String raw) {
    final lines = raw.split('\n');
    // Skip header (line 0)
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cols = line.split(',');
      if (cols.length < 21) continue;
      try {
        final row = EgyptianFoodRow.fromCsvRow(cols);
        final key = row.food.toLowerCase().trim();
        // Keep only the first occurrence (or average — first is fine)
        _db.putIfAbsent(key, () => row);
      } catch (_) {
        // skip malformed rows
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //  FUZZY MATCH  (Levenshtein similarity ≥ 0.70)
  // ─────────────────────────────────────────────────────────────────

  EgyptianFoodRow? _findFood(String query) {
    final q = query.toLowerCase().trim();
    // 1. Exact match
    if (_db.containsKey(q)) return _db[q];

    // 2. Contains match
    for (final key in _db.keys) {
      if (key.contains(q) || q.contains(key)) return _db[key];
    }

    // 3. Levenshtein similarity
    String? bestKey;
    double bestScore = 0;
    for (final key in _db.keys) {
      final score = _similarity(q, key);
      if (score > bestScore) {
        bestScore = score;
        bestKey = key;
      }
    }
    if (bestScore >= 0.70 && bestKey != null) return _db[bestKey];
    return null;
  }

  static int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce(min);
      }
    }
    return dp[m][n];
  }

  static double _similarity(String a, String b) {
    final maxLen = max(a.length, b.length);
    if (maxLen == 0) return 1.0;
    return 1.0 - (_levenshtein(a, b) / maxLen);
  }

  // ─────────────────────────────────────────────────────────────────
  //  COMPUTE NUTRITION
  // ─────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────
  //  COMPUTE NUTRITION (ALIGNED WITH NOTEBOOK)
  // ─────────────────────────────────────────────────────────────────

  Future<EgyptianNutritionResult> computeNutrition(
      List<DetectedFoodItem> items, 
      GeminiService gemini,
      OpenFoodFactsService off) async {
    await ensureLoaded();
    final result = EgyptianNutritionResult();

    for (final item in items) {
      final grams = _toGrams(item.quantity, item.unit);
      final row = _findFood(item.foodName);

      if (row != null) {
        // 1. Found in Egyptian CSV
        result.addScaled(row, grams);
        result.ingredientRows.add({
          'food': item.foodName,
          'weight': grams,
          'energy': (row.energy * grams / 100).toStringAsFixed(2),
          'protein': (row.protein * grams / 100).toStringAsFixed(2),
          'fat': (row.fat * grams / 100).toStringAsFixed(2),
          'carbs': (row.carbs * grams / 100).toStringAsFixed(2),
          'source': 'Local Dataset',
        });
      } else {
        // 2. Fallback to OpenFoodFacts (Notebook Cell 11)
        final offRow = await off.lookup(item.foodName);
        if (offRow != null) {
          result.addScaled(offRow, grams);
          result.ingredientRows.add({
            'food': item.foodName,
            'weight': grams,
            'energy': (offRow.energy * grams / 100).toStringAsFixed(2),
            'protein': (offRow.protein * grams / 100).toStringAsFixed(2),
            'fat': (offRow.fat * grams / 100).toStringAsFixed(2),
            'carbs': (offRow.carbs * grams / 100).toStringAsFixed(2),
            'source': 'OpenFoodFacts',
          });
        } else {
          // 3. Fallback to Gemini Estimation (Notebook Cell 12)
          final estimated = await _geminiFillMissing(item.foodName, grams, gemini);
          if (estimated != null) {
            result.energy += estimated['energy'] ?? 0;
            result.protein += estimated['protein'] ?? 0;
            result.fat += estimated['fat'] ?? 0;
            result.carbs += estimated['carbs'] ?? 0;
            result.sodium += estimated['sodium'] ?? 0;

            result.ingredientRows.add({
              'food': item.foodName,
              'weight': grams,
              'energy': (estimated['energy'] ?? 0).toStringAsFixed(2),
              'protein': (estimated['protein'] ?? 0).toStringAsFixed(2),
              'fat': (estimated['fat'] ?? 0).toStringAsFixed(2),
              'carbs': (estimated['carbs'] ?? 0).toStringAsFixed(2),
              'source': 'AI Estimation',
            });
          } else {
            result.notFound.add(item.foodName);
            result.ingredientRows.add({
              'food': item.foodName,
              'weight': grams,
              'note': 'No data found',
            });
          }
        }
      }
    }

    return result;
  }

  /// Brain of the system: If food isn't in CSV, Gemini estimates it (Matches Notebook Cell 12)
  Future<Map<String, double>?> _geminiFillMissing(
      String food, double grams, GeminiService gemini) async {
    try {
      final prompt = '''You are a nutrition expert.
Estimate nutrition for:
Food: $food
Weight: ${grams}g

Return ONLY JSON:
{
"energy": number,
"protein": number,
"fat": number,
"carbs": number,
"sodium": number
}''';
      
      final res = await gemini.generateText(prompt);
      final text = res.trim();
      
      // Basic JSON cleaning
      final jsonStr = text.substring(text.indexOf('{'), text.lastIndexOf('}') + 1);
      final data = jsonDecode(jsonStr);
      
      return {
        'energy': (data['ENERGY (Kcal)'] ?? data['energy'] ?? 0).toDouble(),
        'protein': (data['PROTEIN (g)'] ?? data['protein'] ?? 0).toDouble(),
        'fat': (data['FAT (g)'] ?? data['fat'] ?? 0).toDouble(),
        'carbs': (data['CARBOHYDRATE (g)'] ?? data['carbs'] ?? 0).toDouble(),
        'sodium': (data['SODIUM (mg)'] ?? data['sodium'] ?? 0).toDouble(),
      };
    } catch (e) {
      debugPrint('Gemini Fallback Error: $e');
      return null;
    }
  }

  static double _toGrams(double qty, String unit) {
    final u = unit.toLowerCase().trim();
    // Use notebook's conversion map (Cell 9)
    return qty * (_unitToGrams[u] ?? 100.0);
  }

  /// Public helper so the screen can convert units for the OFF fallback.
  static double unitGrams(String unit) {
    return _unitToGrams[unit.toLowerCase().trim()] ?? 100.0;
  }

  // ─────────────────────────────────────────────────────────────────
  //  PARSE GEMINI OUTPUT → List<DetectedFoodItem>
  // ─────────────────────────────────────────────────────────────────

  /// Parses Gemini's response like:
  ///   "2 cups pasta\n0.75 cup lentils\n100 g chicken"
  static List<DetectedFoodItem> parseGeminiOutput(String text) {
    final items = <DetectedFoodItem>[];
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

    for (var line in lines) {
      // 1. Clean up only clear list markers like "1- ", "* ", or "1. " 
      // but keep numbers that look like quantities (e.g., "1.5 cups")
      line = line.replaceFirst(RegExp(r'^[\d]+\.\s+'), ''); // matches "1. " but not "1.5"
      line = line.replaceFirst(RegExp(r'^[\-\*]\s+'), '');   // matches "- " or "* "
      
      if (line.isEmpty) continue;

      double qty = 1.0;
      String unit = 'g';
      String foodName = line;

      // 2. Extract Quantity (Decimal or Fraction)
      // Matches 1, 1.5, 0.75, 1/2
      final qtyMatch = RegExp(r'(\d+\.\d+|\d+/\d+|\b\d+\b)').firstMatch(line);
      if (qtyMatch != null) {
        final qtyStr = qtyMatch.group(1)!;
        if (qtyStr.contains('/')) {
          final parts = qtyStr.split('/');
          qty = (double.tryParse(parts[0]) ?? 1.0) / (double.tryParse(parts[1]) ?? 1.0);
        } else {
          qty = double.tryParse(qtyStr) ?? 1.0;
        }
        // Remove the quantity from the string so we can find the unit
        foodName = foodName.replaceFirst(qtyStr, '').trim();
      }

      // 3. Extract Unit
      final unitMatch = RegExp(r'\b(g|grams?|cups?|tbsps?|tablespoons?|tsps?|pieces?|oz|kg|serving)\b', caseSensitive: false)
          .firstMatch(foodName);
      
      if (unitMatch != null) {
        unit = unitMatch.group(1)!.toLowerCase();
        foodName = foodName.replaceFirst(RegExp('\\b$unit\\b', caseSensitive: false), '').trim();
      } else {
        unit = (qty > 5) ? 'g' : 'cup'; // Smarter default
      }

      foodName = foodName.replaceAll(RegExp(r'^[:\-\s]+|[:\-\s]+$'), '').trim();

      if (foodName.isNotEmpty) {
        items.add(DetectedFoodItem(quantity: qty, unit: unit, foodName: foodName));
      }
    }
    return items;
  }
}
