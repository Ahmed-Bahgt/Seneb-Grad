import os
import re
import json
import time
import pandas as pd
import requests
from rapidfuzz import process, fuzz
from google import genai
from google.genai import types
from PIL import Image
from io import BytesIO

# --- CONFIGURATION ---
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = "gemini-2.5-flash"
DATASET_URL = "https://huggingface.co/datasets/laila-mohamed/egyptian-nutrition-dataset/resolve/main/egyptian_nutrition.csv"

# --- REALISTIC NUTRITION CAPS (per 100g) ---
# Based on real-world max values. Used to detect & reject AI hallucinations.
MAX_PER_100G = {
    "PROTEIN (g)":      35.0,   # Chicken breast ~31g/100g is the real-world max for common foods
    "FAT (g)":          95.0,   # Pure fat (oil/butter) ~100g
    "CARBOHYDRATE (g)": 90.0,   # Sugar ~100g
    "ENERGY (Kcal)":   900.0,   # Cooking oil ~884 kcal
    "FIBER (g)":        30.0,   # Wheat bran ~43g but most foods < 15g
    "SODIUM (mg)":    3000.0,   # Very salty food
    "CALCIUM (mg)":   1200.0,
    "IRON (mg)":        20.0,
    "MAGNESIUM (mg)":  200.0,
    "ZINC (mg)":        15.0,
    "WATER (g)":        98.0,
    "ASH (g)":          10.0,
}

# --- FOOD-SPECIFIC CUP DENSITIES (grams per cup) ---
# A "cup" is 240ml but food density varies
CUP_DENSITY_BY_KEYWORD = {
    "rice":       195,  "pasta":    140,  "spaghetti": 140,
    "macaroni":   140,  "noodle":   140,  "soup":      240,
    "lentil":     200,  "adas":     200,  "bean":      180,
    "fuul":       240,  "ful":      240,  "hummus":    240,
    "salad":       80,  "vegetable": 90,  "leaf":       30,
    "milk":       245,  "yogurt":   245,  "juice":     245,
    "oat":         80,  "flour":    125,  "sugar":     200,
    "oil":        218,  "butter":   227,  "ghee":      205,
    "koshari":    200,  "koshary":  200,
    "default":    150,  # generic fallback
}

# --- FOOD NAME ALIASES ---
# Maps common alternate names -> canonical DB name for better matching
FOOD_ALIASES = {
    # Koshary / Koshari
    "koshary rice":       "rice",
    "koshari rice":       "rice",
    "koshary macaroni":   "macaroni",
    "koshary lentils":    "lentils",
    "koshary":            "koshary",
    # Bread
    "aish":               "bread",
    "eish":               "bread",
    "baladi bread":       "bread baladi",
    "pita":               "bread",
    # Ful / Foul
    "foul":               "fuul",
    "ful medames":        "fuul",
    "fava beans":         "fuul",
    # Chicken
    "grilled chicken":    "chicken grilled",
    "chicken grilled":    "chicken grilled",
    "roasted chicken":    "chicken roasted",
    "chicken breast":     "chicken",
    "chicken thigh":      "chicken",
    "fried chicken":      "chicken fried",
    # Meat
    "beef":               "meat",
    "lamb":               "meat lamb",
    "kofta":              "kofta",
    "kebab":              "kebab",
    # Fish
    "fish":               "fish",
    "bouri":              "mullet fish",
    "tilapia":            "tilapia",
    "sardine":            "sardines",
    # Vegetables
    "molokhia":           "molokhia",
    "bamia":              "okra",
    "okra":               "okra",
    "courgette":          "zucchini",
    "zucchini":           "zucchini",
    "eggplant":           "eggplant",
    "aubergine":          "eggplant",
    "tomato sauce":       "tomato",
    "tomato salsa":       "tomato",
    "salsa":              "tomato",
    # Rice / Grains
    "white rice":         "rice",
    "brown rice":         "rice brown",
    "fried rice":         "rice fried",
    # Eggs
    "scrambled eggs":     "eggs scrambled",
    "fried egg":          "eggs fried",
    "boiled egg":         "eggs boiled",
    # Legumes
    "chickpeas":          "chickpeas",
    "hummus":             "hummus",
    "lentils":            "lentils",
    "brown lentils":      "lentils",
    "red lentils":        "lentils red",
    # Dairy
    "yogurt":             "yogurt",
    "labneh":             "labneh",
    "white cheese":       "cheese white",
    "feta":               "cheese white",
    # Oils / Sauces
    "fried onions":       "onion fried",
    "olive oil":          "olive oil",
    "sunflower oil":      "oil",
    "vinegar sauce":      "vinegar",
    "tahini":             "tahini",
}

