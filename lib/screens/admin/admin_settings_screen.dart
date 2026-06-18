import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';
import '../../services/sql_service.dart';

/// Admin Settings Screen - Admin profile, password change, and create new admins
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Text(t('Admin Settings', 'إعدادات الإدمن')),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
        child: Column(
          children: [
            _buildAdminProfileCard(context, isDark),
            SizedBox(height: ResponsiveUtils.spacing(context, 24)),
            _buildChangePasswordCard(context, isDark),
            SizedBox(height: ResponsiveUtils.spacing(context, 24)),
            _buildCreateAdminCard(context, isDark),
            SizedBox(height: ResponsiveUtils.spacing(context, 24)),
            _buildExistingAdminsCard(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminProfileCard(BuildContext context, bool isDark) {
    final user = _auth.currentUser;

    return Card(
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Admin Profile', 'ملف الإدمن'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 18),
                fontWeight: FontWeight.bold,
                color: AppTheme.text(isDark),
              ),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            Text(
              t('Email: ', 'البريد: ') + (user?.email ?? 'N/A'),
              style: TextStyle(
                color: AppTheme.sub(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangePasswordCard(BuildContext context, bool isDark) {
    return Card(
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Change Password', 'تغيير كلمة المرور'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 18),
                fontWeight: FontWeight.bold,
                color: AppTheme.text(isDark),
              ),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showChangePasswordDialog(context),
                icon: const Icon(Icons.lock_rounded),
                label: Text(t('Change Password', 'تغيير كلمة المرور')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateAdminCard(BuildContext context, bool isDark) {
    return Card(
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Create New Admin', 'إنشاء إدمن جديد'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 18),
                fontWeight: FontWeight.bold,
                color: AppTheme.text(isDark),
              ),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showCreateAdminDialog(context),
                icon: const Icon(Icons.person_add_rounded),
                label: Text(t('Create Admin', 'إنشاء إدمن')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExistingAdminsCard(BuildContext context, bool isDark) {
    return Card(
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Existing Admins', 'الإدمنز الحاليون'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 18),
                fontWeight: FontWeight.bold,
                color: AppTheme.text(isDark),
              ),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('admins')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Text(
                    t('No admins found', 'لا يوجد إدمنز'),
                    style: TextStyle(
                      color: AppTheme.sub(isDark),
                    ),
                  );
                }

                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final firstName = data['firstName'] as String? ?? '';
                    final lastName = data['lastName'] as String? ?? '';
                    final email = data['email'] as String? ?? '';
                    final isActive = data['isActive'] as bool? ?? true;

                    final currentUid = _auth.currentUser?.uid;
                    final isCurrentAdmin = doc.id == currentUid;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isActive
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          color: isActive ? Colors.green : Colors.orange,
                        ),
                      ),
                      title: Text(
                        '$firstName $lastName'.trim().isEmpty
                            ? t('Admin', 'إدمن')
                            : '$firstName $lastName'.trim(),
                        style: TextStyle(
                          color: AppTheme.text(isDark),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        email,
                        style: TextStyle(
                          color: AppTheme.sub(isDark),
                        ),
                      ),
                      trailing: isCurrentAdmin
                          ? Text(
                              t('You', 'أنت'),
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.delete_rounded, color: Colors.red),
                              tooltip: t('Delete Admin', 'حذف الإدمن'),
                              onPressed: () => _confirmDeleteAdmin(context, doc.id, '$firstName $lastName'.trim()),
                            ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _ChangePasswordDialog(onSubmit: _changePassword),
    );
  }

  void _showCreateAdminDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _CreateAdminDialog(onSubmit: _createAdmin),
    );
  }

  Future<void> _changePassword(
      String currentPassword, String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user?.email == null) {
        _showSnack(t('Error: No email found', 'خطأ: لم يتم العثور على بريد'));
        return;
      }

      // Re-authenticate user
      await user!.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        ),
      );

      // Update password
      await user.updatePassword(newPassword);

      if (mounted) {
        Navigator.pop(context);
        _showSnack(t('Password changed successfully', 'تم تغيير كلمة المرور بنجاح'));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Navigator.pop(context);
        String message;
        if (e.code == 'wrong-password') {
          message = t('Incorrect current password', 'كلمة المرور الحالية غير صحيحة');
        } else {
          message = e.message ?? t('Error changing password', 'خطأ في تغيير كلمة المرور');
        }
        _showSnack(message);
      }
    }
  }

  Future<void> _createAdmin(
    String email,
    String firstName,
    String lastName,
    String phoneNumber,
    String password,
  ) async {
    try {
      // Save the current admin's credentials to re-login after creating new user
      final currentUser = _auth.currentUser;
      final currentEmail = currentUser?.email;

      // Create user account in Firebase Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final newAdminUid = userCredential.user!.uid;

      // Add admin to Firestore
      await _firestore.collection('admins').doc(newAdminUid).set({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phoneNumber': phoneNumber,
        'role': 'admin',
        'isActive': true,
        'permissions': [
          'manage_users',
          'view_analytics',
          'verify_doctors',
          'manage_complaints',
          'manage_admins',
        ],
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentEmail ?? 'unknown',
      });

      // Sync admin to PostgreSQL backend
      try {
        final sqlService = SqlService();
        await sqlService.adminRegister(
          uid: newAdminUid,
          email: email,
          password: password,
          fullName: '$firstName $lastName'.trim(),
        );
        debugPrint('✅ Admin synced to PostgreSQL successfully');
      } catch (sqlError) {
        debugPrint('⚠️ Failed to sync admin to PostgreSQL: $sqlError');
        // Don't fail the whole operation - Firebase admin was created
      }

      if (mounted) {
        Navigator.pop(context);
        _showSnack(t('Admin created successfully', 'تم إنشاء إدمن بنجاح'));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Navigator.pop(context);
        String message;
        if (e.code == 'email-already-in-use') {
          message = t('Email already in use', 'البريد قيد الاستخدام');
        } else {
          message = e.message ?? t('Error creating admin', 'خطأ في إنشاء الإدمن');
        }
        _showSnack(message);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnack(t('Error: ', 'خطأ: ') + e.toString());
      }
    }
  }

  void _confirmDeleteAdmin(BuildContext context, String adminId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Delete Admin', 'حذف الإدمن')),
        content: Text(
          t('Are you sure you want to delete "$name"?', 'هل أنت متأكد من حذف "$name"؟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _firestore.collection('admins').doc(adminId).delete();
                _showSnack(t('Admin deleted successfully', 'تم حذف الإدمن بنجاح'));
              } catch (e) {
                _showSnack(t('Error: ', 'خطأ: ') + e.toString());
              }
            },
            child: Text(
              t('Delete', 'حذف'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  final Function(String, String) onSubmit;

  const _ChangePasswordDialog({required this.onSubmit});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_newPwdCtrl.text != _confirmPwdCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Passwords do not match', 'كلمات المرور غير متطابقة')),
        ),
      );
      return;
    }

    if (_newPwdCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Password must be at least 6 characters', 'كلمة المرور يجب أن تكون 6 أحرف على الأقل')),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    widget.onSubmit(_currentPwdCtrl.text, _newPwdCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Change Password', 'تغيير كلمة المرور')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentPwdCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t('Current Password', 'كلمة المرور الحالية'),
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _newPwdCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t('New Password', 'كلمة المرور الجديدة'),
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _confirmPwdCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t('Confirm Password', 'تأكيد كلمة المرور'),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Cancel', 'إلغاء')),
        ),
        TextButton(
          onPressed: _isLoading ? null : _handleSubmit,
          child: Text(t('Change', 'تغيير')),
        ),
      ],
    );
  }
}

