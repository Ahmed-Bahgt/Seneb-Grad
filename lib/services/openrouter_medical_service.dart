import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/medical_chat_message.dart';
import '../utils/api_config.dart';

// ---------------------------------------------------------------------------
// PubMedRAG — mirrors the Python PubMedRAG class in medical-chatbot.ipynb
// Uses NCBI E-utilities (free, no API key required).
// ---------------------------------------------------------------------------
class PubMedRAG {
  static const String _entrezBase =
      'https://eutils.ncbi.nlm.nih.gov/entrez/eutils';
  static const String _email = 'medgemma.chatbot@tamrenatech.app';
  static const String _tool = 'MedGemmaMedicalChatbot';

  // Simple in-memory cache (query → list of sources)
  final Map<String, List<PubMedSource>> _cache = {};

  /// Search PubMed for [query] and return up to [maxResults] article summaries.
  Future<List<PubMedSource>> searchPubMed(
    String query, {
    int maxResults = 3,
  }) async {
    final cacheKey = query.toLowerCase().trim();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      // Step 1 — ESearch: get PMIDs
      final searchUri = Uri.parse(
        '$_entrezBase/esearch.fcgi'
        '?db=pubmed'
        '&term=${Uri.encodeQueryComponent(query)}'
        '&retmax=$maxResults'
        '&sort=relevance'
        '&retmode=json'
        '&email=${Uri.encodeQueryComponent(_email)}'
        '&tool=$_tool',
      );

      final searchRes = await http
          .get(searchUri)
          .timeout(const Duration(seconds: 15));

      if (searchRes.statusCode != 200) return [];

      final searchJson = jsonDecode(searchRes.body);
      final pmids = (searchJson['esearchresult']['idlist'] as List)
          .cast<String>();

      if (pmids.isEmpty) return [];

      // Step 2 — ESummary: get article details
      final summaryUri = Uri.parse(
        '$_entrezBase/esummary.fcgi'
        '?db=pubmed'
        '&id=${pmids.join(',')}'
        '&retmode=json'
        '&email=${Uri.encodeQueryComponent(_email)}'
        '&tool=$_tool',
      );

      final summaryRes = await http
          .get(summaryUri)
          .timeout(const Duration(seconds: 15));

      if (summaryRes.statusCode != 200) return [];

      final summaryJson = jsonDecode(summaryRes.body);
      final result = summaryJson['result'] as Map<String, dynamic>;
      final uids = (result['uids'] as List).cast<String>();

      final sources = <PubMedSource>[];
      for (final uid in uids) {
        final article = result[uid] as Map<String, dynamic>?;
        if (article == null) continue;

        final title = article['title']?.toString() ?? 'Untitled';
        final journal = article['source']?.toString() ?? 'Unknown Journal';
        final pubDate = article['pubdate']?.toString() ?? '';
        final year = pubDate.isNotEmpty ? pubDate.split(' ').first : 'Unknown';

        sources.add(PubMedSource(
          pmid: uid,
          title: title,
          journal: journal,
          year: year,
          link: 'https://pubmed.ncbi.nlm.nih.gov/$uid/',
        ));
      }

      _cache[cacheKey] = sources;
      return sources;
    } catch (_) {
      return [];
    }
  }

  /// Fetch abstract text for a single PMID.
  Future<String> fetchAbstract(String pmid) async {
    try {
      final uri = Uri.parse(
        '$_entrezBase/efetch.fcgi'
        '?db=pubmed'
        '&id=$pmid'
        '&retmode=text'
        '&rettype=abstract'
        '&email=${Uri.encodeQueryComponent(_email)}'
        '&tool=$_tool',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        // Strip header lines, keep the abstract paragraph
        final lines = res.body.split('\n');
        final sb = StringBuffer();
        for (final line in lines) {
          if (line.trim().isNotEmpty) sb.writeln(line.trim());
        }
        final full = sb.toString().trim();
        return full.length > 1500 ? '${full.substring(0, 1500)}...' : full;
      }
    } catch (_) {}
    return '';
  }

  /// Build a RAG context string from PubMed articles (mirrors notebook's
  /// `get_relevant_context`). Returns empty string if no articles found.
  Future<String> buildRagContext(
    String question,
    List<PubMedSource> sources,
  ) async {
    if (sources.isEmpty) return '';

    final contextParts = <String>[];
    final citations = <String>[];

    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      final abstract = await fetchAbstract(src.pmid);
      final snippet = abstract.isNotEmpty
          ? abstract.substring(0, abstract.length.clamp(0, 800))
          : '(Abstract not available)';

      contextParts.add(
        '[Source ${i + 1}]\n'
        'Title: ${src.title}\n'
        'Journal: ${src.journal} (${src.year})\n'
        'Key findings: $snippet',
      );
      citations.add(
        '[${i + 1}] ${src.title} — ${src.journal}, ${src.year} '
        '(PMID: ${src.pmid})',
      );
    }

    final fullContext = contextParts.join('\n\n');
    final citationsText =
        '\n\n**📚 Sources from PubMed:**\n${citations.join('\n')}';
    return fullContext + citationsText;
  }

  /// Enhance a question with PubMed context (mirrors
  /// `enhance_question_with_pubmed`).
  Future<({String enhancedQuestion, List<PubMedSource> sources})>
      enhanceWithPubMed(String question) async {
    final sources = await searchPubMed(question);
    final context = await buildRagContext(question, sources);

    if (context.isNotEmpty) {
      final enhanced = '''
Based on recent PubMed research, answer this medical question:

QUESTION: $question

RELEVANT RESEARCH FROM PUBMED:
$context

Instructions:
1. Answer based on the PubMed research provided above
2. Cite the sources using [Source X] when referencing specific findings
3. If the information is not in the research, say so clearly
4. Provide a clear, evidence-based answer

ANSWER:''';
      return (enhancedQuestion: enhanced, sources: sources);
    } else {
      final fallback = '''
Answer this medical question to the best of your knowledge:

QUESTION: $question

Provide a clear, accurate answer based on standard medical knowledge.

ANSWER:''';
      return (enhancedQuestion: fallback, sources: <PubMedSource>[]);
    }
  }

  void clearCache() => _cache.clear();
}

