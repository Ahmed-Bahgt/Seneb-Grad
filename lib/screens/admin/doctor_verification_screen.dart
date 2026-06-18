import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';

/// Doctor Verification Screen - Admin can approve/reject pending doctors
class DoctorVerificationScreen extends StatefulWidget {
  const DoctorVerificationScreen({super.key});

  @override
  State<DoctorVerificationScreen> createState() =>
      _DoctorVerificationScreenState();
}

class _DoctorVerificationScreenState extends State<DoctorVerificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirebaseFirestore.instance;

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
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Text(t('Doctor Approvals', 'موافقات الأطباء')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t('Pending', 'قيد الانتظار')),
            Tab(text: t('Rejected', 'مرفوض')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingTab(isDark),
          _buildRejectedTab(isDark),
        ],
      ),
    );
  }

  Widget _buildPendingTab(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('doctors')
          .where('isVerified', isEqualTo: false)
          .where('approvalStatus', isEqualTo: 'pending')
          .snapshots(),
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
            child: Text(t('No pending doctors', 'لا توجد أطباء قيد الانتظار')),
          );
        }

        final doctors = snapshot.data!.docs;

        return ListView.builder(
          padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
          itemCount: doctors.length,
          itemBuilder: (context, index) {
            final doctor = doctors[index].data() as Map<String, dynamic>;
            final doctorId = doctors[index].id;
            return _buildDoctorCard(
              context,
              doctor,
              doctorId,
              isDark,
              isPending: true,
            );
          },
        );
      },
    );
  }

  Widget _buildRejectedTab(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('doctors')
          .where('approvalStatus', isEqualTo: 'rejected')
          .snapshots(),
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
            child: Text(t('No rejected doctors', 'لا توجد أطباء مرفوضة')),
          );
        }

        final doctors = snapshot.data!.docs;

        return ListView.builder(
          padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
          itemCount: doctors.length,
          itemBuilder: (context, index) {
            final doctor = doctors[index].data() as Map<String, dynamic>;
            final doctorId = doctors[index].id;
            return _buildDoctorCard(
              context,
              doctor,
              doctorId,
              isDark,
              isPending: false,
            );
          },
        );
      },
    );
  }

  Widget _buildDoctorCard(
    BuildContext context,
    Map<String, dynamic> doctor,
    String doctorId,
    bool isDark, {
    required bool isPending,
  }) {
    final firstName = doctor['firstName'] as String? ?? '';
    final lastName = doctor['lastName'] as String? ?? '';
    final email = doctor['email'] as String? ?? '';
    final graduationDateValue = doctor['graduationDate'] ?? doctor['graduation_date'];
    final certificateUrl = doctor['certificateUrl'] as String?;
    final rejectionReason = doctor['rejectionReason'] as String?;

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
                          fontSize: ResponsiveUtils.fontSize(context, 18),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.text(isDark),
                        ),
                      ),
                      SizedBox(height: ResponsiveUtils.spacing(context, 4)),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: ResponsiveUtils.fontSize(context, 14),
                          color: AppTheme.sub(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isPending)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveUtils.spacing(context, 12),
                      vertical: ResponsiveUtils.spacing(context, 4),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t('Pending', 'قيد الانتظار'),
                      style: TextStyle(
                        color: Colors.amber[700],
                        fontWeight: FontWeight.bold,
                        fontSize: ResponsiveUtils.fontSize(context, 12),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveUtils.spacing(context, 12),
                      vertical: ResponsiveUtils.spacing(context, 4),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t('Rejected', 'مرفوض'),
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: ResponsiveUtils.fontSize(context, 12),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            if (graduationDateValue != null) ...[
              Text(
                '${t('Graduation Date: ', 'تاريخ التخرج: ')} ${_formatFlexibleDate(graduationDateValue)}',
                style: TextStyle(
                  color: AppTheme.sub(isDark),
                ),
              ),
              SizedBox(height: ResponsiveUtils.spacing(context, 8)),
            ],
            if (!isPending && rejectionReason != null && rejectionReason.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(ResponsiveUtils.padding(context, 10)),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Rejection Reason:', 'سبب الرفض:'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    SizedBox(height: ResponsiveUtils.spacing(context, 4)),
                    Text(
                      rejectionReason,
                      style: TextStyle(
                        color: AppTheme.sub(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            ],
            Row(
              children: [
                if (certificateUrl != null && certificateUrl.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showCertificateDialog(context, certificateUrl),
                      icon: const Icon(Icons.image_rounded),
                      label: Text(t('Certificate', 'الشهادة')),
                    ),
                  ),
                if (certificateUrl != null && certificateUrl.isNotEmpty)
                  SizedBox(width: ResponsiveUtils.spacing(context, 8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showDoctorDetailsDialog(context, doctor, doctorId),
                    icon: const Icon(Icons.info_rounded),
                    label: Text(t('Details', 'التفاصيل')),
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            if (isPending)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveDoctor(context, doctorId),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(t('Approve', 'الموافقة')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveUtils.spacing(context, 8)),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _rejectDoctor(context, doctorId),
                      icon: const Icon(Icons.close_rounded),
                      label: Text(t('Reject', 'الرفض')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _reapproveDoctor(context, doctorId),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(t('Re-Approve', 'إعادة الموافقة')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveUtils.spacing(context, 8)),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _deleteDoctor(context, doctorId),
                      icon: const Icon(Icons.delete_rounded),
                      label: Text(t('Delete', 'حذف')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
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

  Future<void> _approveDoctor(BuildContext context, String doctorId) async {
    try {
      await _firestore.collection('doctors').doc(doctorId).update({
        'isVerified': true,
        'approvalStatus': 'approved',
        'verifiedAt': FieldValue.serverTimestamp(),
        'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Doctor approved successfully', 'تم الموافقة على الطبيب'))),
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

  Future<void> _rejectDoctor(BuildContext context, String doctorId) async {
    showDialog(
      context: context,
      builder: (context) => _RejectionDialog(
        onSubmit: (reason) async {
          // Dialog already popped itself before calling onSubmit — do NOT pop again
          try {
            await _firestore.collection('doctors').doc(doctorId).update({
              'isVerified': false,
              'approvalStatus': 'rejected',
              'rejectionReason': reason,
              'rejectedAt': FieldValue.serverTimestamp(),
              'rejectedBy': FirebaseAuth.instance.currentUser?.uid,
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('Doctor rejected', 'تم رفض الطبيب'))),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${t('Error: ', 'خطأ: ')}${e.toString()}')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _reapproveDoctor(BuildContext context, String doctorId) async {
    try {
      await _firestore.collection('doctors').doc(doctorId).update({
        'isVerified': true,
        'approvalStatus': 'approved',
        'verifiedAt': FieldValue.serverTimestamp(),
        'rejectionReason': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Doctor re-approved', 'تم إعادة الموافقة'))),
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

  Future<void> _deleteDoctor(BuildContext context, String doctorId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Confirm Delete', 'تأكيد الحذف')),
        content: Text(t('Are you sure you want to delete this doctor?', 'هل أنت متأكد من حذف هذا الطبيب؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _firestore.collection('doctors').doc(doctorId).delete();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t('Doctor deleted', 'تم حذف الطبيب'))),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${t('Error: ', 'خطأ: ')}${e.toString()}')),
                  );
                }
              }
            },
            child: Text(t('Delete', 'حذف'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCertificateDialog(BuildContext context, String certificateUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Certificate', 'الشهادة')),
        content: SingleChildScrollView(
          child: Image.network(
            certificateUrl,
            errorBuilder: (context, error, stackTrace) => Text(
              t('Unable to load certificate', 'لا يمكن تحميل الشهادة'),
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

  void _showDoctorDetailsDialog(BuildContext context, Map<String, dynamic> doctor, String doctorId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final graduationDate =
        doctor['graduationDate'] ?? doctor['graduation_date'] ?? doctor['certificationDate'] ?? doctor['degree'];
    final registrationDate = doctor['createdAt'] ?? doctor['submittedAt'];
    final updatedDate = doctor['updatedAt'];

    final rawQualifications = doctor['qualifications'];
    final List<Map<String, dynamic>> qualifications = rawQualifications is List
        ? rawQualifications.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [];

    final details = <MapEntry<String, String>>[
      MapEntry('First Name', (doctor['firstName'] as String?)?.trim().isNotEmpty == true ? doctor['firstName'].toString() : '-'),
      MapEntry('Last Name', (doctor['lastName'] as String?)?.trim().isNotEmpty == true ? doctor['lastName'].toString() : '-'),
      MapEntry('Email', (doctor['email'] as String?)?.trim().isNotEmpty == true ? doctor['email'].toString() : '-'),
      MapEntry('Graduation Date', _formatFlexibleDate(graduationDate)),
      MapEntry('Registration Date', _formatFlexibleDate(registrationDate)),
      MapEntry('Updated Date', _formatFlexibleDate(updatedDate)),
    ];
    
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
                // Text details
                ...details.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.text(isDark),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.value,
                          style: TextStyle(
                            color: AppTheme.sub(isDark),
                            fontSize: 13,
                          ),
                        ),
                        const Divider(height: 16),
                      ],
                    ),
                  );
                }),

                // Qualifications section
                if (qualifications.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    t('Qualifications', 'المؤهلات'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                                fontSize: 13,
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
                                  style: const TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
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

  String _formatFlexibleDate(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    if (value is DateTime) {
      return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    }

    if (value is String && value.trim().isNotEmpty) {
      final str = value.trim();
      // Already in DD/MM/YYYY format
      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(str)) return str;
      // ISO format YYYY-MM-DD
      final parsed = DateTime.tryParse(str);
      if (parsed != null) {
        return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
      }
      return str;
    }

    return '-';
  }
}

class _RejectionDialog extends StatefulWidget {
  final Function(String) onSubmit;

  const _RejectionDialog({required this.onSubmit});

  @override
  State<_RejectionDialog> createState() => _RejectionDialogState();
}

class _RejectionDialogState extends State<_RejectionDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Reject Doctor', 'رفض الطبيب')),
      content: TextField(
        controller: _reasonCtrl,
        decoration: InputDecoration(
          labelText: t('Reason', 'السبب'),
          hintText: t('Enter rejection reason', 'أدخل سبب الرفض'),
          border: const OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Cancel', 'إلغاء')),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onSubmit(_reasonCtrl.text.trim());
          },
          child: Text(t('Reject', 'رفض')),
        ),
      ],
    );
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
