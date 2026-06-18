import 'package:flutter/material.dart';

import '../../services/doctor_patient_chat_service.dart';
import '../../utils/theme_provider.dart';
import '../../widgets/custom_app_bar.dart';
import '../common/doctor_patient_chat_screen.dart';

class PatientChatScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const PatientChatScreen({super.key, this.onBack});

  @override
  State<PatientChatScreen> createState() => _PatientChatScreenState();
}

class _PatientChatScreenState extends State<PatientChatScreen> {
  final DoctorPatientChatService _chatService = DoctorPatientChatService();
  late final Future<DoctorPatientChatContext?> _chatContextFuture;

  @override
  void initState() {
    super.initState();
    _chatContextFuture = _chatService.loadCurrentPatientChatContext();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<DoctorPatientChatContext?>(
      future: _chatContextFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: CustomAppBar(
              title: t('Chat', 'المحادثة'),
              onBack: widget.onBack,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final chatContext = snapshot.data;
        if (chatContext == null) {
          return Scaffold(
            appBar: CustomAppBar(
              title: t('Chat', 'المحادثة'),
              onBack: widget.onBack,
            ),
            backgroundColor: AppTheme.bg(isDark),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t('No assigned doctor yet. Chat becomes available after a doctor is assigned.',
                      'لا يوجد طبيب معالج مخصص بعد. ستتاح المحادثة بعد تعيين الطبيب.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.sub(isDark),
                  ),
                ),
              ),
            ),
          );
        }

        return DoctorPatientChatScreen(
          chatContext: chatContext,
          onBack: widget.onBack,
        );
      },
    );
  }
}
