import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';

/// Patient Community Screen (group chats by injury)
class PatientCommunityScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PatientCommunityScreen({super.key, this.onBack});

  @override
  State<PatientCommunityScreen> createState() => _PatientCommunityScreenState();
}

class _PatientCommunityScreenState extends State<PatientCommunityScreen> {
  final TextEditingController _searchController = TextEditingController();
  late List<_SupportGroup> _groups;
  late List<_SupportGroup> _filteredGroups;
  _SupportGroup? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    _groups = [
      _SupportGroup(
        id: 'grp1',
        name: t('ACL Recovery Crew', 'مجموعة تعافي الرباط الصليبي'),
        injury: t('ACL / Knee', 'إصابة الركبة / الرباط الصليبي'),
        description: t(
            'Share rehab tips, milestones, and setbacks during ACL recovery.',
            'شارك نصائح التأهيل، الإنجازات والتحديات أثناء التعافي من الرباط الصليبي.'),
        avatar: '🦵',
        memberCount: 124,
        lastMessage: t('Day 30: finally full extension!',
            'اليوم 30: وصلت للمد الكامل أخيراً!'),
        lastMessageTime: DateTime.now().subtract(const Duration(minutes: 12)),
        messages: [
          _Message(
            id: 'm1',
            senderName: 'Noura',
            text: t('Day 30: finally full extension!',
                'اليوم 30: وصلت للمد الكامل أخيراً!'),
            timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
            isMe: false,
          ),
          _Message(
            id: 'm2',
            senderName: 'You',
            text: t('Congrats! How was your swelling after the session?',
                'مبروك! كيف كان الانتفاخ بعد التمرين؟'),
            timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
            isMe: true,
          ),
        ],
      ),
      _SupportGroup(
        id: 'grp2',
        name: t('Lower Back Relief', 'تخفيف آلام أسفل الظهر'),
        injury: t('Lumbar / Sciatica', 'أسفل الظهر / عرق النسا'),
        description: t('Discuss core work, ergonomics, and pain management.',
            'ناقش تمارين الكور، بيئة العمل، وإدارة الألم.'),
        avatar: '🔙',
        memberCount: 198,
        lastMessage: t('Anyone tried McKenzie extensions daily?',
            'هل جرب أحد تمديدات ماكينزي يومياً؟'),
        lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
        messages: [
          _Message(
            id: 'm3',
            senderName: 'Ali',
            text: t('Anyone tried McKenzie extensions daily?',
                'هل جرب أحد تمديدات ماكينزي يومياً؟'),
            timestamp: DateTime.now().subtract(const Duration(hours: 2)),
            isMe: false,
          ),
          _Message(
            id: 'm4',
            senderName: 'You',
            text: t('Yes, 3x10 every morning reduced my stiffness.',
                'نعم، ٣×١٠ كل صباح قللت التيبس.'),
            timestamp:
                DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
            isMe: true,
          ),
        ],
      ),
      _SupportGroup(
        id: 'grp3',
        name: t('Shoulder Mobility Lab', 'مختبر مرونة الكتف'),
        injury:
            t('Rotator cuff / Frozen shoulder', 'تمزق الكتف / الكتف المتجمد'),
        description: t('Share band routines, wall slides, and progress photos.',
            'شارك تمارين الأربطة، السلايدات على الحائط، وصور التقدم.'),
        avatar: '🏋️',
        memberCount: 86,
        lastMessage: t('Band external rotations are helping a lot.',
            'تمارين الدوران الخارجي بالرباط مفيدة جداً.'),
        lastMessageTime: DateTime.now().subtract(const Duration(hours: 5)),
        messages: [
          _Message(
            id: 'm5',
            senderName: 'Sara',
            text: t('Band external rotations are helping a lot.',
                'تمارين الدوران الخارجي بالرباط مفيدة جداً.'),
            timestamp: DateTime.now().subtract(const Duration(hours: 5)),
            isMe: false,
          ),
        ],
      ),
      _SupportGroup(
        id: 'grp4',
        name: t('Ankle Comeback', 'عودة الكاحل'),
        injury: t('Sprain / Fracture', 'التواء / كسر'),
        description: t(
            'Balance drills, proprioception, and return-to-run plans.',
            'تمارين الاتزان، الإحساس الحركي، وخطط العودة للجري.'),
        avatar: '🦶',
        memberCount: 142,
        lastMessage: t('Single-leg stands are still shaky.',
            'الوقوف على رجل واحدة ما زال مهتز.'),
        lastMessageTime:
            DateTime.now().subtract(const Duration(days: 1, hours: 3)),
        messages: [
          _Message(
            id: 'm6',
            senderName: 'Khaled',
            text: t('Single-leg stands are still shaky.',
                'الوقوف على رجل واحدة ما زال مهتز.'),
            timestamp:
                DateTime.now().subtract(const Duration(days: 1, hours: 3)),
            isMe: false,
          ),
        ],
      ),
    ];

