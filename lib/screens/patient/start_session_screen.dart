import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import 'session_demo_screen.dart';
import 'session_live_stream_screen.dart';

  /// Start Session Screen - Main hub with 2 tabs for session training
class StartSessionScreen extends StatefulWidget {
  final String planName;
  final String? exerciseType; // 'Squat', 'Shoulder Abduction', etc.
  final VoidCallback? onBack;

  const StartSessionScreen({
    super.key,
    required this.planName,
    this.exerciseType,
    this.onBack,
  });

  @override
  State<StartSessionScreen> createState() => _StartSessionScreenState();
}

class _StartSessionScreenState extends State<StartSessionScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: widget.onBack ?? () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('Today\'s Session', 'جلسة اليوم'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.planName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: AppTheme.sub(isDark),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: [
            Tab(
              icon: const Icon(Icons.video_library),
              text: t('Preview', 'معاينة'),
            ),
            Tab(
              icon: const Icon(Icons.videocam),
              text: t('Live Stream', 'بث مباشر'),
            ),
          ],
        ),
      ),
      backgroundColor: AppTheme.bg(isDark),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Demo
          SessionDemoScreen(
            onBack: widget.onBack,
            exerciseType: widget.exerciseType,
          ),

          // Tab 2: Live Stream
          SessionLiveStreamScreen(onBack: widget.onBack),
        ],
      ),
    );
  }
}
