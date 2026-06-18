import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'egyptian_nutrition_service.dart';

/// Fallback nutrition lookup using OpenFoodFacts (free, no key needed).
/// Returns an [EgyptianFoodRow]-compatible object scaled to 100 g.
class OpenFoodFactsService {
  static const _baseUrl =
      'https://world.openfoodfacts.org/cgi/search.pl';

  Future<EgyptianFoodRow?> lookup(String foodName) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'search_terms': foodName,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '5',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final products = (data['products'] as List?) ?? [];
      if (products.isEmpty) return null;

      // Pick best matching product by name similarity
      Map<String, dynamic>? best;
      double bestScore = 0;
      for (final p in products) {
        final name = ((p['product_name'] as String?) ?? '').toLowerCase();
        if (name.isEmpty) continue;
        final score = _similarity(foodName.toLowerCase(), name);
        if (score > bestScore) {
          bestScore = score;
          best = p as Map<String, dynamic>;
        }
      }
      if (best == null || bestScore < 0.4) return null;

      final n = (best['nutriments'] as Map<String, dynamic>?) ?? {};
      double g(String key) =>
          (n[key] is num) ? (n[key] as num).toDouble() : 0.0;

      return EgyptianFoodRow(
        food: foodName,
        refuse: 0,
        water: g('water_100g'),
        energy: g('energy-kcal_100g'),
        protein: g('proteins_100g'),
        fat: g('fat_100g'),
        ash: 0,
        fiber: g('fiber_100g'),
        carbs: g('carbohydrates_100g'),
        sodium: g('sodium_100g') * 1000, // kg → mg
        potassium: g('potassium_100g') * 1000,
        calcium: g('calcium_100g') * 1000,
        phosphorus: 0,
        magnesium: 0,
        iron: g('iron_100g') * 1000,
        zinc: 0,
        copper: 0,
        vitaminA: 0,
        vitaminC: g('vitamin-c_100g') * 1000,
        thiamin: 0,
        riboflavin: 0,
      );
    } catch (e) {
      debugPrint('[OpenFoodFacts] error for "$foodName": $e');
      return null;
    }
  }

  static double _similarity(String a, String b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - (_levenshtein(a, b) / maxLen);
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
            : 1 +
                [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]]
                    .reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[m][n];
  }
}
