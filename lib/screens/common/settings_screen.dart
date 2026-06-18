import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';

// --- SETTINGS SCREEN ---
class SettingsScreen extends StatefulWidget {
  final ThemeProvider? themeProvider;
  final VoidCallback? onBack;

  const SettingsScreen({super.key, this.themeProvider, this.onBack});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _isDarkMode;
  late String _language;
  late bool _notificationsEnabled;
  late String _displayName;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.themeProvider?.isDarkMode ?? true;
    _language = widget.themeProvider?.language ?? 'en';
    _notificationsEnabled = true;
    _displayName = widget.themeProvider?.displayName ?? '';
    
    // Load user profile if not already loaded
    if (_displayName.isEmpty) {
      widget.themeProvider?.loadUserProfile().then((_) {
        if (mounted) {
          setState(() {
            _displayName = widget.themeProvider?.displayName ?? 'User';
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.themeProvider?.isDarkMode ?? true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.bg(isDarkMode),
        elevation: 1,
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).colorScheme.primary),
          onPressed: widget.onBack ?? () => Navigator.pop(context),
        ),
        title: Text(
          t('Settings', 'الإعدادات'),
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.text(isDarkMode)),
        ),
      ),
      backgroundColor: AppTheme.bg(isDarkMode),
      body: Center(
        child: SingleChildScrollView(
          padding: ResponsiveUtils.horizontalPadding(context).copyWith(
            top: ResponsiveUtils.padding(context, 16),
            bottom: ResponsiveUtils.padding(context, 16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveUtils.maxContentWidth(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(t('Appearance', 'المظهر')),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.dark_mode,
                  title: t('Dark Mode', 'الوضع الليلي'),
                  subtitle: _isDarkMode ? t('Enabled', 'مفعّل') : t('Disabled', 'معطّل'),
                  trailing: Switch(
                    value: _isDarkMode,
                    onChanged: (value) {
                      setState(() => _isDarkMode = value);
                      widget.themeProvider?.toggleTheme();
                    },
                    activeThumbColor: const Color(0xFF00BCD4),
                  ),
                  isDarkMode: isDarkMode,
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSectionTitle(t('Language', 'اللغة')),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildLanguageOptions(isDarkMode),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 24)),
                _buildSectionTitle(t('Notifications', 'الإشعارات')),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.notifications,
                  title: t('Push Notifications', 'إشعارات فورية'),
                  subtitle: t('Receive session reminders and updates', 'احصل على تذكيرات الجلسات والتحديثات'),
                  trailing: Switch(
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() => _notificationsEnabled = value);
                    },
                    activeThumbColor: const Color(0xFF00BCD4),
                  ),
                  isDarkMode: isDarkMode,
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 24)),
                _buildSectionTitle(t('Account & Privacy', 'الحساب والخصوصية')),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.badge,
                  title: t('Display Name', 'الاسم المعروض'),
                  subtitle: _displayName,
                  trailing: const Icon(Icons.edit, color: Color(0xFF00BCD4)),
                  isDarkMode: isDarkMode,
                  onTap: () => _showEditNameDialog(context, isDarkMode),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.person,
                  title: t('Profile', 'الملف الشخصي'),
                  subtitle: t('View and edit your profile', 'عرض وتعديل ملفك الشخصي'),
                  trailing: const Icon(Icons.arrow_forward, color: Color(0xFF00BCD4)),
                  isDarkMode: isDarkMode,
                  onTap: () => _showProfileDialog(context, isDarkMode),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.lock,
                  title: t('Privacy & Security', 'الخصوصية والأمان'),
                  subtitle: t('Change password and manage security', 'غيّر كلمة المرور وإدارة الأمان'),
                  trailing: const Icon(Icons.arrow_forward, color: Color(0xFF00BCD4)),
                  isDarkMode: isDarkMode,
                  onTap: () => _showChangePasswordDialog(context, isDarkMode),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.data_usage,
                  title: t('Data & Storage', 'البيانات والتخزين'),
                  subtitle: t('Manage cache and storage', 'إدارة الذاكرة المؤقتة والتخزين'),
                  trailing: const Icon(Icons.arrow_forward, color: Color(0xFF00BCD4)),
                  isDarkMode: isDarkMode,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Storage management coming soon'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 24)),
                _buildSectionTitle(t('About', 'حول التطبيق')),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.info,
                  title: t('App Version', 'إصدار التطبيق'),
                  subtitle: '1.0.0 (Build 001)',
                  isDarkMode: isDarkMode,
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.description,
                  title: t('Terms & Conditions', 'الشروط والأحكام'),
                  subtitle: t('Read our terms', 'اقرأ شروطنا'),
                  trailing: const Icon(Icons.arrow_forward, color: Color(0xFF00BCD4)),
                  isDarkMode: isDarkMode,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Terms of Service'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                _buildSettingCard(
                  icon: Icons.privacy_tip,
                  title: t('Privacy Policy', 'سياسة الخصوصية'),
                  subtitle: t('Read our privacy policy', 'اقرأ سياسة الخصوصية لدينا'),
                  trailing: const Icon(Icons.arrow_forward, color: Color(0xFF00BCD4)),
                  isDarkMode: isDarkMode,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Privacy Policy'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Color color = const Color(0xFF00BCD4)}) {
    return Text(
      title,
      style: TextStyle(
        fontSize: ResponsiveUtils.fontSize(context, 16),
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required bool isDarkMode,
    VoidCallback? onTap,
    Color? backgroundColor,
  }) {
    final horizontalPadding = ResponsiveUtils.padding(context, 16);
    final verticalPadding = ResponsiveUtils.padding(context, 12);
    final borderRadius = ResponsiveUtils.spacing(context, 12);
    final iconSize = ResponsiveUtils.iconSize(context, 24);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        decoration: BoxDecoration(
          color: backgroundColor ??
              (AppTheme.card(isDarkMode)),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                : const Color(0xFF00BCD4).withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveUtils.spacing(context, 8)),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(ResponsiveUtils.spacing(context, 8)),
              ),
              child: Icon(icon, color: const Color(0xFF00BCD4), size: iconSize),
            ),
            SizedBox(width: ResponsiveUtils.spacing(context, 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: ResponsiveUtils.fontSize(context, 15),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text(isDarkMode),
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: EdgeInsets.only(top: ResponsiveUtils.spacing(context, 4)),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: ResponsiveUtils.fontSize(context, 12),
                          color: AppTheme.sub(isDarkMode),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOptions(bool isDarkMode) {
    return Column(
      children: [
        _buildLanguageButton('English', 'en', isDarkMode),
        SizedBox(height: ResponsiveUtils.spacing(context, 12)),
        _buildLanguageButton('العربية', 'ar', isDarkMode),
      ],
    );
  }

  Widget _buildLanguageButton(String label, String code, bool isDarkMode) {
    final isSelected = _language == code;
    final horizontalPadding = ResponsiveUtils.padding(context, 16);
    final verticalPadding = ResponsiveUtils.padding(context, 14);
    final borderRadius = ResponsiveUtils.spacing(context, 12);
    
    return GestureDetector(
      onTap: () {
        setState(() => _language = code);
        widget.themeProvider?.setLanguage(code);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00BCD4).withValues(alpha: 0.15)
              : (AppTheme.card(isDarkMode)),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00BCD4)
                : (isDarkMode
                    ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                    : const Color(0xFF00BCD4).withValues(alpha: 0.1)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: ResponsiveUtils.fontSize(context, 15),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text(isDarkMode),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF00BCD4), size: 20),
          ],
        ),
      ),
    );
  }

  void _showProfileDialog(BuildContext context, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card(isDarkMode),
        title: Text(
          t('Your Profile', 'ملفك الشخصي'),
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.text(isDarkMode)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileInfo(t('Name', 'الاسم'), _displayName, isDarkMode),
              _buildProfileInfo(t('Email', 'البريد الإلكتروني'), 'doctor@tamrena.com', isDarkMode),
              _buildProfileInfo(t('Phone', 'الهاتف'), '+966501234567', isDarkMode),
              _buildProfileInfo(t('Member Since', 'عضو منذ'), '2024-10-15', isDarkMode),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Close', 'إغلاق'), style: const TextStyle(color: Color(0xFF00BCD4))),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo(String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.sub(isDarkMode),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.text(isDarkMode),
            ),
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, bool isDarkMode) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          int step = 0;
          return AlertDialog(
            backgroundColor: AppTheme.card(isDarkMode),
            title: Text(
              step == 0 ? t('Verify Current Password', 'تحقق من كلمة المرور الحالية') : t('Set New Password', 'تعيين كلمة مرور جديدة'),
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.text(isDarkMode)),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (step == 0)
                    TextField(
                      controller: currentPasswordController,
                      obscureText: true,
                      style: TextStyle(color: AppTheme.text(isDarkMode)),
                      decoration: InputDecoration(
                        labelText: t('Current Password', 'كلمة المرور الحالية'),
                        labelStyle: TextStyle(color: AppTheme.sub(isDarkMode)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF00BCD4), width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        TextField(
                          controller: newPasswordController,
                          obscureText: true,
                          style: TextStyle(color: AppTheme.text(isDarkMode)),
                          decoration: InputDecoration(
                            labelText: t('New Password', 'كلمة مرور جديدة'),
                            labelStyle: TextStyle(color: AppTheme.sub(isDarkMode)),
                            helperText: t('At least 8 characters', 'على الأقل 8 أحرف'),
                            helperStyle: TextStyle(color: isDarkMode ? Colors.grey[500] : Colors.grey[600]),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Color(0xFF00BCD4), width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: true,
                          style: TextStyle(color: AppTheme.text(isDarkMode)),
                          decoration: InputDecoration(
                            labelText: t('Confirm Password', 'تأكيد كلمة المرور'),
                            labelStyle: TextStyle(color: AppTheme.sub(isDarkMode)),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Color(0xFF00BCD4), width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('Cancel', 'إلغاء'), style: const TextStyle(color: Color(0xFF00BCD4))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BCD4)),
                onPressed: () {
                  if (step == 0) {
                    if (currentPasswordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('Enter current password', 'أدخل كلمة المرور الحالية'))),
                      );
                      return;
                    }
                    setState(() => step = 1);
                  } else {
                    if (newPasswordController.text.isEmpty || confirmPasswordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('All fields required', 'جميع الحقول مطلوبة'))),
                      );
                      return;
                    }
                    if (newPasswordController.text.length < 8) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('Password too short', 'كلمة المرور قصيرة جداً'))),
                      );
                      return;
                    }
                    if (newPasswordController.text != confirmPasswordController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('Passwords do not match', 'كلمات المرور غير متطابقة'))),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t('Password changed successfully', 'تم تغيير كلمة المرور بنجاح'))),
                    );
                  }
                },
                child: Text(step == 0 ? t('Verify', 'تحقق') : t('Update Password', 'تحديث كلمة المرور'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, bool isDarkMode) {
    final controller = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card(isDarkMode),
        title: Text(t('Edit Display Name', 'تعديل الاسم المعروض')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: t('Name', 'الاسم'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Cancel', 'إلغاء'), style: const TextStyle(color: Color(0xFF00BCD4))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BCD4)),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t('Name cannot be empty', 'لا يمكن أن يكون الاسم فارغاً'))),
                );
                return;
              }
              widget.themeProvider?.setDisplayName(newName);
              setState(() => _displayName = newName);
              Navigator.pop(context);
            },
            child: Text(t('Save', 'حفظ'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