// ---------------------------------------------------------------------------
// OpenRouterMedicalService — LLM backend + PubMed RAG integration
// ---------------------------------------------------------------------------
class OpenRouterMedicalService {
  static const String _apiKey = ApiConfig.openRouterApiKey;
  static const String _baseUrl =
      'https://openrouter.ai/api/v1/chat/completions';

  /// Free models tried in order — if one hits rate limit, next is used.
  /// All IDs verified on openrouter.ai/models
  static const List<String> _fallbackModels = [
    'openai/gpt-oss-120b:free',
    'z-ai/glm-4.5-air:free',
    'nvidia/nemotron-nano-9b-v2:free',
    'minimax/minimax-m2.5:free',
    'tencent/hy3-preview:free',
  ];

  static const String _systemPrompt =
      'You are MedGemma, a highly experienced and board-certified medical AI assistant. '
      'You provide evidence-based, accurate, and detailed medical information to healthcare professionals. '
      'CRITICAL INSTRUCTIONS FOR MOBILE UI: '
      '1. Be extremely concise and "to the point". '
      '2. NEVER use markdown tables (the mobile screen is too small). '
      '3. Structure your responses clearly with short bullet points. '
      '4. DO NOT output any internal thinking processes, <think> tags, or step-by-step reasoning blocks. '
      '5. Prioritize absolute clinical accuracy. Do NOT guess or hallucinate medical facts. If unsure, state that clearly. '
      'When PubMed research is provided in the context, base your answer primarily on that research '
      'and cite sources using [Source X] notation.';

  final PubMedRAG _rag = PubMedRAG();

  // -------------------------------------------------------------------------
  // Public API — all methods now return a record with the response text
  // and the PubMed sources used.
  // -------------------------------------------------------------------------

  /// General medical chat with PubMed RAG.
  Future<({String response, List<PubMedSource> sources})> sendMessage(
    String userMessage,
  ) async {
    final enhanced = await _rag.enhanceWithPubMed(userMessage);
    final response = await _callApi([
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': enhanced.enhancedQuestion},
    ]);
    return (response: response, sources: enhanced.sources);
  }

  /// Clinical case analysis with PubMed RAG (mirrors `analyze_clinical_case`).
  Future<({String response, List<PubMedSource> sources})> analyzeClinicalCase(
    String symptoms, {
    String patientHistory = '',
  }) async {
    final basePrompt = patientHistory.isNotEmpty
        ? 'Clinical Case Analysis:\n\n'
            'Symptoms: $symptoms\n'
            'Patient History: $patientHistory\n\n'
            'Please provide evidence-based:\n'
            '1. Differential diagnosis\n'
            '2. Recommended diagnostic tests\n'
            '3. Possible treatment approaches\n'
            '4. Red flags to watch for\n'
            '5. Follow-up recommendations'
        : 'Clinical Case Analysis:\n\n'
            'Symptoms: $symptoms\n\n'
            'Please provide evidence-based:\n'
            '1. Differential diagnosis\n'
            '2. Recommended diagnostic tests\n'
            '3. Possible treatment approaches\n'
            '4. Red flags to watch for\n'
            '5. Follow-up recommendations';

    final enhanced = await _rag.enhanceWithPubMed(basePrompt);
    final response = await _callApi([
      {
        'role': 'system',
        'content':
            'You are an expert clinical diagnostician. $_systemPrompt',
      },
      {'role': 'user', 'content': enhanced.enhancedQuestion},
    ], maxTokens: 1024);

    return (response: response, sources: enhanced.sources);
  }

