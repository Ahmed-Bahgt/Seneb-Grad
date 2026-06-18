import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/medical_chat_message.dart';
import '../../services/sql_medical_service.dart';
import '../../utils/theme_provider.dart';

class MedicalChatbotScreen extends StatefulWidget {
  const MedicalChatbotScreen({super.key});

  @override
  State<MedicalChatbotScreen> createState() => _MedicalChatbotScreenState();
}

class _MedicalChatbotScreenState extends State<MedicalChatbotScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SqlMedicalService _service = SqlMedicalService();

  // Chat Tab
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<MedicalChatMessage> _messages = [];
  bool _chatLoading = false;

  // Clinical Case Tab
  final TextEditingController _symptomsCtrl = TextEditingController();
  final TextEditingController _historyCtrl = TextEditingController();
  String _clinicalResult = '';
  List<PubMedSource> _clinicalSources = [];
  bool _clinicalLoading = false;

  // Medical Term Tab
  final TextEditingController _termCtrl = TextEditingController();
  String _termResult = '';
  List<PubMedSource> _termSources = [];
  bool _termLoading = false;

  // Quick Reference Tab
  String? _selectedTopic;
  String _refResult = '';
  List<PubMedSource> _refSources = [];
  bool _refLoading = false;

  static const _quickTopics = [
    'Normal vital signs for adults',
    'Common drug interactions with warfarin',
    'Diagnostic criteria for hypertension',
    'CDC vaccination schedule',
    'ACLS algorithms overview',
    'Common antibiotic classifications',
    'Diabetes mellitus management guidelines',
    'Chest pain differential diagnosis',
  ];

  static const _primary = Color(0xFF00BCD4);
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(user.uid)
          .collection('MedicalChatHistory')
          .orderBy('timestamp')
          .get();

      if (mounted && snapshot.docs.isNotEmpty) {
        setState(() {
          _messages.clear();
          for (var doc in snapshot.docs) {
            final data = doc.data();
            _messages.add(MedicalChatMessage(
              text: data['text'],
              isUser: data['isUser'],
              usedRag: data['usedRag'] ?? false,
            ));
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error loading medical chat history: $e');
    }
  }

  Future<void> _saveMessage(String text, bool isUser, {bool usedRag = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(user.uid)
          .collection('MedicalChatHistory')
          .add({
        'text': text,
        'isUser': isUser,
        'usedRag': usedRag,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving medical chat message: $e');
    }
  }

  Future<void> _clearHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(user.uid)
          .collection('MedicalChatHistory')
          .get();
      
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
      
      setState(() => _messages.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat history cleared')),
      );
    } catch (e) {
      _snack('Failed to clear history: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    _symptomsCtrl.dispose();
    _historyCtrl.dispose();
    _termCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  // ── Chat ──────────────────────────────────────────────────────────────────
  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _chatLoading) return;
    _chatCtrl.clear();

    setState(() {
      _messages.add(MedicalChatMessage(text: text, isUser: true));
      _messages.add(MedicalChatMessage(text: '', isUser: false, isLoading: true));
      _chatLoading = true;
    });
    _scrollToBottom();

    try {
      final result = await _service.chat(text);
      final responseText = result['response'] ?? 'No response received.';
      setState(() {
        _messages.removeLast();
        _messages.add(MedicalChatMessage(
          text: responseText,
          isUser: false,
        ));
      });
      // Save both messages
      _saveMessage(text, true);
      _saveMessage(responseText, false);
    } catch (e) {
      setState(() => _messages.removeLast());
      _snack(e.toString());
    } finally {
      setState(() => _chatLoading = false);
      _scrollToBottom();
    }
  }

  // ── Clinical Case ─────────────────────────────────────────────────────────
  Future<void> _analyzeCase() async {
    if (_symptomsCtrl.text.trim().isEmpty) {
      _snack('Please enter symptoms.');
      return;
    }
    setState(() {
      _clinicalLoading = true;
      _clinicalResult = '';
      _clinicalSources = [];
    });
    try {
      final result = await _service.chat(
        "Symptoms: ${_symptomsCtrl.text.trim()}\nHistory: ${_historyCtrl.text.trim()}",
        type: 'clinical'
      );
      setState(() {
        _clinicalResult = result['response'] ?? 'No analysis available.';
      });
    } catch (e) {
      _snack(e.toString());
    } finally {
      setState(() => _clinicalLoading = false);
    }
  }

  // ── Medical Term ──────────────────────────────────────────────────────────
  Future<void> _explainTerm() async {
    if (_termCtrl.text.trim().isEmpty) {
      _snack('Please enter a medical term.');
      return;
    }
    setState(() {
      _termLoading = true;
      _termResult = '';
      _termSources = [];
    });
    try {
      final result = await _service.chat(_termCtrl.text.trim(), type: 'terms');
      setState(() {
        _termResult = result['response'] ?? 'Explanation unavailable.';
      });
    } catch (e) {
      _snack(e.toString());
    } finally {
      setState(() => _termLoading = false);
    }
  }

  // ── Quick Reference ───────────────────────────────────────────────────────
  Future<void> _getReference() async {
    if (_selectedTopic == null) {
      _snack('Please select a topic.');
      return;
    }
    setState(() {
      _refLoading = true;
      _refResult = '';
      _refSources = [];
    });
    try {
      final result = await _service.chat(_selectedTopic!);
      setState(() {
        _refResult = result['response'] ?? 'Reference unavailable.';
      });
    } catch (e) {
      _snack(e.toString());
    } finally {
      setState(() => _refLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════════════════════

  Widget _disclaimer() => Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFCC02), width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFF9A825), size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠️ For clinical decision support only. Always verify with licensed physicians.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.brown.shade700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _ragBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science, size: 11, color: _primary),
            SizedBox(width: 3),
            Text(
              'PubMed RAG',
              style: TextStyle(fontSize: 10, color: _primary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  Widget _sourcesWidget(List<PubMedSource> sources) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(
        '📚 ${sources.length} PubMed Source${sources.length > 1 ? 's' : ''}',
        style: const TextStyle(fontSize: 12, color: _primary, fontWeight: FontWeight.w600),
      ),
      children: sources.asMap().entries.map((e) {
        final i = e.key + 1;
        final s = e.value;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CircleAvatar(
            radius: 11,
            backgroundColor: _primary,
            child: Text('$i', style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
          title: Text(s.title, style: const TextStyle(fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${s.journal} · ${s.year} · PMID ${s.pmid}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 14),
            onPressed: () => Clipboard.setData(ClipboardData(text: s.link)),
            tooltip: 'Copy link',
          ),
        );
      }).toList(),
    );
  }

  Widget _card({required String title, required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card(_isDark),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: _primary)),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppTheme.card(_isDark),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB2DFDB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB2DFDB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _primaryBtn({required String label, required VoidCallback? onPressed, bool loading = false, IconData? icon}) =>
      ElevatedButton.icon(
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon ?? Icons.send, size: 18),
        label: Text(loading ? 'Loading...' : label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  // ── Chat Tab ──────────────────────────────────────────────────────────────
  Widget _buildChatTab() {
    return Column(
      children: [
        _disclaimer(),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.medical_services, size: 44, color: _primary),
                        ),
                        const SizedBox(height: 16),
                        const Text('MedGemma AI Assistant',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _primary)),
                        const SizedBox(height: 6),
                        Text('Ask any medical question',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                        const SizedBox(height: 6),
                        _ragBadge(),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildBubble(_messages[i]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _chatCtrl,
                  enabled: !_chatLoading,
                  maxLines: 4,
                  minLines: 1,
                  decoration: _inputDeco('Type your medical question...'),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 22,
                backgroundColor: _chatLoading ? Colors.grey : _primary,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  onPressed: _chatLoading ? null : _sendChat,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(MedicalChatMessage msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 15,
                  backgroundColor: _primary,
                  child: const Icon(Icons.medical_services, color: Colors.white, size: 15),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFFE0F2F1) : AppTheme.card(_isDark),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: msg.isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 60,
                          child: LinearProgressIndicator(
                            backgroundColor: Color(0xFFB2DFDB),
                            color: _primary,
                          ),
                        )
                      : MarkdownBody(
                          data: msg.text,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 14.5, height: 1.5),
                            strong: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 8),
                const CircleAvatar(
                  radius: 15,
                  backgroundColor: Color(0xFF37474F),
                  child: Icon(Icons.person, color: Colors.white, size: 15),
                ),
              ],
            ],
          ),
          if (!isUser && !msg.isLoading && msg.usedRag) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: _ragBadge(),
            ),
            if (msg.ragSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 30, right: 12),
                child: _sourcesWidget(msg.ragSources),
              ),
          ],
        ],
      ),
    );
  }

  // ── Clinical Case Tab ─────────────────────────────────────────────────────
  Widget _buildClinicalTab() => SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _disclaimer(),
            const SizedBox(height: 14),
            _card(
              title: '📋 Clinical Case Analysis',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Patient Symptoms *',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _symptomsCtrl,
                    maxLines: 4,
                    decoration: _inputDeco(
                        'e.g., fever 39°C, chest pain, shortness of breath for 3 days...'),
                  ),
                  const SizedBox(height: 14),
                  const Text('Patient History (Optional)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _historyCtrl,
                    maxLines: 3,
                    decoration: _inputDeco(
                        'e.g., hypertension, diabetes, current medications...'),
                  ),
                  const SizedBox(height: 16),
                  _primaryBtn(
                    label: 'Analyze Case',
                    icon: Icons.biotech,
                    loading: _clinicalLoading,
                    onPressed: _clinicalLoading ? null : _analyzeCase,
                  ),
                ],
              ),
            ),
            if (_clinicalResult.isNotEmpty) ...[
              _card(
                title: '🔬 Evidence-Based Analysis',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MarkdownBody(
                      data: _clinicalResult,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 14, height: 1.6),
                        strong: const TextStyle(fontWeight: FontWeight.bold),
                        h3: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_clinicalSources.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ragBadge(),
                      const SizedBox(height: 4),
                      _sourcesWidget(_clinicalSources),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  // ── Medical Term Tab ──────────────────────────────────────────────────────
  Widget _buildTermTab() => SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _disclaimer(),
            const SizedBox(height: 14),
            _card(
              title: '📚 Medical Term Explainer',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Enter Medical Term',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _termCtrl,
                    decoration: _inputDeco(
                        "e.g., myocardial infarction, edema, ataxia..."),
                    onSubmitted: (_) => _termLoading ? null : _explainTerm(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['myocardial infarction', 'ataxia', 'dyspnea', 'edema', 'sepsis']
                        .map((t) => ActionChip(
                              label: Text(t, style: const TextStyle(fontSize: 11)),
                              backgroundColor: const Color(0xFFE0F2F1),
                              onPressed: () => setState(() => _termCtrl.text = t),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  _primaryBtn(
                    label: 'Explain Term',
                    icon: Icons.menu_book,
                    loading: _termLoading,
                    onPressed: _termLoading ? null : _explainTerm,
                  ),
                ],
              ),
            ),
            if (_termResult.isNotEmpty)
              _card(
                title: '💡 Explanation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MarkdownBody(
                      data: _termResult,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 14, height: 1.6),
                        strong: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_termSources.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ragBadge(),
                      const SizedBox(height: 4),
                      _sourcesWidget(_termSources),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );

  // ── Quick Reference Tab ───────────────────────────────────────────────────
  Widget _buildRefTab() => SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _disclaimer(),
            const SizedBox(height: 14),
            _card(
              title: '⚡ Quick Clinical Reference',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Select Topic',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F9F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFB2DFDB)),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedTopic,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      hint: const Text('Choose a clinical topic...'),
                      items: _quickTopics
                          .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedTopic = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _primaryBtn(
                    label: 'Get Evidence-Based Answer',
                    icon: Icons.search,
                    loading: _refLoading,
                    onPressed: _refLoading ? null : _getReference,
                  ),
                  if (_refResult.isEmpty && !_refLoading) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _quickTopics.take(4).map((t) => ActionChip(
                            label: Text(t, style: const TextStyle(fontSize: 11)),
                            backgroundColor: const Color(0xFFE0F2F1),
                            onPressed: () => setState(() => _selectedTopic = t),
                          )).toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (_refResult.isNotEmpty)
              _card(
                title: '📖 Clinical Reference',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MarkdownBody(
                      data: _refResult,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 14, height: 1.6),
                        strong: const TextStyle(fontWeight: FontWeight.bold),
                        listBullet: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (_refSources.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ragBadge(),
                      const SizedBox(height: 4),
                      _sourcesWidget(_refSources),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _isDark = isDark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.medical_services, size: 20,
                color: isDark ? AppTheme.cyan : Colors.white),
            const SizedBox(width: 8),
            Text('Medical AI Assistant',
                style: TextStyle(
                    fontSize: 17,
                    color: isDark ? AppTheme.text(isDark) : Colors.white)),
          ],
        ),
        backgroundColor: isDark ? AppTheme.dBg : _primary,
        foregroundColor: isDark ? AppTheme.text(isDark) : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 22),
            tooltip: 'Clear history',
            onPressed: _clearHistory,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 22),
            tooltip: 'Clear PubMed cache',
            onPressed: () {
              _service.clearCache();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ PubMed cache cleared')),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorWeight: 3,
          tabs: const [
          Tab(icon: Icon(Icons.chat, size: 17), text: 'Chat'),
          Tab(icon: Icon(Icons.biotech, size: 17), text: 'Clinical Case'),
          Tab(icon: Icon(Icons.book, size: 17), text: 'Medical Term'),
        ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatTab(),
          _buildClinicalTab(),
          _buildTermTab(),
        ],
      ),
    );
  }
}