class _CreateAdminDialog extends StatefulWidget {
  final Function(String, String, String, String, String) onSubmit;

  const _CreateAdminDialog({required this.onSubmit});

  @override
  State<_CreateAdminDialog> createState() => _CreateAdminDialogState();
}

class _CreateAdminDialogState extends State<_CreateAdminDialog> {
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_emailCtrl.text.isEmpty ||
        _firstNameCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Please fill all fields', 'يرجى ملء جميع الحقول'))),
      );
      return;
    }

    setState(() => _isLoading = true);
    widget.onSubmit(
      _emailCtrl.text.trim(),
      _firstNameCtrl.text.trim(),
      _lastNameCtrl.text.trim(),
      _phoneCtrl.text.trim(),
      _passwordCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AlertDialog(
        title: Text(t('Create New Admin', 'إنشاء إدمن جديد')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _firstNameCtrl,
              decoration: InputDecoration(
                labelText: t('First Name', 'الاسم الأول'),
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _lastNameCtrl,
              decoration: InputDecoration(
                labelText: t('Last Name', 'اسم العائلة'),
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: t('Email', 'البريد'),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: InputDecoration(
                labelText: t('Phone (Optional)', 'الهاتف (اختياري)'),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t('Password', 'كلمة المرور'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: _isLoading ? null : _handleSubmit,
            child: Text(t('Create', 'إنشاء')),
          ),
        ],
      ),
    );
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
