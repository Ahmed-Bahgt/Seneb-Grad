import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tamren_tech/services/sql_nutrition_service.dart';
import 'package:tamren_tech/widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';
import '../../utils/permission_helper.dart';

class NutritionChatbotScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const NutritionChatbotScreen({super.key, this.onBack});

  @override
  State<NutritionChatbotScreen> createState() => _NutritionChatbotScreenState();
}

class _NutritionChatbotScreenState extends State<NutritionChatbotScreen> {
  final _picker = ImagePicker();
  File? _imageFile;
  bool _isBusy = false;
  String? _error;
  
  Map<String, dynamic>? _analysisResult;
  List<dynamic> _ingredients = [];

  Future<void> _pickImage({bool fromCamera = false}) async {
    try {
      final hasPermission = await checkAndRequestUploadPermission(
        context,
        isCamera: fromCamera,
      );
      if (!hasPermission) {
        setState(() => _error = 'Permission denied. Please allow access to continue.');
        return;
      }

      // ── Pick image ───────────────────────────────────────────────
      final picked = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() {
        _imageFile = File(picked.path);
        _analysisResult = null;
        _ingredients = [];
        _error = null;
      });
    } catch (e) {
      debugPrint('Error picking image: $e');
      setState(() => _error = 'Failed to pick image: $e');
    }
  }

  Future<void> _detectFoods() async {
    if (_imageFile == null) return;
    setState(() { _isBusy = true; _error = null; });
    try {
      final response = await sqlNutritionService.analyzeMeal(_imageFile!);
      setState(() {
        _ingredients = List.from(response['analysis']['ingredients']);
        _analysisResult = null; // Don't show dashboard until 'Calculate' is clicked
      });
    } catch (e) {
      setState(() => _error = 'Detection failed: $e');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _calculateFinal() async {
    if (_ingredients.isEmpty) return;
    setState(() { _isBusy = true; _error = null; });
    try {
      final response = await sqlNutritionService.recalculate(_ingredients);
      setState(() {
        _analysisResult = response;
      });
      // Save to history
      _saveToHistory(response);
    } catch (e) {
      setState(() => _error = 'Calculation failed: $e');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _saveToHistory(Map<String, dynamic> result) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('patients')
          .doc(user.uid)
          .collection('NutritionHistory')
          .add({
        'ingredients': _ingredients,
        'total': result['total'],
        'timestamp': FieldValue.serverTimestamp(),
        // Note: we're not saving the local image file to storage here to keep it simple, 
        // but normally we would upload it first.
      });
      _activeSessionId = docRef.id;
    } catch (e) {
      debugPrint('Error saving nutrition history: $e');
    }
  }

  String? _activeSessionId;

  void _reset() {
    setState(() {
      _imageFile = null;
      _analysisResult = null;
      _ingredients = [];
      _error = null;
      _messages.clear();
    });
  }

  void _showResultSheet() {
    final total = _analysisResult?['total'] ?? {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NutritionResultSheet(total: total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = globalThemeProvider.isDarkMode;
    final theme = isDark ? AppTheme.dark() : AppTheme.light();

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        appBar: CustomAppBar(
          title: 'Nutrition Assistant', 
          onBack: widget.onBack,
          actions: [
            IconButton(
              icon: const Icon(Icons.history_rounded, color: AppTheme.cyan),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _NutritionHistoryScreen())),
              tooltip: 'History',
            ),
            if (_imageFile != null)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent),
                onPressed: _reset,
                tooltip: 'Reset',
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Image View
              _buildImageContainer(isDark),
              const SizedBox(height: 20),

              // 2. Action Buttons Row (Premium Styling)
              Row(
                children: [
                  Expanded(child: _premiumActionBtn(Icons.camera_alt_rounded, 'Camera', () => _pickImage(fromCamera: true), Colors.teal, isDark)),
                  const SizedBox(width: 8),
                  Expanded(child: _premiumActionBtn(Icons.photo_library_rounded, 'Gallery', _pickImage, Colors.blueGrey, isDark)),
                  const SizedBox(width: 8),
                  Expanded(child: _premiumActionBtn(Icons.auto_awesome_rounded, 'Detect', _detectFoods, AppTheme.cyan, isDark)),
                ],
              ),
              const SizedBox(height: 24),

              // 3. Detected Foods Section
              if (_ingredients.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle('Detected Ingredients', isDark),
                    TextButton.icon(
                      icon: const Icon(Icons.add_circle_rounded, color: AppTheme.cyan, size: 18),
                      label: const Text('Add', style: TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700)),
                      onPressed: () => _showAddIngredientDialog(isDark),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Swipe left or tap  −  to remove an item',
                  style: TextStyle(fontSize: 11, color: AppTheme.sub(isDark)),
                ),
                const SizedBox(height: 12),
                _buildIngredientsList(isDark),
                const SizedBox(height: 24),
                _primaryBtn('Calculate Full Nutrition', _calculateFinal, isDark),
                
                if (_analysisResult != null) ...[
                  const SizedBox(height: 32),
                  _sectionTitle('Nutrition Facts', isDark),
                  const SizedBox(height: 16),
                  _buildNutritionDashboard(isDark),
                  const SizedBox(height: 32),
                  _sectionTitle('Ask AI about this meal', isDark),
                  const SizedBox(height: 12),
                  _buildChatSection(isDark),
                ],
              ],
              
              if (_isBusy) 
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppTheme.cyan))),

              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageContainer(bool isDark) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        image: _imageFile != null ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover) : null,
      ),
      child: _imageFile == null ? const Icon(Icons.fastfood_outlined, size: 64, color: Colors.grey) : null,
    );
  }

  Widget _buildIngredientsList(bool isDark) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _ingredients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _ingredients[index];
        return Dismissible(
          key: ValueKey('ingredient_$index'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => setState(() => _ingredients.removeAt(index)),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                // Quantity Box
                Container(
                  width: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
                  ),
                  child: TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.text(isDark), fontSize: 15),
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    controller: TextEditingController(text: item['quantity'] == item['quantity'].toInt() ? '${item['quantity'].toInt()}' : '${item['quantity']}')..selection = TextSelection.collapsed(offset: (item['quantity'] == item['quantity'].toInt() ? '${item['quantity'].toInt()}' : '${item['quantity']}').length),
                    onChanged: (val) {
                      final numVal = double.tryParse(val);
                      if (numVal != null) {
                        _ingredients[index]['quantity'] = numVal;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Unit Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item['unit'] ?? 'g',
                    style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                // Food Name
                Expanded(
                  child: Text(
                    _cleanFoodName(item['food']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.text(isDark)),
                  ),
                ),
                // Delete Button
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () => setState(() => _ingredients.removeAt(index)),
                  tooltip: 'Remove',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddIngredientDialog(bool isDark) {
    final nameCtrl = TextEditingController();
    final qtyCtrl  = TextEditingController(text: '100');
    String selectedUnit = 'g';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppTheme.card(isDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.add_circle_rounded, color: AppTheme.cyan),
              const SizedBox(width: 8),
              Text('Add Ingredient', style: TextStyle(color: AppTheme.text(isDark), fontWeight: FontWeight.w900)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(color: AppTheme.text(isDark)),
                decoration: InputDecoration(
                  labelText: 'Food Name',
                  labelStyle: TextStyle(color: AppTheme.sub(isDark)),
                  prefixIcon: const Icon(Icons.restaurant_menu_rounded, color: AppTheme.cyan, size: 20),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.cyan.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cyan),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: AppTheme.text(isDark)),
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        labelStyle: TextStyle(color: AppTheme.sub(isDark)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.cyan.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.cyan),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      dropdownColor: AppTheme.card(isDark),
                      style: TextStyle(color: AppTheme.text(isDark)),
                      decoration: InputDecoration(
                        labelText: 'Unit',
                        labelStyle: TextStyle(color: AppTheme.sub(isDark)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.cyan.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.cyan),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'g',     child: Text('g')),
                        DropdownMenuItem(value: 'cup',   child: Text('cup')),
                        DropdownMenuItem(value: 'piece', child: Text('piece')),
                        DropdownMenuItem(value: 'ml',    child: Text('ml')),
                      ],
                      onChanged: (v) => setLocal(() => selectedUnit = v ?? 'g'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppTheme.sub(isDark))),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyan,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final qty  = double.tryParse(qtyCtrl.text.trim()) ?? 100.0;
                if (name.isEmpty) return;
                setState(() {
                  _ingredients.add({'food': name, 'quantity': qty, 'unit': selectedUnit});
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _cleanFoodName(String name) {
    // Aggressive cleaning of units and numbers from the name
    return name
      .replaceAll(RegExp(r'^\d+\.?\d*\s*', caseSensitive: false), '') // Remove leading numbers
      .replaceAll(RegExp(r'\b(g|grams|cup|cups|oz|lb|piece|slice|bowl|ml)\b', caseSensitive: false), '') // Remove units
      .replaceAll(RegExp(r'^[-\*\.\s]+'), '') // Remove bullets
      .trim();
  }

  Widget _premiumActionBtn(IconData icon, String label, VoidCallback onTap, Color color, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isBusy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? color.withValues(alpha: 0.15) : Colors.white,
          foregroundColor: color,
          elevation: 0,
          side: BorderSide(color: color.withValues(alpha: 0.2)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionDashboard(bool isDark) {
    final total = _analysisResult?['total'] ?? {};
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _macroBox('Calories', '${total['ENERGY (Kcal)']} kcal', Colors.orange, isDark)),
            const SizedBox(width: 8),
            Expanded(child: _macroBox('Protein', '${total['PROTEIN (g)']}g', Colors.redAccent, isDark)),
            const SizedBox(width: 8),
            Expanded(child: _macroBox('Carbs', '${total['CARBOHYDRATE (g)']}g', Colors.blue, isDark)),
          ],
        ),
        const SizedBox(height: 16),
        _detailRow('Fat', '${total['FAT (g)']} g', isDark),
        _detailRow('Water', '${total['WATER (g)']} g', isDark),
        _detailRow('Fiber', '${total['FIBER (g)']} g', isDark),
        _detailRow('Sodium', '${total['SODIUM (mg)']} mg', isDark),
        _detailRow('Calcium', '${total['CALCIUM (mg)']} mg', isDark),
        _detailRow('Iron', '${total['IRON (mg)']} mg', isDark),
        _detailRow('Ash', '${total['ASH (g)']} g', isDark),
      ],
    );
  }

  Widget _macroBox(String label, String val, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: AppTheme.cardDeco(isDark).copyWith(
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              val, 
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(), 
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.sub(isDark), letterSpacing: 0.5)
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String val, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.sub(isDark))),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChatSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDeco(isDark),
      child: Column(
        children: [
          if (_messages.isNotEmpty) ...[
            ..._messages.map((m) => _chatBubble(m, isDark)),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: const InputDecoration(hintText: 'Ask about this meal...', border: InputBorder.none),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
              IconButton(onPressed: _sendChat, icon: const Icon(Icons.send_rounded, color: AppTheme.cyan)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chatBubble(_ChatMsg m, bool isDark) {
    final isUser = m.role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.cyan.withValues(alpha: 0.1) : (isDark ? Colors.white10 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(12),
        ),
        child: isUser 
          ? Text(m.text, style: TextStyle(color: AppTheme.text(isDark)))
          : MarkdownBody(
              data: m.text,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: AppTheme.text(isDark), fontSize: 14),
                strong: TextStyle(color: AppTheme.text(isDark), fontWeight: FontWeight.bold),
                listBullet: TextStyle(color: AppTheme.cyan),
              ),
            ),
      ),
    );
  }

  Widget _sectionTitle(String title, bool isDark) => Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.text(isDark)));

  final _chatController = TextEditingController();
  final List<_ChatMsg> _messages = [];

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _analysisResult == null) return;
    final userMsg = _ChatMsg(role: _Role.user, text: text);
    setState(() {
      _messages.add(userMsg);
      _chatController.clear();
      _isBusy = true;
    });
    _saveChatMessage(userMsg);

    try {
      final reply = await sqlNutritionService.chat(text, _analysisResult!);
      final botMsg = _ChatMsg(role: _Role.bot, text: reply);
      setState(() => _messages.add(botMsg));
      _saveChatMessage(botMsg);
    } catch (e) {
      setState(() => _error = 'Chat error: $e');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _saveChatMessage(_ChatMsg msg) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _activeSessionId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(user.uid)
          .collection('NutritionHistory')
          .doc(_activeSessionId)
          .collection('Chat')
          .add({
        'role': msg.role == _Role.user ? 'user' : 'bot',
        'text': msg.text,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving nutrition chat: $e');
    }
  }

  Widget _primaryBtn(String label, VoidCallback onTap, bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isBusy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.cyan,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _NutritionResultSheet extends StatelessWidget {
  final Map<String, dynamic> total;
  const _NutritionResultSheet({required this.total});

  @override
  Widget build(BuildContext context) {
    final isDark = globalThemeProvider.isDarkMode;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bg(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          const Text('Analysis Summary', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          _buildNutrientRow('Energy', '${total['ENERGY (Kcal)']} kcal', Icons.bolt, Colors.orange),
          _buildNutrientRow('Protein', '${total['PROTEIN (g)']} g', Icons.fitness_center, Colors.red),
          _buildNutrientRow('Carbs', '${total['CARBOHYDRATE (g)']} g', Icons.bakery_dining, Colors.blue),
          _buildNutrientRow('Fats', '${total['FAT (g)']} g', Icons.opacity, Colors.orangeAccent),
          const Divider(height: 32),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            childAspectRatio: 3,
            children: [
              _miniNutrient('Fiber', '${total['FIBER (g)']}g'),
              _miniNutrient('Sodium', '${total['SODIUM (mg)']}mg'),
              _miniNutrient('Calcium', '${total['CALCIUM (mg)']}mg'),
              _miniNutrient('Iron', '${total['IRON (mg)']}mg'),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cyan, minimumSize: const Size(double.infinity, 50)),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientRow(String label, String val, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _miniNutrient(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

enum _Role { user, bot }

class _ChatMsg {
  final _Role role;
  final String text;
  _ChatMsg({required this.role, required this.text});
}

class _NutritionHistoryScreen extends StatelessWidget {
  const _NutritionHistoryScreen();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = globalThemeProvider.isDarkMode;
    
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: const Text('Nutrition History'),
        backgroundColor: AppTheme.card(isDark),
        foregroundColor: AppTheme.text(isDark),
      ),
      body: user == null
          ? const Center(child: Text('Please log in'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('patients')
                  .doc(user.uid)
                  .collection('NutritionHistory')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No history found'));
                
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final ts = data['timestamp'] as Timestamp?;
                    final date = ts?.toDate() ?? DateTime.now();
                    final calories = data['total']?['ENERGY (Kcal)'] ?? 0;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: AppTheme.cyan, child: Icon(Icons.restaurant, color: Colors.white)),
                        title: Text('Meal on ${date.day}/${date.month} at ${date.hour}:${date.minute}'),
                        subtitle: Text('$calories kcal · ${data['ingredients']?.length ?? 0} items'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Show a summary dialog or similar
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => _NutritionResultSheet(total: data['total']),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