    _filteredGroups = List.from(_groups);
  }

  void _filterGroups(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredGroups = List.from(_groups);
      } else {
        _filteredGroups = _groups
            .where((group) =>
                group.name.toLowerCase().contains(query.toLowerCase()) ||
                group.injury.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _openGroup(_SupportGroup group) {
    setState(() {
      _selectedGroup = group;
    });
  }

  void _leaveGroup(_SupportGroup group) {
    setState(() {
      _groups.removeWhere((g) => g.id == group.id);
      _filteredGroups.removeWhere((g) => g.id == group.id);
      _selectedGroup = null;
    });
  }

  void _toggleMute(_SupportGroup group) {
    setState(() {
      group.isMuted = !group.isMuted;
    });
  }

  void _sendMessage(String text) {
    if (text.isEmpty || _selectedGroup == null) return;

    final newMessage = _Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderName: 'You',
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
    );

    setState(() {
      _selectedGroup!.messages.add(newMessage);
      _selectedGroup!.lastMessage = text;
      _selectedGroup!.lastMessageTime = newMessage.timestamp;
    });

    // Simulate a group reply
    Future.delayed(const Duration(seconds: 1)).then((_) {
      if (!mounted || _selectedGroup == null) return;
      final reply = _Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderName: _randomMemberName(),
        text: _getRandomReply(),
        timestamp: DateTime.now(),
        isMe: false,
      );
      setState(() {
        _selectedGroup!.messages.add(reply);
        _selectedGroup!.lastMessage = reply.text;
        _selectedGroup!.lastMessageTime = reply.timestamp;
      });
    });
  }

  String _getRandomReply() {
    final replies = [
      t('Great tip! I will try it.', 'نصيحة رائعة! سأجربها.'),
      t('Same here, balance is tough.', 'نفس الشيء، الاتزان صعب.'),
      t('How many sets are you doing?', 'كم عدد المجموعات التي تقوم بها؟'),
      t('Make sure to warm up first.', 'تأكد من الإحماء أولاً.'),
      t('Ice after the session helps me.', 'الثلج بعد التمرين يساعدني.'),
      t('Progress takes time, keep going.', 'التقدم يحتاج وقت، استمر.'),
    ];
    return (replies..shuffle()).first;
  }

  String _randomMemberName() {
    final names = ['Mariam', 'Omar', 'Layla', 'Hassan', 'Youssef', 'Hind'];
    return (names..shuffle()).first;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_selectedGroup != null) {
      return _GroupChatScreen(
        group: _selectedGroup!,
        onBack: () {
          setState(() {
            _selectedGroup = null;
          });
        },
        onSendMessage: _sendMessage,
        onLeaveGroup: () => _leaveGroup(_selectedGroup!),
        onToggleMute: () => _toggleMute(_selectedGroup!),
        isDark: isDark,
      );
    }

    const accent = AppTheme.cyan;

    return Scaffold(
      appBar: CustomAppBar(
        title: t('Community', 'المجتمع'),
        onBack: widget.onBack,
      ),
      backgroundColor: AppTheme.bg(isDark),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _filterGroups,
              style: TextStyle(color: AppTheme.text(isDark)),
              decoration: InputDecoration(
                hintText:
                    t('Search injury groups...', 'ابحث عن مجموعات الإصابات...'),
                hintStyle: TextStyle(
                  color: AppTheme.sub(isDark),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppTheme.sub(isDark),
                ),
                filled: true,
                fillColor: AppTheme.card(isDark),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('Group Chats by Injury', 'مجموعات حسب الإصابة'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        '${_filteredGroups.length} ${t('groups', 'مجموعات')}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filteredGroups.isEmpty
                ? Center(
                    child: Text(
                      t('No groups found', 'لا توجد مجموعات'),
                      style: TextStyle(
                        color: AppTheme.sub(isDark),
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredGroups.length,
                    itemBuilder: (context, index) {
                      final group = _filteredGroups[index];
                      return _GroupCard(
                        group: group,
                        onTap: () => _openGroup(group),
                        isDark: isDark,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _GroupCard extends StatelessWidget {
  final _SupportGroup group;
  final VoidCallback onTap;
  final bool isDark;

  const _GroupCard({
    required this.group,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const accent = AppTheme.cyan;
    return Card(
      color: AppTheme.card(isDark),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.border(isDark),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              group.avatar,
              style: const TextStyle(fontSize: 26),
            ),
          ),
        ),
        title: Text(
          group.name,
          style: TextStyle(
            color: AppTheme.text(isDark),
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              group.injury,
              style: TextStyle(
                color: AppTheme.sub(isDark),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              group.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.sub(isDark),
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatTime(group.lastMessageTime),
              style: TextStyle(
                color: AppTheme.sub(isDark),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${group.memberCount} ${t('members', 'أعضاء')}',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return DateFormat('MMM d').format(time);
    }
  }
}

class _GroupChatScreen extends StatefulWidget {
  final _SupportGroup group;
  final VoidCallback onBack;
  final Function(String) onSendMessage;
  final VoidCallback onLeaveGroup;
  final VoidCallback onToggleMute;
  final bool isDark;

  const _GroupChatScreen({
    required this.group,
    required this.onBack,
    required this.onSendMessage,
    required this.onLeaveGroup,
    required this.onToggleMute,
    required this.isDark,
  });

  @override
  State<_GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<_GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    const accent = AppTheme.cyan;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: widget.onBack,
        ),
        actions: [
          IconButton(
            tooltip: group.isMuted
                ? t('Unmute group', 'إلغاء كتم المجموعة')
                : t('Mute group', 'كتم المجموعة'),
            icon: Icon(
              group.isMuted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_outlined,
            ),
            onPressed: widget.onToggleMute,
          ),
          IconButton(
            tooltip: t('Leave group', 'مغادرة المجموعة'),
            icon: const Icon(Icons.logout),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(t('Leave group?', 'مغادرة المجموعة؟')),
                  content: Text(t(
                      'You will stop receiving updates from this group.',
                      'سوف تتوقف عن استقبال التحديثات من هذه المجموعة.')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t('Cancel', 'إلغاء')),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onLeaveGroup();
                      },
                      child: Text(
                        t('Leave', 'مغادرة'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name),
            Text(
              group.injury,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: AppTheme.sub(widget.isDark),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      backgroundColor: AppTheme.bg(widget.isDark),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppTheme.card(widget.isDark),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        '${group.memberCount} ${t('members', 'أعضاء')}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    group.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          AppTheme.sub(widget.isDark),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: group.messages.length,
              itemBuilder: (context, index) {
                final message = group.messages[index];
                return _MessageBubble(
                  message: message,
                  isDark: widget.isDark,
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card(widget.isDark),
              border: Border(
                top: BorderSide(
                  color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: TextStyle(
                      color: AppTheme.text(widget.isDark),
                    ),
                    decoration: InputDecoration(
                      hintText: t('Share an update...', 'اكتب تحديثاً...'),
                      hintStyle: TextStyle(
                        color:
                            widget.isDark ? Colors.grey[600] : Colors.grey[400],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppTheme.bg(widget.isDark),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        widget.onSendMessage(value);
                        _messageController.clear();
                        Future.delayed(
                            const Duration(milliseconds: 300), _scrollToBottom);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (_messageController.text.isNotEmpty) {
                      widget.onSendMessage(_messageController.text);
                      _messageController.clear();
                      Future.delayed(
                          const Duration(milliseconds: 300), _scrollToBottom);
                    }
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final _Message message;
  final bool isDark;

  const _MessageBubble({
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: message.isMe
                  ? AppTheme.cyan
                  : AppTheme.card(isDark),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!message.isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.sub(isDark),
                      ),
                    ),
                  ),
                Text(
                  message.text,
                  style: TextStyle(
                    color: message.isMe
                        ? Colors.white
                        : (AppTheme.text(isDark)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: message.isMe
                        ? Colors.white70
                        : AppTheme.sub(isDark).withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportGroup {
  final String id;
  final String name;
  final String injury;
  final String description;
  final String avatar;
  final int memberCount;
  String lastMessage;
  DateTime lastMessageTime;
  bool isMuted = false;
  final List<_Message> messages;

  _SupportGroup({
    required this.id,
    required this.name,
    required this.injury,
    required this.description,
    required this.avatar,
    required this.memberCount,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.messages,
  });
}

class _Message {
  final String id;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  _Message({
    required this.id,
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });
}
