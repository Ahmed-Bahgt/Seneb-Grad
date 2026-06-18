import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../utils/theme_provider.dart';

/// Demo Screen - Shows correct/incorrect form videos for the assigned exercise.
/// If we don't have demo videos for the exercise type yet, shows a clean
/// placeholder instead of falling back to a squat video.
class SessionDemoScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final String? exerciseType; // 'Squat', 'Shoulder Abduction', etc.

  const SessionDemoScreen({super.key, this.onBack, this.exerciseType});

  @override
  State<SessionDemoScreen> createState() => _SessionDemoScreenState();
}

class _SessionDemoScreenState extends State<SessionDemoScreen> {
  String _selectedForm = 'Correct';
  YoutubePlayerController? _videoController;
  bool _isLoading = false;
  String? _errorMessage;

  // YouTube IDs per exercise. Add entries here as you record demo clips for
  // the other exercises.
  static const Map<String, Map<String, String>> _videoIdsByExercise = {
    'Squat': {
      'correct': 'NjCrfSkrxDI',
      'incorrect': 'rS-nhzFEeLg',
    },
  };

  String get _exerciseName {
    final t = widget.exerciseType?.trim();
    return (t == null || t.isEmpty) ? 'Squat' : t;
  }

  bool get _hasVideos => _videoIdsByExercise.containsKey(_exerciseName);

  String? _getVideoId() {
    final ids = _videoIdsByExercise[_exerciseName];
    if (ids == null) return null;
    return ids[_selectedForm.toLowerCase()];
  }

  @override
  void initState() {
    super.initState();
    if (_hasVideos) _setupController();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _setupController() {
    final videoId = _getVideoId();
    if (videoId == null) return;
    _videoController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        loop: true,
        forceHD: false,
        useHybridComposition: true,
        controlsVisibleAtStart: false,
        enableCaption: false,
        mute: false,
      ),
    );
  }

  Future<void> _loadSelectedVideo() async {
    if (_videoController == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final videoId = _getVideoId();
    try {
      if (videoId != null) _videoController!.load(videoId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Video playback failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Fitness Trainer — Form Examples',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _exerciseName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.sub(isDark),
            ),
          ),
          const SizedBox(height: 20),

          if (_hasVideos) ...[
            // Form picker (Correct / Incorrect) — only shown when we have videos
            Row(
              children: [
                Text('Form',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: AppTheme.sub(isDark))),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown(
                    value: _selectedForm,
                    items: const ['Correct', 'Incorrect'],
                    onChanged: (v) {
                      setState(() => _selectedForm = v ?? 'Correct');
                      _loadSelectedVideo();
                    },
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Example — $_exerciseName · $_selectedForm',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.card(isDark),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildVideoContent(isDark),
              ),
            ),
          ] else
            _buildNoDemoCard(isDark),
        ],
      ),
    );
  }

  Widget _buildNoDemoCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(
        children: [
          Icon(Icons.video_library_outlined,
              size: 56, color: AppTheme.sub(isDark).withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            'Demo video not available yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'A reference clip for $_exerciseName will be added soon. '
            'Switch to the Live Stream tab to start your session — '
            'the AI trainer will guide you with on-screen feedback.',
            style: TextStyle(fontSize: 13, color: AppTheme.sub(isDark)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoContent(bool isDark) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text('Video Unavailable',
                  style: TextStyle(
                      color: AppTheme.text(isDark),
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? 'Network error',
                  style: TextStyle(color: AppTheme.sub(isDark), fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadSelectedVideo,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_videoController != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            YoutubePlayer(
              controller: _videoController!,
              showVideoProgressIndicator: true,
              progressIndicatorColor: Colors.red,
              progressColors: const ProgressBarColors(
                playedColor: Colors.red,
                handleColor: Colors.redAccent,
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_circle_outline,
              size: 64, color: AppTheme.sub(isDark).withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('Ready to play', style: TextStyle(color: AppTheme.sub(isDark))),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadSelectedVideo,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Load Video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyan,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: AppTheme.card(isDark),
        style: TextStyle(color: AppTheme.text(isDark), fontSize: 14),
        onChanged: onChanged,
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
      ),
    );
  }
}