  /// Medical term explanation with PubMed RAG (mirrors `explain_medical_term`).
  Future<({String response, List<PubMedSource> sources})> explainMedicalTerm(
    String term,
  ) async {
    final basePrompt =
        "Explain the medical term '$term' in simple, understandable language.\n\n"
        'Include:\n'
        '- What it means in plain English\n'
        '- Common clinical contexts where it is used\n'
        '- Important implications for patients\n'
        '- Any common misconceptions\n'
        '- Related terms';

    final enhanced = await _rag.enhanceWithPubMed(basePrompt);
    final response = await _callApi([
      {
        'role': 'system',
        'content': 'You are an expert medical educator. $_systemPrompt',
      },
      {'role': 'user', 'content': enhanced.enhancedQuestion},
    ], maxTokens: 700);

    return (response: response, sources: enhanced.sources);
  }

  /// Quick clinical reference (mirrors `quick_reference`).
  Future<({String response, List<PubMedSource> sources})> quickReference(
    String topic,
  ) async {
    final basePrompt = 'Provide a concise clinical reference for: $topic\n\n'
        'Format:\n'
        '• Key points as bullet points\n'
        '• Normal ranges if applicable\n'
        '• Important clinical pearls\n'
        '• Warnings or precautions\n\n'
        'Keep it practical and evidence-based.';

    final enhanced = await _rag.enhanceWithPubMed(basePrompt);
    final response = await _callApi([
      {
        'role': 'system',
        'content':
            'You are an expert clinical reference provider. $_systemPrompt',
      },
      {'role': 'user', 'content': enhanced.enhancedQuestion},
    ], maxTokens: 700);

    return (response: response, sources: enhanced.sources);
  }

  void clearCache() => _rag.clearCache();

  // -------------------------------------------------------------------------
  // Private — OpenRouter HTTP call with auto-retry + fallback models
  // -------------------------------------------------------------------------
  Future<String> _callApi(
    List<Map<String, String>> messages, {
    int maxTokens = 1024,
  }) async {
    Exception? lastError;

    for (final model in _fallbackModels) {
      try {
        final response = await http
            .post(
              Uri.parse(_baseUrl),
              headers: {
                'Authorization': 'Bearer $_apiKey',
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://tamrenatech.app',
                'X-Title': 'TamrenaTech Medical Assistant',
              },
              body: jsonEncode({
                'model': model,
                'messages': messages,
                'max_tokens': maxTokens,
                'temperature': 0.3,
              }),
            )
            .timeout(const Duration(seconds: 90));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final content = decoded['choices']?[0]?['message']?['content'];
          if (content != null && content.toString().isNotEmpty) {
            String text = content.toString().trim();
            // Strip common reasoning tags used by some open-source models
            text = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
            text = text.replaceAll(RegExp(r'<thought>[\s\S]*?</thought>', caseSensitive: false), '');
            text = text.replaceAll(RegExp(r'<unused94>thought[\s\S]*?(?=\n\n|\Z)', caseSensitive: false), '');
            return text.trim();
          }
          return 'No response received from the model.';
        } else if (response.statusCode == 429) {
          // Rate limited — wait 2 seconds then try next model
          await Future.delayed(const Duration(seconds: 2));
          lastError = Exception('Rate limit on $model');
          continue; // try next model
        } else if (response.statusCode == 401) {
          return 'Authentication failed. Please check your API key.';
        } else if (response.statusCode == 503) {
          // Model loading — try next immediately
          lastError = Exception('Model loading: $model');
          continue;
        } else {
          lastError =
              Exception('API Error ${response.statusCode}: ${response.body}');
          continue;
        }
      } on Exception catch (e) {
        lastError = e;
        continue; // try next model on timeout or network error
      }
    }

    // All models failed
    throw lastError ??
        Exception('All models are currently unavailable. Please try again in a minute.');
  }
}