class NutritionService:
    def __init__(self):
        self.client = genai.Client(api_key=GEMINI_API_KEY)
        self.df = None
        self.cols = [
            "ENERGY (Kcal)", "PROTEIN (g)", "FAT (g)", "CARBOHYDRATE (g)",
            "SODIUM (mg)", "FIBER (g)", "CALCIUM (mg)", "WATER (g)", "ASH (g)",
            "IRON (mg)", "MAGNESIUM (mg)", "ZINC (mg)"
        ]
        self._load_dataset()

    def _load_dataset(self):
        try:
            print("[*] Loading Egyptian Nutrition Dataset...")
            self.df = pd.read_csv(DATASET_URL, encoding='utf-8')
            self.df["FOOD"] = self.df["FOOD"].str.lower().str.strip()
            for col in self.cols:
                if col not in self.df.columns:
                    self.df[col] = 0
            # Clamp obviously wrong values in dataset itself
            for col, cap in MAX_PER_100G.items():
                if col in self.df.columns:
                    self.df[col] = self.df[col].clip(upper=cap)
            print(f"[SUCCESS] Dataset loaded. {len(self.df)} food items.")
        except Exception as e:
            print(f"[ERROR] Dataset load failed: {e}")
            self.df = pd.DataFrame(columns=["FOOD"] + self.cols)

    def safe_generate(self, contents):
        """Generate content with retry logic using the new google.genai SDK."""
        for attempt in range(3):
            try:
                response = self.client.models.generate_content(
                    model=GEMINI_MODEL,
                    contents=contents
                )
                if response and response.text:
                    return response.text
            except Exception as e:
                print(f"Gemini Error (attempt {attempt + 1}): {e}")
                time.sleep(1.5)
        return ""

    def detect_food_from_image(self, image_bytes):
        """
        Two-pass detection:
        Pass 1: Identify foods from the image.
        Pass 2: Validate and correct portion weights to be realistic.
        """
        detect_prompt = """You are a professional Egyptian dietitian analyzing a food photograph.

TASK: Identify EVERY distinct food item visible on the plate/image.

STRICT OUTPUT FORMAT:
- One food item per line only.
- Format exactly: [weight_grams] g [food_name_in_english]
- Use ONLY grams. NEVER write "cup", "bowl", "plate", "piece", "serving" or any other unit.
- Food name must be in ENGLISH (e.g., "rice", "lentils", "chicken", "bread").

REALISTIC PORTION WEIGHTS for a standard single serving on a 25cm dinner plate:
| Food Category          | Typical weight range |
|------------------------|----------------------|
| Rice / pasta / grains  | 100 - 200 g          |
| Meat / chicken / fish  | 80  - 150 g          |
| Legumes (lentils, beans, chickpeas) | 80 - 180 g |
| Cooked vegetables      | 50  - 150 g          |
| Raw salad              | 40  - 100 g          |
| Bread (per piece)      | 50  - 100 g          |
| Sauce / dip / oil      | 15  -  60 g          |
| Fried onions / garnish | 5   -  20 g          |
| Egg (one large)        | 50  -  60 g          |

EXAMPLES:
For a koshary plate:
150 g rice
80 g macaroni
60 g lentils
50 g chickpeas
40 g tomato sauce
10 g fried onions

For a grilled chicken meal:
130 g chicken grilled
150 g rice
80 g salad
30 g tahini

DO NOT output: intro text, bullets, markdown, explanations, or Arabic text.
If no food is visible, output exactly: NO_FOOD_DETECTED
"""
        try:
            image = Image.open(BytesIO(image_bytes))
            # Resize if too large to save API tokens
            max_size = (1024, 1024)
            image.thumbnail(max_size, Image.LANCZOS)
            img_buffer = BytesIO()
            image.save(img_buffer, format="JPEG", quality=85)
            img_bytes = img_buffer.getvalue()

            # Pass 1: Detect foods
            response = self.client.models.generate_content(
                model=GEMINI_MODEL,
                contents=[
                    detect_prompt,
                    types.Part.from_bytes(data=img_bytes, mime_type="image/jpeg")
                ]
            )
            raw = response.text.strip() if response and response.text else ""
            print(f"[DETECT Pass1]: {raw}")

            if not raw or "NO_FOOD_DETECTED" in raw.upper():
                return raw

            # Pass 2: Validate and refine portion sizes
            validate_prompt = f"""You are a clinical dietitian reviewing a food portion list.

The following list was automatically generated from a food photo:
---
{raw}
---

Your task: Review each item and correct any UNREALISTIC portion weights.
Rules:
- Keep the same foods, just fix weights that are clearly wrong.
- A single meal total should be 300g - 800g (not 50g and not 2000g).
- Sauces, oils, garnishes should be 10-60g.
- Main dishes (rice, meat, pasta) should be 80-200g each.
- Output the CORRECTED list in EXACTLY the same format: [weight] g [food_name]
- One item per line. No extra text.
"""
            val_response = self.client.models.generate_content(
                model=GEMINI_MODEL,
                contents=validate_prompt
            )
            validated = val_response.text.strip() if val_response and val_response.text else raw
            print(f"[DETECT Pass2 validated]: {validated}")
            return validated

        except Exception as e:
            print(f"Detection Error: {e}")
            return ""

    def parse_food_list(self, text):
        if "NO_FOOD_DETECTED" in text.upper():
            return []
        foods = []
        lines = re.split(r'[\n\r]', text.lower())

        for line in lines:
            line = line.strip()
            if not line or len(line) < 3:
                continue

            # Remove list markers (bullets, numbering) but preserve decimals
            line = re.sub(r'^[\*\-\s]+', '', line).strip()
            line = re.sub(r'^\d+\.\s+', '', line).strip()

            qty = 1.0
            unit = "g"
            food_name = line

            # Extract number (including decimals)
            nums = re.findall(r"(\d+\.?\d*)", line)
            if nums:
                qty = float(nums[0])
                line = line.replace(nums[0], "", 1).strip()

            # Extract unit
            unit_match = re.search(
                r"\b(cup|cups|g|gram|grams|ml|oz|piece|pieces|slice|slices)\b",
                line, re.IGNORECASE
            )
            if unit_match:
                found_unit = unit_match.group(0).lower()
                unit = "cup" if "cup" in found_unit else "g"
                line = line.replace(unit_match.group(0), "", 1).strip()

            food_name = line.strip()
            if not food_name:
                food_name = "unknown food"

            # Sanity check on quantity
            if unit == "g" and qty > 1000:
                qty = 200.0   # Hard cap: no single item > 1kg in a meal
            elif unit == "cup" and qty > 5:
                qty = 1.0

            foods.append({"quantity": round(qty, 2), "unit": unit, "food": food_name})

        return foods

    def analyze_meal(self, foods):
        """
        Calculates total nutrition for a list of foods.
        foods: list of dicts, e.g. [{"food": "rice", "quantity": 150, "unit": "g"}]
        Returns: dict with "ingredients", "total", "health_score" keys.
        """
        ingredients_out = []
        total = {c: 0.0 for c in self.cols}

        for item in foods:
            food = item.get("food", "").strip()
            qty = float(item.get("quantity", 0.0))
            unit = item.get("unit", "g").strip()

            if not food:
                continue

            grams = self.convert_to_grams(qty, unit, food)

            # Try DB, then Open Food Facts, then AI estimation
            nutr_100g = None
            
            # 1. DB
            db_row = self._find_in_db(food)
            if db_row is not None:
                nutr_100g = {c: float(db_row.get(c, 0.0) or 0.0) for c in self.cols}
            
            # 2. OFF
            if nutr_100g is None:
                off_data = self._find_in_off(food)
                if off_data is not None:
                    nutr_100g = {c: float(off_data.get(c, 0.0) or 0.0) for c in self.cols}
            
            # 3. AI
            if nutr_100g is None:
                ai_data = self._estimate_with_ai(food)
                if ai_data is not None:
                    nutr_100g = {c: float(ai_data.get(c, 0.0) or 0.0) for c in self.cols}
            
            # Fallback to zeros if everything fails
            if nutr_100g is None:
                nutr_100g = {c: 0.0 for c in self.cols}

            # Validate & clamp the 100g values
            nutr_100g = self._validate_nutrition_per_100g(nutr_100g)

            # Calculate actual nutrition for this item
            item_nutr = {c: round(val_100g * grams / 100.0, 2) for c, val_100g in nutr_100g.items()}

            # Add to total
            for c in self.cols:
                total[c] += item_nutr[c]

            ingredients_out.append({
                "food": food,
                "quantity": qty,
                "unit": unit,
                "grams": round(grams, 2),
                "nutrition": item_nutr
            })

        # Final rounding for total values
        for c in self.cols:
            total[c] = round(total[c], 2)

        health_score = self._calc_score(total)

        return {
            "ingredients": ingredients_out,
            "total": total,
            "health_score": health_score
        }

    def convert_to_grams(self, q, unit, food_name=""):
        """Convert quantity to grams using food-aware cup densities."""
        if unit in ("g", "grams", "gram"):
            return q
        if unit == "cup":
            name_lower = food_name.lower()
            density = CUP_DENSITY_BY_KEYWORD["default"]
            for keyword, g_per_cup in CUP_DENSITY_BY_KEYWORD.items():
                if keyword in name_lower:
                    density = g_per_cup
                    break
            return q * density
        if unit in ("piece", "pieces"):
            return q * 150
        if unit in ("slice", "slices"):
            return q * 30
        if unit == "ml":
            return q * 1.0   # approximate: 1ml ≈ 1g for water-based liquids
        if unit == "oz":
            return q * 28.35
        return q * 100  # unknown unit fallback

    def _validate_nutrition_per_100g(self, data: dict) -> dict:
        """
        Clamp nutrition values to realistic per-100g limits.
        Prevents AI hallucinations like 157g protein per 100g.
        """
        cleaned = {}
        for col in self.cols:
            val = float(data.get(col, 0) or 0)
            cap = MAX_PER_100G.get(col, float("inf"))
            cleaned[col] = min(val, cap)
        return cleaned

    def _resolve_alias(self, name: str) -> str:
        """Map alternate food names to canonical DB-friendly names."""
        name_lower = name.lower().strip()
        if name_lower in FOOD_ALIASES:
            return FOOD_ALIASES[name_lower]
        for alias, canonical in FOOD_ALIASES.items():
            if alias in name_lower:
                return canonical
        return name_lower

    def _find_in_db(self, name):
        if self.df is None or self.df.empty:
            return None

        resolved = self._resolve_alias(name)
        candidates_to_try = list(dict.fromkeys([resolved, name.lower()]))

        for candidate in candidates_to_try:
            # Strategy 1: WRatio (best all-around)
            match = process.extractOne(candidate, self.df["FOOD"], scorer=fuzz.WRatio)
            if match and match[1] >= 82:
                row = self.df[self.df["FOOD"] == match[0]].iloc[0]
                print(f"[DB HIT WRatio] '{name}' -> '{match[0]}' ({match[1]:.0f}%)")
                return row

            # Strategy 2: Token Set Ratio (handles word order differences)
            match2 = process.extractOne(candidate, self.df["FOOD"], scorer=fuzz.token_set_ratio)
            if match2 and match2[1] >= 85:
                row = self.df[self.df["FOOD"] == match2[0]].iloc[0]
                print(f"[DB HIT TokenSet] '{name}' -> '{match2[0]}' ({match2[1]:.0f}%)")
                return row

            # Strategy 3: Partial ratio (good for "brown lentils" -> "lentils")
            match3 = process.extractOne(candidate, self.df["FOOD"], scorer=fuzz.partial_ratio)
            if match3 and match3[1] >= 90:
                row = self.df[self.df["FOOD"] == match3[0]].iloc[0]
                print(f"[DB HIT Partial] '{name}' -> '{match3[0]}' ({match3[1]:.0f}%)")
                return row

        print(f"[DB MISS] '{name}' (resolved: '{resolved}')")
        return None


    def _find_in_off(self, name):
        """Fetch from Open Food Facts — returns per-100g values."""
        try:
            url = (
                f"https://world.openfoodfacts.org/cgi/search.pl"
                f"?search_terms={name}&action=process&json=1&page_size=3"
            )
            r = requests.get(url, timeout=6).json()
            products = r.get("products", [])
            for product in products:
                nutr = product.get("nutriments", {})
                # Only accept products that have at least energy data
                if nutr.get("energy-kcal_100g"):
                    print(f"[OFF HIT] '{name}' → '{product.get('product_name', '?')}'")
                    return {
                        "ENERGY (Kcal)":    nutr.get("energy-kcal_100g", 0),
                        "PROTEIN (g)":      nutr.get("proteins_100g", 0),
                        "FAT (g)":          nutr.get("fat_100g", 0),
                        "CARBOHYDRATE (g)": nutr.get("carbohydrates_100g", 0),
                        "SODIUM (mg)":      nutr.get("sodium_100g", 0) * 1000,  # OFF gives it in g
                        "FIBER (g)":        nutr.get("fiber_100g", 0),
                        "CALCIUM (mg)":     nutr.get("calcium_100g", 0) * 1000,
                        "IRON (mg)":        nutr.get("iron_100g", 0) * 1000,
                        "WATER (g)":        nutr.get("water_100g", 0),
                        "ASH (g)":          0,
                        "MAGNESIUM (mg)":   nutr.get("magnesium_100g", 0) * 1000,
                        "ZINC (mg)":        nutr.get("zinc_100g", 0) * 1000,
                    }
        except Exception as e:
            print(f"[OFF ERROR] {e}")
        return None

    def _estimate_with_ai(self, name):
        """
        Ask Gemini for per-100g nutrition of a food item.
        Prompt is strict to avoid inflated values.
        """
        example = {
            "ENERGY (Kcal)": 130, "PROTEIN (g)": 2.7, "FAT (g)": 0.3,
            "CARBOHYDRATE (g)": 28, "SODIUM (mg)": 1, "FIBER (g)": 0.4,
            "CALCIUM (mg)": 10, "WATER (g)": 68, "ASH (g)": 0.5,
            "IRON (mg)": 0.2, "MAGNESIUM (mg)": 12, "ZINC (mg)": 0.5
        }
        prompt = f"""You are a nutrition database. Return the nutrition facts per 100g of "{name}".

RULES:
- Values must be REALISTIC and scientifically accurate per 100g.
- PROTEIN must NOT exceed 35g per 100g (max for chicken breast is ~31g).
- ENERGY must NOT exceed 900 kcal per 100g.
- Return ONLY valid JSON. No markdown. No extra text.

Example for "white rice (cooked)":
{json.dumps(example)}

Now provide for "{name}":"""

        res = self.safe_generate(prompt)
        print(f"[AI ESTIMATE] '{name}' → {res[:120]}...")
        try:
            cleaned = re.sub(r'```json|```', '', res).strip()
            # Extract JSON object if there's extra text
            json_match = re.search(r'\{.*\}', cleaned, re.DOTALL)
            if json_match:
                return json.loads(json_match.group())
        except Exception as e:
            print(f"[AI PARSE ERROR] {e}")
        # Safe fallback: return zeros (better than wrong data)
        return {c: 0 for c in self.cols}

    def _calc_score(self, t):
        s = 70
        if t["PROTEIN (g)"] > 20:      s += 10
        if t["FIBER (g)"] > 5:         s += 10
        if t["FAT (g)"] > 30:          s -= 15
        if t["SODIUM (mg)"] > 1000:    s -= 15
        if t["ENERGY (Kcal)"] > 800:   s -= 10
        return max(0, min(100, s))

    def chat(self, question, meal_data):
        prompt = f"""
        NUTRITIONIST AI. Context: {json.dumps(meal_data['total'])}
        STRICT RULES:
        1. Be extremely concise and "to the point".
        2. Use bullet points for advice or alternatives.
        3. Structure your response with clear, short headings if needed.
        4. Provide medical-grade nutrition advice only.
        5. USE ONLY EMOJIS for status: ✅ (instead of YES), ❌ (instead of NO), ⚠️ (instead of CAUTION).
        6. Wrap key terms or headings in **bold** for emphasis.
        Question: {question}
        """
        res = self.safe_generate(prompt)
        res = res.replace("CAUTION:", "⚠️").replace("CAUTION", "⚠️")
        res = res.replace("YES:", "✅").replace("YES", "✅")
        res = res.replace("NO:", "❌").replace("NO", "❌")
        return res


nutrition_service = NutritionService()
