// =============================================================================
// PATIENT REPORTS SCREEN - VIEW ALL SESSION REPORTS FOR A PATIENT
// =============================================================================
// Purpose: Display all completed sessions for a patient with summary details
// Features:
// - StreamBuilder to fetch all sessions from /Patients/{patientId}/Sessions
// - Display each session as a Card with Date, Correct/Wrong reps, Accuracy
// - Tap on session to view full summary in AlertDialog
// - Sort sessions by date (newest first)
// - Show visual progress bar for accuracy
// Data Structure:
// - Reads from: /Patients/{patientId}/Sessions/{sessionId}
// - Contains: correctReps, wrongReps, accuracyPercentage, timestamp
// =============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:video_player/video_player.dart';
import '../../services/sql_clinical_service.dart';
import '../../services/sql_clinical_chat_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';

/// Patient Reports Screen - View all sessions for a patient
class PatientReportsScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final VoidCallback? onBack;

  const PatientReportsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.onBack,
  });

  @override
  State<PatientReportsScreen> createState() => _PatientReportsScreenState();
}

class _PatientReportsScreenState extends State<PatientReportsScreen> {
  late Stream<QuerySnapshot> _sessionsStream;
  final SqlClinicalService _clinicalService = SqlClinicalService();
  final SqlClinicalChatService _chatService = SqlClinicalChatService();
  bool _isAnalyzing = false;
  Map<String, dynamic>? _aiAnalysisResult;
  // Follow-up chat state
  List<ClinicalChatMessage> _chatHistory = [];
  final TextEditingController _chatController = TextEditingController();
  bool _chatLoading = false;
  Map<String, dynamic>? _activeSessionData;

