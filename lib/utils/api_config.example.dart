

class ApiConfig {
  // Groq API Configuration (Medical Chatbot)
  static const String baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String apiKey = 'YOUR_GROQ_API_KEY_HERE';  // ← Replace with your Groq API key
  static const String model = 'llama-3.3-70b-versatile';
  
  // API Request Settings
  static const double temperature = 0.7;
  static const int maxTokens = 2000;
  
  // Edamam API Configuration (Nutrition Analysis)
  static const String edamamAppId = 'YOUR_EDAMAM_APP_ID_HERE';  // ← Replace with your Edamam App ID
  static const String edamamAppKey = 'YOUR_EDAMAM_APP_KEY_HERE';  // ← Replace with your Edamam App Key
  static const String edamamBaseUrl = 'https://api.edamam.com/api/nutrition-details';
  
  // Google Gemini API Configuration (Image Analysis)
  static const String geminiApiKey = 'YOUR_GEMINI_API_KEY_HERE';  // ← Replace with your Gemini API key
  static const String geminiModel = 'gemini-2.5-flash';
}
