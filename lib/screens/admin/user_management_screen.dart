import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';

/// User Management Screen - Admin can view and manage all users
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  String _userType = 'doctors'; // doctors or patients
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Text(t('User Management', 'إدارة المستخدمين')),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
            child: Column(
              children: [
                // User Type Selector
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'doctors',
                      label: Text(t('Doctors', 'الأطباء')),
                      icon: const Icon(Icons.medical_services_rounded),
                    ),
                    ButtonSegment(
                      value: 'patients',
                      label: Text(t('Patients', 'المرضى')),
                      icon: const Icon(Icons.people_rounded),
                    ),
                  ],
                  selected: {_userType},
                  onSelectionChanged: (selected) {
                    setState(() => _userType = selected.first);
                  },
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                // Search Field
                TextField(
                  decoration: InputDecoration(
                    hintText: t('Search by name or email', 'ابحث باسم أو بريد'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toLowerCase());
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildUsersList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection(_userType).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(t('No users found', 'لم يتم العثور على مستخدمين')),
          );
        }

        var users = snapshot.data!.docs;

        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          users = users.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = '${data['firstName'] as String? ?? ''} ${data['lastName'] as String? ?? ''}';
            final email = data['email'] as String? ?? '';
            return name.toLowerCase().contains(_searchQuery) ||
                email.toLowerCase().contains(_searchQuery);
          }).toList();
        }

        return ListView.builder(
          padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index].data() as Map<String, dynamic>;
            final userId = users[index].id;

            return _buildUserCard(context, user, userId, isDark);
          },
        );
      },
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    Map<String, dynamic> user,
    String userId,
    bool isDark,
  ) {
    final firstName = user['firstName'] as String? ?? '';
    final lastName = user['lastName'] as String? ?? '';
    final email = user['email'] as String? ?? '';
    final phone = user['phone'] as String? ?? '';
    final isVerified = user['isVerified'] as bool? ?? false;
    final isActive = user['isActive'] as bool? ?? true;
    final createdAt = user['createdAt'] as Timestamp?;

    return Card(
      color: isDark ? Colors.grey[900] : Colors.white,
      margin: EdgeInsets.only(bottom: ResponsiveUtils.spacing(context, 12)),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$firstName $lastName',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.fontSize(context, 16),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.text(isDark),
                        ),
                      ),
                      SizedBox(height: ResponsiveUtils.spacing(context, 4)),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: ResponsiveUtils.fontSize(context, 13),
                          color: AppTheme.sub(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isVerified == true)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveUtils.spacing(context, 8),
                      vertical: ResponsiveUtils.spacing(context, 4),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t('Verified', 'مُتحقق'),
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: ResponsiveUtils.fontSize(context, 11),
                      ),
                    ),
                  ),
                if (!isActive)
                  Container(
                    margin: EdgeInsets.only(left: ResponsiveUtils.spacing(context, 6)),
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveUtils.spacing(context, 8),
                      vertical: ResponsiveUtils.spacing(context, 4),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t('Disabled', 'معطل'),
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: ResponsiveUtils.fontSize(context, 11),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            if (phone.isNotEmpty) ...[
              Text(
                t('Phone: ', 'الهاتف: ') + phone,
                style: TextStyle(
                  color: AppTheme.sub(isDark),
                  fontSize: ResponsiveUtils.fontSize(context, 13),
                ),
              ),
              SizedBox(height: ResponsiveUtils.spacing(context, 8)),
            ],
            if (createdAt != null) ...[
              Text(
                t('Joined: ', 'انضم في: ') + _formatDate(createdAt.toDate()),
                style: TextStyle(
                  color: AppTheme.sub(isDark),
                  fontSize: ResponsiveUtils.fontSize(context, 12),
                ),
              ),
              SizedBox(height: ResponsiveUtils.spacing(context, 8)),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleUserActive(context, userId, isActive),
                    icon: Icon(isActive ? Icons.block_rounded : Icons.check_circle_rounded),
                    label: Text(
                      isActive ? t('Disable', 'تعطيل') : t('Enable', 'تفعيل'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isActive ? Colors.orange : Colors.green,
                      side: BorderSide(color: isActive ? Colors.orange : Colors.green),
                      textStyle: TextStyle(
                        fontSize: ResponsiveUtils.fontSize(context, 14),
                        fontWeight: FontWeight.w700,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.spacing(context, 8),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveUtils.spacing(context, 8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _viewUserDetails(context, user),
                    icon: const Icon(Icons.visibility_rounded),
                    label: Text(
                      t('View', 'عرض'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      textStyle: TextStyle(
                        fontSize: ResponsiveUtils.fontSize(context, 14),
                        fontWeight: FontWeight.w700,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.spacing(context, 8),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveUtils.spacing(context, 8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteUser(context, userId),
                    icon: const Icon(Icons.delete_rounded),
                    label: Text(
                      t('Delete', 'حذف'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red),
                      textStyle: TextStyle(
                        fontSize: ResponsiveUtils.fontSize(context, 14),
                        fontWeight: FontWeight.w700,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.spacing(context, 8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleUserActive(BuildContext context, String userId, bool isActive) async {
    try {
      await _firestore.collection(_userType).doc(userId).update({
        'isActive': !isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !isActive
                  ? t('User enabled successfully', 'تم تفعيل المستخدم بنجاح')
                  : t('User disabled successfully', 'تم تعطيل المستخدم بنجاح'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('Error: ', 'خطأ: ')}${e.toString()}')),
        );
      }
    }
  }

  void _viewUserDetails(BuildContext context, Map<String, dynamic> user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDoctor = _userType == 'doctors';

    // Extract doctor-specific fields
    final graduationDate = user['graduationDate'] ?? user['graduation_date'];
    final certificateUrl = user['certificateUrl'] as String?;
    final rawQualifications = user['qualifications'];
    final List<Map<String, dynamic>> qualifications = rawQualifications is List
        ? rawQualifications.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Doctor Details', 'تفاصيل الطبيب')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name
                _detailRow(t('Name', 'الاسم'), '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(), isDark),
                const SizedBox(height: 12),
                // Email
                _detailRow(t('Email', 'البريد الإلكتروني'), user['email']?.toString() ?? '-', isDark),
                const SizedBox(height: 12),
                // Registration Date
                _detailRow(t('Registration Date', 'تاريخ التسجيل'), _formatFlexibleDate(user['createdAt']), isDark),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // Graduation Date
                if (isDoctor && graduationDate != null) ...[
                  Text(
                    t('Graduation Date', 'تاريخ التخرج'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFlexibleDate(graduationDate),
                    style: TextStyle(
                      color: AppTheme.sub(isDark),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Certificate image
                if (isDoctor && certificateUrl != null && certificateUrl.isNotEmpty) ...[
                  Text(
                    t('Certificate', 'الشهادة'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      certificateUrl,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Text(
                        t('Unable to load image', 'تعذر تحميل الصورة'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Qualifications list
                if (isDoctor && qualifications.isNotEmpty) ...[
                  Text(
                    t('Qualifications', 'المؤهلات'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...qualifications.map((q) {
                    final name = q['name'] as String? ?? '';
                    final url = q['url'] as String?;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (name.isNotEmpty)
                            Text(
                              name,
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: AppTheme.sub(isDark),
                              ),
                            ),
                          if (url != null && url.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const SizedBox(
                                    height: 120,
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) => Text(
                                  t('Unable to load image', 'تعذر تحميل الصورة'),
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],

                // If nothing to show for doctor
                if (isDoctor &&
                    graduationDate == null &&
                    (certificateUrl == null || certificateUrl.isEmpty) &&
                    qualifications.isEmpty)
                  Text(
                    t('No details available', 'لا توجد تفاصيل'),
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Close', 'إغلاق')),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.text(isDark),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.isNotEmpty ? value : '-',
          style: TextStyle(color: AppTheme.sub(isDark)),
        ),
      ],
    );
  }

  String _formatFlexibleDate(dynamic value) {
    if (value == null) return '-';
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    if (value is String && value.isNotEmpty) {
      // Already DD/MM/YYYY
      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(value)) return value;
      // YYYY-MM-DD
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)) {
        final parts = value.split('-');
        return '${parts[2].substring(0, 2)}/${parts[1]}/${parts[0]}';
      }
      return value;
    }
    return value.toString();
  }

  Future<void> _deleteUser(BuildContext context, String userId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Confirm Delete', 'تأكيد الحذف')),
        content: Text(t('Are you sure you want to delete this user?', 'هل أنت متأكد من حذف هذا المستخدم؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () async {
              try {
                if (_userType == 'doctors') {
                  // Delete all related doctor data
                  // 1. Delete doctor bookings
                  final bookingsSnapshot = await _firestore
                      .collection('doctors')
                      .doc(userId)
                      .collection('bookings')
                      .get();
                  for (var doc in bookingsSnapshot.docs) {
                    await doc.reference.delete();
                  }

                  // 2. Delete doctor availability slots
                  final slotsSnapshot = await _firestore
                      .collection('doctors')
                      .doc(userId)
                      .collection('availability_slots')
                      .get();
                  for (var doc in slotsSnapshot.docs) {
                    await doc.reference.delete();
                  }

                  // 3. Delete all doctor-patient chats where this doctor is involved
                  final chatsSnapshot = await _firestore
                      .collection('doctor_patient_chats')
                      .where('doctorId', isEqualTo: userId)
                      .get();
                  for (var doc in chatsSnapshot.docs) {
                    // Delete all messages in this chat first
                    final messagesSnapshot = await doc.reference.collection('messages').get();
                    for (var msgDoc in messagesSnapshot.docs) {
                      await msgDoc.reference.delete();
                    }
                    // Then delete the chat document
                    await doc.reference.delete();
                  }
                }

                // 4. Delete the user document itself
                await _firestore.collection(_userType).doc(userId).delete();
                
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _userType == 'doctors'
                            ? t('Doctor and all related data deleted', 'تم حذف الدكتور وجميع بيانته')
                            : t('User deleted', 'تم حذف المستخدم'),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        t('Error: ', 'خطأ: ') + e.toString(),
                      ),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: Text(t('Delete', 'حذف'), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