  @override
  void initState() {
    super.initState();
    debugPrint('[PatientReports] Loading sessions for patient: ${widget.patientId}');
    debugPrint('[PatientReports] Patient name: ${widget.patientName}');
    // Initialize stream to fetch sessions from Firestore
    _sessionsStream = FirebaseFirestore.instance
        .collection('patients')
        .doc(widget.patientId)
        .collection('Sessions')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
        title: '${widget.patientName} - Session Reports',
        onBack: widget.onBack ?? () => Navigator.pop(context),
      ),
      backgroundColor:
          AppTheme.bg(isDark),
      body: StreamBuilder<QuerySnapshot>(
        stream: _sessionsStream,
        builder: (context, snapshot) {
          // Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error state
          if (snapshot.hasError) {
            debugPrint('[PatientReports] Error loading sessions: ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading sessions',
                      style: TextStyle(
                        color: AppTheme.text(isDark),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      style: TextStyle(
                        color: AppTheme.sub(isDark),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // No sessions state
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            debugPrint('[PatientReports] No sessions found for patient: ${widget.patientId}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_off,
                      size: 64,
                      color: isDark ? Colors.white24 : Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No sessions yet',
                      style: TextStyle(
                        color: AppTheme.text(isDark),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No sessions recorded for this patient yet.',
                      style: TextStyle(
                        color: AppTheme.sub(isDark),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // Sessions list
          final sessions = snapshot.data!.docs;
          
          // Filter duplicates based on timestamp and exercise name
          final uniqueSessions = <QueryDocumentSnapshot>[];
          final seenKeys = <String>{};
          
          for (var doc in sessions) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['timestamp'];
            final ex = data['exerciseType'] ?? 'Squat';
            
            // Create a unique key from exercise + exact timestamp string
            final key = "$ex-${ts?.toString() ?? 'no-ts'}";
            
            if (!seenKeys.contains(key)) {
              seenKeys.add(key);
              uniqueSessions.add(doc);
            }
          }

          debugPrint('[PatientReports] Found ${sessions.length} sessions, showing ${uniqueSessions.length} unique for patient: ${widget.patientId}');
          
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: uniqueSessions.length,
            itemBuilder: (context, index) {
              final sessionDoc = uniqueSessions[index];
              final data = sessionDoc.data() as Map<String, dynamic>;

              return _buildSessionCard(
                context: context,
                isDark: isDark,
                sessionData: data,
                sessionId: sessionDoc.id,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSessionCard({
    required BuildContext context,
    required bool isDark,
    required Map<String, dynamic> sessionData,
    required String sessionId,
  }) {
    final correctReps = sessionData['correctReps'] as int? ?? 0;
    final wrongReps = sessionData['incorrectReps'] as int? ?? 0;
    final totalReps = sessionData['totalReps'] as int? ?? (correctReps + wrongReps);
    final accuracy = (sessionData['accuracy'] as num?)?.toDouble() ?? 0.0;
    final exerciseType = sessionData['exerciseType'] as String? ?? 'Squat';
    final videoUrl = sessionData['videoUrl'] as String?;

    // Parse Firestore Timestamp
    final ts = sessionData['timestamp'];
    final timestamp = ts is Timestamp
        ? ts.toDate()
        : (ts is String && ts.isNotEmpty ? DateTime.tryParse(ts) : null) ??
            DateTime.now();
    final formattedDate = _formatDate(timestamp);
    final formattedTime = _formatTime(timestamp);

    return GestureDetector(
      onTap: () => _showSessionSummaryDialog(
        context: context,
        isDark: isDark,
        sessionData: sessionData,
        formattedDate: formattedDate,
        formattedTime: formattedTime,
        sessionId: sessionId,
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: AppTheme.card(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date and Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattedDate,
                          style: TextStyle(
                            color: AppTheme.text(isDark),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedTime,
                          style: TextStyle(
                            color: AppTheme.sub(isDark),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Exercise type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF64B5F6).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF64B5F6).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      exerciseType,
                      style: const TextStyle(
                        color: Color(0xFF64B5F6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                   if (videoUrl != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill, color: Colors.red, size: 28),
                      onPressed: () => _showVideoPlayerDialog(context, videoUrl, exerciseType),
                      tooltip: 'Watch Session Video',
                    ),
                  ],
                  // Delete Button
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red.withValues(alpha: 0.7), size: 22),
                    onPressed: () => _confirmDeleteSession(context, sessionId),
                    tooltip: 'Delete Session',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Correct vs Wrong Reps
              Row(
                children: [
                  Expanded(
                    child: _buildRepsBadge(
                      label: 'Correct',
                      value: correctReps,
                      color: Colors.green,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildRepsBadge(
                      label: 'Incorrect',
                      value: wrongReps,
                      color: Colors.red,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Accuracy Progress Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Accuracy',
                        style: TextStyle(
                          color: AppTheme.sub(isDark),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${accuracy.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: AppTheme.text(isDark),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: accuracy / 100,
                      minHeight: 8,
                      backgroundColor:
                          isDark ? Colors.white12 : Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getAccuracyColor(accuracy),
                      ),
                    ),
                  ),
                ],
              ),

              // Total Reps
              const SizedBox(height: 12),
              Text(
                'Total Reps: $totalReps',
                style: TextStyle(
                  color: AppTheme.sub(isDark),
                  fontSize: 11,
                ),
              ),

              // Tap to view details hint
              const SizedBox(height: 8),
              Text(
                'Tap to view full details →',
                style: TextStyle(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.7),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRepsBadge({
    required String label,
    required int value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.sub(isDark),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionSummaryDialog({
    required BuildContext context,
    required bool isDark,
    required Map<String, dynamic> sessionData,
    required String formattedDate,
    required String formattedTime,
    required String sessionId,
  }) {
    final correctReps = sessionData['correctReps'] as int? ?? 0;
    final wrongReps = sessionData['incorrectReps'] as int? ?? 0;
    final totalReps = correctReps + wrongReps;
    final accuracy = (sessionData['accuracy'] as num?)?.toDouble() ?? 0.0;
    final exerciseType = sessionData['exerciseType'] as String? ?? 'Squat';
    final sets = sessionData['currentSet'] as int? ?? 0;
    final targetSets = sessionData['targetSets'] as int? ?? 0;
    final mode = sessionData['mode'] as String? ?? 'Beginner';

    // Store session data for the follow-up chat agent
    _activeSessionData = {
      'exercise_type': exerciseType,
      'correct_reps': correctReps,
      'incorrect_reps': wrongReps,
      'total_reps': totalReps,
      'accuracy': accuracy,
      'sets_completed': sets,
      'target_sets': targetSets,
      'mode': mode,
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session Summary - $exerciseType'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date and Time
                _buildSummaryRow('Date', formattedDate),
                _buildSummaryRow('Time', formattedTime),
                const Divider(height: 16),
                
                // Exercise Details
                _buildSummaryRow('Exercise', exerciseType),
                _buildSummaryRow('Mode', mode),
                _buildSummaryRow('Sets Completed', '$sets/$targetSets'),
                const Divider(height: 16),
                
                // AI Clinical Agent Section
                Text(
                  '🧠 Seneb AI Clinical Agent',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cyan,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ClinicalAnalysisPage(
                          sessionData: sessionData,
                          patientName: widget.patientName,
                          sessionId: sessionId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: const Text('Run Clinical Analysis'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyan,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // --- Follow-Up Chat (Python REPL Agent) ---
                if (_aiAnalysisResult != null) ...[
                  const Divider(height: 24),
                  Text(
                    '💬 Ask Seneb Clinical Agent',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.cyan,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Chat history
                  if (_chatHistory.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _chatHistory.length,
                        itemBuilder: (_, i) {
                          final msg = _chatHistory[i];
                          final isUser = msg.role == 'user';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: isUser
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? AppTheme.cyan.withValues(alpha: 0.15)
                                        : (isDark ? Colors.white10 : Colors.grey.shade100),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: MarkdownBody(
                                    data: msg.content,
                                    styleSheet: MarkdownStyleSheet(
                                      p: TextStyle(fontSize: 12, color: AppTheme.text(isDark)),
                                    ),
                                  ),
                                ),
                                if (msg.imageBase64 != null) ...[
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      base64Decode(msg.imageBase64!),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          enabled: !_chatLoading,
                          style: TextStyle(fontSize: 13, color: AppTheme.text(isDark)),
                          decoration: InputDecoration(
                            hintText: 'Ask a question or request a chart...',
                            hintStyle: TextStyle(fontSize: 12, color: AppTheme.sub(isDark)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onSubmitted: (_) => _sendChatMessage(setDialogState),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: _chatLoading ? Colors.grey : AppTheme.cyan,
                        child: _chatLoading
                            ? const SizedBox(width: 12, height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.send, color: Colors.white, size: 16),
                                onPressed: () => _sendChatMessage(setDialogState),
                              ),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),

                // Performance Metrics
                _buildSummaryRow(
                  'Correct Reps',
                  correctReps.toString(),
                  valueColor: Colors.green,
                ),
                _buildSummaryRow(
                  'Incorrect Reps',
                  wrongReps.toString(),
                  valueColor: Colors.red,
                ),
                _buildSummaryRow('Total Reps', totalReps.toString()),
                _buildSummaryRow(
                  'Accuracy',
                  '${accuracy.toStringAsFixed(1)}%',
                  valueColor: _getAccuracyColor(accuracy),
                ),
                
                if (sessionData['videoUrl'] != null && sessionData['videoUrl'].toString().isNotEmpty) ...[
                  const Divider(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showVideoPlayerDialog(context, sessionData['videoUrl'].toString(), '$exerciseType Session'),
                    icon: const Icon(Icons.play_circle_fill),
                    label: const Text('Watch Raw Session Video'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyan,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 36),
                    ),
                  ),
                ] else if (sessionData['recordingConsent'] == false) ...[
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.videocam_off, color: Colors.orange, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Patient opted out of video recording. Only biomechanical logs and AI analysis are available.',
                            style: TextStyle(
                              color: isDark ? Colors.orange[200] : Colors.orange[800],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Video recording failed or is still uploading. The patient consented, but no video file was found in the cloud.',
                            style: TextStyle(
                              color: isDark ? Colors.red[200] : Colors.red[800],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _resetChatState();
              Navigator.pop(context);
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    Color? valueColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppTheme.sub(isDark), fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? (AppTheme.text(isDark)),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAssessment({
    required int correctReps,
    required int totalReps,
    required double accuracy,
    required int sets,
    required int targetSets,
  }) {
    final buffer = StringBuffer();

    // Performance assessment
    if (accuracy >= 90) {
      buffer.writeln('✅ Excellent form consistency! Strong performance.');
    } else if (accuracy >= 75) {
      buffer.writeln('✅ Good form! Keep practicing for better consistency.');
    } else if (accuracy >= 60) {
      buffer.writeln('⚠️ Average form. Focus on proper technique.');
    } else {
      buffer.writeln('⚠️ Form needs improvement. Consider reducing reps/sets.');
    }

    buffer.writeln();

    // Volume assessment
    if (sets == targetSets) {
      buffer.writeln('✅ Completed all target sets.');
    } else if (sets > 0) {
      buffer.writeln('⚠️ Did not complete all target sets.');
    }

    buffer.writeln();

    // Recommendations
    buffer.write('💡 ');
    if (accuracy >= 80 && sets == targetSets) {
      buffer.write(
        'Great progress! Consider increasing difficulty in next session.',
      );
    } else if (accuracy < 70) {
      buffer.write('Focus on form over volume. Watch the demo videos.');
    } else {
      buffer.write('Keep up the consistent work!');
    }

    return buffer.toString().trim();
  }

  String _formatDate(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy').format(dateTime);
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy >= 90) return Colors.green;
    if (accuracy >= 75) return Colors.lightGreen;
    if (accuracy >= 60) return Colors.orange;
    return Colors.red;
  }

  void _showVideoPlayerDialog(BuildContext context, String videoUrl, String title) {
    showDialog(
      context: context,
      builder: (context) => _VideoPlayerDialog(videoUrl: videoUrl, title: title),
    );
  }

  /// Called when doctor sends a follow-up message to the Seneb Clinical Agent.
  /// Supports text Q&A and custom graph generation via Python REPL on backend.
  Future<void> _sendChatMessage(StateSetter setDialogState) async {
    final msg = _chatController.text.trim();
    if (msg.isEmpty || _chatLoading || _activeSessionData == null) return;

    final userMsg = ClinicalChatMessage(role: 'user', content: msg);
    setDialogState(() {
      _chatHistory.add(userMsg);
      _chatLoading = true;
      _chatController.clear();
    });

    try {
      final reply = await _chatService.sendMessage(
        message: msg,
        sessionData: _activeSessionData!,
        history: _chatHistory.where((m) => m.role != 'user' || m != userMsg).toList(),
      );
      setDialogState(() {
        _chatHistory.add(reply);
        _chatLoading = false;
      });
    } catch (e) {
      setDialogState(() {
        _chatHistory.add(ClinicalChatMessage(
          role: 'assistant',
          content: '⚠️ Error: ${e.toString().replaceAll('Exception: ', '')}',
        ));
        _chatLoading = false;
      });
    }
  }

  void _confirmDeleteSession(BuildContext context, String sessionId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session?'),
        content: const Text('This will permanently remove this session record. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSession(sessionId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patientId)
          .collection('Sessions')
          .doc(sessionId)
          .delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete session: $e')),
        );
      }
    }
  }

  void _resetChatState() {
    setState(() {
      _aiAnalysisResult = null;
      _isAnalyzing = false;
      _chatHistory = [];
      _chatController.clear();
      _chatLoading = false;
      _activeSessionData = null;
    });
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;
  final String title;

  const _VideoPlayerDialog({required this.videoUrl, required this.title});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Session Video - ${widget.title}'),
      contentPadding: EdgeInsets.zero,
      content: AspectRatio(
        aspectRatio: _initialized ? _controller.value.aspectRatio : 16 / 9,
        child: _initialized
            ? Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  VideoPlayer(_controller),
                  VideoProgressIndicator(_controller, allowScrubbing: true),
                  Center(
                    child: IconButton(
                      icon: Icon(
                        _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 50,
                      ),
                      onPressed: () {
                        setState(() {
                          _controller.value.isPlaying ? _controller.pause() : _controller.play();
                        });
                      },
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A dedicated full-screen page for Clinical Analysis
class ClinicalAnalysisPage extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  final String patientName;
  final String? sessionId;

  const ClinicalAnalysisPage({
    super.key,
    required this.sessionData,
    required this.patientName,
    this.sessionId,
  });

  @override
  State<ClinicalAnalysisPage> createState() => _ClinicalAnalysisPageState();
}

class _ClinicalAnalysisPageState extends State<ClinicalAnalysisPage> {
  final SqlClinicalService _clinicalService = SqlClinicalService();
  final SqlClinicalChatService _chatService = SqlClinicalChatService();
  
  bool _isAnalyzing = true;
  Map<String, dynamic>? _analysisResult;
  String? _error;
  
  // Chat state
  final List<ClinicalChatMessage> _chatHistory = [];
  final TextEditingController _chatController = TextEditingController();
  bool _chatLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingAnalysis();
  }

  Future<void> _loadExistingAnalysis() async {
    // 1. Check if analysis already exists in sessionData
    if (widget.sessionData.containsKey('aiAnalysis')) {
      setState(() {
        _analysisResult = {
          'analysis': widget.sessionData['aiAnalysis'],
          'reps_chart': widget.sessionData['repsChart'],
          'sets_chart': widget.sessionData['setsChart'],
        };
        _isAnalyzing = false;
      });
      _loadChatHistory();
      return;
    }

    // 2. Otherwise, check Firestore directly if we have sessionId
    if (widget.sessionId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('patients')
            .doc(widget.sessionData['patientId'])
            .collection('Sessions')
            .doc(widget.sessionId)
            .get();
        
        if (doc.exists && doc.data()!.containsKey('aiAnalysis')) {
          final data = doc.data()!;
          setState(() {
            _analysisResult = {
              'analysis': data['aiAnalysis'],
              'reps_chart': data['repsChart'],
              'sets_chart': data['setsChart'],
            };
            _isAnalyzing = false;
          });
          _loadChatHistory();
          return;
        }
      } catch (e) {
        debugPrint('Error loading existing analysis: $e');
      }
    }

    // 3. Finally, perform new analysis
    _performAnalysis();
  }

  Future<void> _loadChatHistory() async {
    if (widget.sessionId == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.sessionData['patientId'])
          .collection('Sessions')
          .doc(widget.sessionId)
          .collection('ClinicalChat')
          .orderBy('timestamp')
          .get();
      
      if (mounted && snapshot.docs.isNotEmpty) {
        setState(() {
          _chatHistory.clear();
          for (var doc in snapshot.docs) {
            final data = doc.data();
            _chatHistory.add(ClinicalChatMessage(
              role: data['role'],
              content: data['content'],
            ));
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading chat history: $e');
    }
  }

  Future<void> _performAnalysis() async {
    try {
      final ts = widget.sessionData['timestamp'];
      final timestamp = ts is Timestamp
          ? ts.toDate()
          : (ts is String && ts.isNotEmpty ? DateTime.tryParse(ts) : null) ??
              DateTime.now();
      final formattedTS = "${DateFormat('yyyy-MM-dd').format(timestamp)} at ${DateFormat('HH:mm').format(timestamp)}";

      final payload = Map<String, dynamic>.from(widget.sessionData);
      payload['patientName'] = widget.patientName;
      payload['formattedTimestamp'] = formattedTS;
      final res = await _clinicalService.analyzeSession(payload);
      if (mounted) {
        setState(() {
          _analysisResult = res;
          _isAnalyzing = false;
        });
        _saveAnalysisToFirestore(res);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _saveAnalysisToFirestore(Map<String, dynamic> result) async {
    if (widget.sessionId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.sessionData['patientId'])
          .collection('Sessions')
          .doc(widget.sessionId)
          .update({
        'aiAnalysis': result['analysis'],
        'repsChart': result['reps_chart'],
        'setsChart': result['sets_chart'],
      });
      debugPrint('Analysis saved to Firestore');
    } catch (e) {
      debugPrint('Error saving analysis: $e');
    }
  }

  Future<void> _resetAnalysis() async {
    if (widget.sessionId == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Analysis?'),
        content: const Text('This will permanently delete the current AI report and chat history. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _chatHistory.clear();
      _error = null;
    });

    try {
      final sessionRef = FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.sessionData['patientId'])
          .collection('Sessions')
          .doc(widget.sessionId);

      // 1. Clear fields in session doc
      await sessionRef.update({
        'aiAnalysis': FieldValue.delete(),
        'repsChart': FieldValue.delete(),
        'setsChart': FieldValue.delete(),
      });

      // 2. Clear chat collection
      final chatSnapshot = await sessionRef.collection('ClinicalChat').get();
      for (var doc in chatSnapshot.docs) {
        await doc.reference.delete();
      }

      debugPrint('Firestore data cleared for reset');
      
      // Stop here, don't re-run analysis automatically
      setState(() => _isAnalyzing = false);
    } catch (e) {
      _snack('Reset failed: $e');
      setState(() => _isAnalyzing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendChatMessage() async {
    final query = _chatController.text.trim();
    if (query.isEmpty || _analysisResult == null) return;

    final userMsg = ClinicalChatMessage(role: 'user', content: query);
    setState(() {
      _chatHistory.add(userMsg);
      _chatController.clear();
      _chatLoading = true;
    });

    // Save user message to Firestore
    _saveChatMessage(userMsg);

    try {
      final ts = widget.sessionData['timestamp'];
      final timestamp = ts is Timestamp
          ? ts.toDate()
          : (ts is String && ts.isNotEmpty ? DateTime.tryParse(ts) : null) ??
              DateTime.now();
      final formattedTS = "${DateFormat('yyyy-MM-dd').format(timestamp)} at ${DateFormat('HH:mm').format(timestamp)}";

      final payload = Map<String, dynamic>.from(widget.sessionData);
      payload['patientName'] = widget.patientName;
      payload['formattedTimestamp'] = formattedTS;
      final responseMsg = await _chatService.sendMessage(
        message: query,
        sessionData: payload,
        history: _chatHistory,
      );

      if (mounted) {
        setState(() {
          _chatHistory.add(responseMsg);
          _chatLoading = false;
        });
        // Save assistant message to Firestore
        _saveChatMessage(responseMsg);
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = ClinicalChatMessage(role: 'assistant', content: 'Sorry, I encountered an error: $e');
        setState(() {
          _chatHistory.add(errorMsg);
          _chatLoading = false;
        });
      }
    }
  }

  Future<void> _saveChatMessage(ClinicalChatMessage msg) async {
    if (widget.sessionId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.sessionData['patientId'])
          .collection('Sessions')
          .doc(widget.sessionId)
          .collection('ClinicalChat')
          .add({
        'role': msg.role,
        'content': msg.content,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving chat message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ts = widget.sessionData['timestamp'];
    final timestamp = ts is Timestamp
        ? ts.toDate()
        : (ts is String && ts.isNotEmpty ? DateTime.tryParse(ts) : null) ??
            DateTime.now();
    final formattedTS = "${DateFormat('yyyy-MM-dd').format(timestamp)} at ${DateFormat('HH:mm').format(timestamp)}";

    final exerciseType = widget.sessionData['exerciseType'] ?? 'Exercise';

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clinical Analysis - $exerciseType', style: const TextStyle(fontSize: 16)),
            Text('${widget.patientName} • $formattedTS', style: TextStyle(fontSize: 11, color: AppTheme.sub(isDark))),
          ],
        ),
        backgroundColor: AppTheme.card(isDark),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isAnalyzing && _analysisResult != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyan),
              tooltip: 'Reset Analysis',
              onPressed: _resetAnalysis,
            ),
        ],
      ),
      body: _isAnalyzing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppTheme.cyan),
                  const SizedBox(height: 20),
                  Text(
                    'Analyzing session data...',
                    style: TextStyle(color: AppTheme.text(isDark)),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Analysis Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.text(isDark))),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.sub(isDark))),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isAnalyzing = true;
                              _error = null;
                            });
                            _performAnalysis();
                          },
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : _analysisResult == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.analytics_outlined, size: 80, color: AppTheme.sub(isDark).withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'No Analysis Performed Yet',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.text(isDark)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Run the clinical agent to get AI insights.',
                            style: TextStyle(color: AppTheme.sub(isDark)),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isAnalyzing = true;
                                _error = null;
                              });
                              _performAnalysis();
                            },
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Start AI Analysis'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.cyan,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Simple Header
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: AppTheme.cyan),
                          const SizedBox(width: 8),
                          Text(
                            'AI Clinical Report',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.text(isDark),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Charts
                      if (_analysisResult != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildChartCard('Repetitions Analysis', _analysisResult!['reps_chart'], isDark),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildChartCard('Sets Progress', _analysisResult!['sets_chart'], isDark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Analysis Text
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.card(isDark),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
                          ),
                          child: MarkdownBody(
                            data: _analysisResult!['analysis'],
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(fontSize: 14, color: AppTheme.text(isDark), height: 1.6),
                              strong: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.cyan),
                              h1: TextStyle(fontSize: 18, color: AppTheme.text(isDark)),
                              h2: TextStyle(fontSize: 16, color: AppTheme.text(isDark)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Chat Section
                        Text(
                          '💬 Consult Seneb about this session',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.text(isDark),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildChatSection(isDark),
                        const SizedBox(height: 100), // Bottom padding
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildChartCard(String title, String base64Image, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 12, color: AppTheme.sub(isDark), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            base64Decode(base64Image),
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  Widget _buildChatSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          if (_chatHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'Ask anything about the patient\'s performance, range of motion, or suggested adjustments.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.sub(isDark), fontSize: 13),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _chatHistory.length,
              itemBuilder: (context, index) {
                final msg = _chatHistory[index];
                final isUser = msg.role == 'user';
                return Container(
                  padding: const EdgeInsets.all(12),
                  color: isUser ? Colors.transparent : AppTheme.cyan.withValues(alpha: 0.05),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isUser ? Icons.person_outline : Icons.smart_toy_outlined,
                        size: 18,
                        color: isUser ? AppTheme.sub(isDark) : AppTheme.cyan,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MarkdownBody(
                          data: msg.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(fontSize: 13, color: AppTheme.text(isDark)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (_chatLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation(AppTheme.cyan)),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    decoration: InputDecoration(
                      hintText: 'Type your question...',
                      hintStyle: TextStyle(color: AppTheme.sub(isDark), fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    style: TextStyle(color: AppTheme.text(isDark), fontSize: 13),
                    onSubmitted: (_) => _sendChatMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _chatLoading ? null : _sendChatMessage,
                  icon: const Icon(Icons.send_rounded, color: AppTheme.cyan),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.cyan),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.text(isDark))),
          Text(value, style: TextStyle(color: AppTheme.sub(isDark))),
        ],
      ),
    );
  }
}
