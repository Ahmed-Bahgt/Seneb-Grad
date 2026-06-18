import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_form_field.dart';

/// Doctor Registration Screen - Multi-Step Registration
class DoctorRegistrationScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onReturnToLogin;
  final VoidCallback onBack;

  const DoctorRegistrationScreen({
    super.key,
    required this.onSuccess,
    required this.onReturnToLogin,
    required this.onBack,
  });

  @override
  State<DoctorRegistrationScreen> createState() =>
      _DoctorRegistrationScreenState();
}

class _DoctorRegistrationScreenState extends State<DoctorRegistrationScreen> {
  int currentStep = 0;
  final _formKey = GlobalKey<FormState>();

  void nextStep() {
    setState(() {
      if (currentStep < 2) {
        currentStep++;
      } else {
        widget.onSuccess();
      }
    });
  }

  void previousStep() {
    setState(() {
      if (currentStep > 0) {
        currentStep--;
      } else {
        widget.onBack();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padding = ResponsiveUtils.padding(context, 24);
    final spacing = ResponsiveUtils.spacing(context, 30);
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: CustomAppBar(
        title: t('Doctor Registration - Step ${currentStep + 1} of 3',
            'تسجيل الطبيب - الخطوة ${currentStep + 1} من 3'),
        onBack: currentStep == 0 ? widget.onBack : previousStep,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Column(
          children: [
            _buildStepProgress(),
            SizedBox(height: spacing),
            Form(
              key: _formKey,
              child: _buildCurrentStep(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepProgress() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(3, (index) {
        bool isCurrent = index == currentStep;
        bool isCompleted = index < currentStep;

        return Expanded(
          child: Container(
            height: 8,
            margin: EdgeInsets.only(right: index < 2 ? ResponsiveUtils.spacing(context, 8) : 0),
            decoration: BoxDecoration(
              color: isCompleted
                  ? const Color(0xFF8BC34A)
                  : isCurrent
                      ? const Color(0xFF00BCD4)
                      : const Color(0xFF4C4C4C),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCurrentStep() {
    switch (currentStep) {
      case 0:
        return Step1PrimaryInfo(onNext: nextStep);
      case 1:
        return Step2PrimaryQualification(
            onPrevious: previousStep, onNext: nextStep);
      case 2:
        return Step3AdditionalQualification(
            onPrevious: previousStep, onCreateAccount: nextStep);
      default:
        return Container();
    }
  }
}

class Step1PrimaryInfo extends StatelessWidget {
  final VoidCallback onNext;

  const Step1PrimaryInfo({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spacing = ResponsiveUtils.spacing(context, 20);
    final buttonSpacing = ResponsiveUtils.spacing(context, 16);
    final largeSpacing = ResponsiveUtils.spacing(context, 40);
    final fontSize = ResponsiveUtils.fontSize(context, 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('Enter your primary account details.', 'أدخل تفاصيل حسابك الأساسية'),
            style: TextStyle(fontSize: fontSize, color: AppTheme.sub(isDark))),
        SizedBox(height: spacing),
        Row(
          children: [
            Expanded(child: CustomFormField(t('First Name', 'الاسم الأول'))),
            SizedBox(width: buttonSpacing),
            Expanded(child: CustomFormField(t('Last Name', 'اسم العائلة'))),
          ],
        ),
        CustomFormField(
            t('Email', 'البريد الإلكتروني'), keyboardType: TextInputType.emailAddress),
        CustomFormField(
            t('Phone Number', 'رقم الهاتف'), keyboardType: TextInputType.phone),
        CustomFormField(t('Password', 'كلمة المرور'), isPassword: true),
        CustomFormField(t('Confirm Password', 'تأكيد كلمة المرور'), isPassword: true),
        SizedBox(height: largeSpacing),
        SizedBox(
          height: ResponsiveUtils.buttonHeight(context),
          width: double.infinity,
          child: GradientButton(text: t('Next', 'التالي'), onPressed: onNext),
        ),
      ],
    );
  }
}

class Step2PrimaryQualification extends StatefulWidget {
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const Step2PrimaryQualification({
    super.key,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  State<Step2PrimaryQualification> createState() => _Step2PrimaryQualificationState();
}

class _Step2PrimaryQualificationState extends State<Step2PrimaryQualification> {
  File? _certificateImage;
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _gradDateController;

  @override
  void initState() {
    super.initState();
    _gradDateController = TextEditingController();
  }

  @override
  void dispose() {
    _gradDateController.dispose();
    super.dispose();
  }

  Future<void> _pickCertificate() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        var status = await Permission.photos.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        if (!status.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t(
                'Permission to access gallery is required',
                'صلاحية الوصول لمعرض الصور مطلوبة',
              )),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (pickedFile != null) {
        final fileSize = await pickedFile.length();
        const maxSize = 5 * 1024 * 1024; // 5MB

        if (fileSize > maxSize) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t(
                'File size exceeds 5MB limit',
                'حجم الملف يتجاوز حد 5 ميجابايت',
              )),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        setState(() {
          _certificateImage = File(pickedFile.path);
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t(
              'Certificate uploaded successfully',
              'تم تحميل الشهادة بنجاح',
            )),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t(
            'Error picking image: $e',
            'خطأ في اختيار الصورة: $e',
          )),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickGraduationDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 1),
    );

    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _gradDateController.text = formatted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spacing = ResponsiveUtils.spacing(context, 20);
    final smallSpacing = ResponsiveUtils.spacing(context, 8);
    final fontSize = ResponsiveUtils.fontSize(context, 16);
    final smallFontSize = ResponsiveUtils.fontSize(context, 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('Primary Qualification Details', 'تفاصيل المؤهل الأساسي'),
            style: TextStyle(fontSize: fontSize, color: AppTheme.sub(isDark))),
        SizedBox(height: spacing),
        CustomFormField(t('University Name', 'اسم الجامعة')),
        Padding(
          padding: EdgeInsets.symmetric(vertical: smallSpacing),
          child: TextFormField(
            controller: _gradDateController,
            readOnly: true,
            onTap: () => _pickGraduationDate(context),
            decoration: InputDecoration(
              labelText: t('Graduation Date', 'تاريخ التخرج'),
              suffixIcon: const Icon(Icons.calendar_today),
              labelStyle: TextStyle(color: AppTheme.sub(isDark)),
            ),
            style: TextStyle(color: isDark ? const Color(0xFFDEE2E6) : Colors.black87),
          ),
        ),
        SizedBox(height: spacing),
        Text(t('Graduation Certificate', 'شهادة التخرج'),
            style: TextStyle(fontSize: smallFontSize, color: const Color(0xFF00BCD4))),
        SizedBox(height: smallSpacing),
        GestureDetector(
          onTap: _pickCertificate,
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.card(isDark) : AppTheme.card(isDark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _certificateImage != null
                    ? const Color(0xFF8BC34A)
                    : (isDark ? Colors.white12 : Colors.grey[300]!),
                width: 2,
              ),
            ),
            child: _certificateImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      _certificateImage!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.cloud_upload_rounded,
                            color: Color(0xFF8BC34A), size: 40),
                        onPressed: _pickCertificate,
                      ),
                      Text(
                        t('Tap to upload Photo', 'انقر لتحميل الصورة'),
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                          fontSize: ResponsiveUtils.fontSize(context, 14),
                        ),
                      ),
                      SizedBox(height: ResponsiveUtils.spacing(context, 4)),
                      Text(
                        t('(Max 5MB)', '(الحد الأقصى 5 ميجابايت)'),
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey[500],
                          fontSize: ResponsiveUtils.fontSize(context, 12),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        SizedBox(height: ResponsiveUtils.spacing(context, 40)),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: ResponsiveUtils.buttonHeight(context),
                child: OutlinedButton(
                  onPressed: widget.onPrevious,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Color(0xFF00BCD4)),
                  ),
                  child: Text(t('Previous', 'السابق'),
                      style: const TextStyle(color: Color(0xFF00BCD4))),
                ),
              ),
            ),
            SizedBox(width: ResponsiveUtils.spacing(context, 16)),
            Expanded(
              child: SizedBox(
                height: ResponsiveUtils.buttonHeight(context),
                child: GradientButton(text: t('Next', 'التالي'), onPressed: widget.onNext),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class Step3AdditionalQualification extends StatefulWidget {
  final VoidCallback onPrevious;
  final VoidCallback onCreateAccount;

  const Step3AdditionalQualification({
    super.key,
    required this.onPrevious,
    required this.onCreateAccount,
  });

  @override
  State<Step3AdditionalQualification> createState() =>
      _Step3AdditionalQualificationState();
}

class _Step3AdditionalQualificationState
    extends State<Step3AdditionalQualification> {
  List<int> qualifications = [0];
  Map<int, File?> certificateImages = {};
  final ImagePicker _imagePicker = ImagePicker();

  void addQualification() {
    setState(() {
      qualifications.add(qualifications.isEmpty ? 0 : qualifications.last + 1);
    });
  }

  void removeQualification(int id) {
    setState(() {
      qualifications.removeWhere((qId) => qId == id);
      certificateImages.remove(id);
    });
  }

  Future<void> _pickCertificate(int qualificationId) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        var status = await Permission.photos.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        if (!status.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t(
                'Permission to access gallery is required',
                'صلاحية الوصول لمعرض الصور مطلوبة',
              )),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (pickedFile != null) {
        final fileSize = await pickedFile.length();
        const maxSize = 5 * 1024 * 1024; // 5MB

        if (fileSize > maxSize) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t(
                'File size exceeds 5MB limit',
                'حجم الملف يتجاوز حد 5 ميجابايت',
              )),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        setState(() {
          certificateImages[qualificationId] = File(pickedFile.path);
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t(
              'Certificate uploaded successfully',
              'تم تحميل الشهادة بنجاح',
            )),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t(
            'Error picking image: $e',
            'خطأ في اختيار الصورة: $e',
          )),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildQualificationEntry(int id, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: ValueKey(id),
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('${t('Qualification ', 'المؤهل ')}${index + 1}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8BC34A))),
              ),
              if (qualifications.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent, size: 24),
                  onPressed: () => removeQualification(id),
                  tooltip: 'Remove Qualification',
                ),
            ],
          ),
          const SizedBox(height: 10),
          CustomFormField(t('Degree Name / Diploma', 'اسم الدرجة / الدبلوم')),
          const SizedBox(height: 16),
          Text(t('Upload Certificate Photo', 'ارفع صورة الشهادة'),
              style: const TextStyle(fontSize: 14, color: Color(0xFF00BCD4))),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _pickCertificate(id),
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.bg(isDark) : AppTheme.card(isDark),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: certificateImages[id] != null
                      ? const Color(0xFF8BC34A)
                      : (isDark ? Colors.white12 : Colors.grey[300]!),
                  width: 2,
                ),
              ),
              child: certificateImages[id] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        certificateImages[id]!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_a_photo,
                          color: Color(0xFF8BC34A),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('Tap to upload', 'انقر للتحميل'),
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('Add any additional professional degrees or diplomas.',
            'أضف أي درجات أو شهادات مهنية إضافية'),
            style: TextStyle(fontSize: 16, color: AppTheme.sub(isDark))),
        const SizedBox(height: 20),
        ...qualifications.asMap().entries.map((entry) {
          int index = entry.key;
          int id = entry.value;
          return _buildQualificationEntry(id, index);
        }),
        Center(
          child: OutlinedButton.icon(
            onPressed: addQualification,
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: Color(0xFF8BC34A)),
            label: Text(t('Add Another Qualification', 'إضافة مؤهل آخر'),
                style: const TextStyle(color: Color(0xFF8BC34A), fontSize: 16)),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: Color(0xFF8BC34A)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onPrevious,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFF00BCD4)),
                ),
                child: Text(t('Previous', 'السابق'),
                    style: const TextStyle(color: Color(0xFF00BCD4))),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GradientButton(
                text: t('Create Account', 'إنشاء حساب'),
                onPressed: widget.onCreateAccount,
                startColor: const Color(0xFF8BC34A),
                endColor: const Color(0xFF689F38),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
