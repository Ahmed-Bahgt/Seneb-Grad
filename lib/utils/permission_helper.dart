import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'theme_provider.dart';
import 'dart:io';

/// Checks if a permission is granted. If not, shows a premium, explanatory in-app pop-up dialog
/// describing why the permission is needed. If the user clicks "Agree", requests the system permission.
/// If the permission is permanently denied, prompts the user to open settings.
Future<bool> checkAndRequestUploadPermission(
  BuildContext context, {
  required bool isCamera,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return true;
  }

  final permission = isCamera ? Permission.camera : Permission.photos;
  var status = await permission.status;

  if (status.isGranted || status.isLimited) {
    return true;
  }

  // Handle Android special storage status if not photos
  if (!isCamera && Platform.isAndroid) {
    // Check general storage permission as fallback
    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted || storageStatus.isLimited) {
      return true;
    }
  }

  // If permanently denied, show redirect to settings dialog
  if (status.isPermanentlyDenied) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: AppTheme.card(isDark),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.border(isDark)),
            ),
            title: Text(
              t('Permission Required', 'الصلاحية مطلوبة'),
              style: TextStyle(
                color: AppTheme.text(isDark),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              isCamera
                  ? t('Camera permission is permanently denied. Please enable it in system settings to take photos.',
                      'تم رفض صلاحية الكاميرا نهائياً. يرجى تفعيلها من إعدادات النظام لتتمكن من التقاط الصور.')
                  : t('Photo library permission is permanently denied. Please enable it in system settings to select photos.',
                      'تم رفض صلاحية معرض الصور نهائياً. يرجى تفعيلها من إعدادات النظام لتتمكن من اختيار الصور.'),
              style: TextStyle(color: AppTheme.sub(isDark)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  t('Cancel', 'إلغاء'),
                  style: TextStyle(color: AppTheme.sub(isDark)),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyan,
                  foregroundColor: Colors.white,
                ),
                child: Text(t('Open Settings', 'فتح الإعدادات')),
              ),
            ],
          );
        },
      );
    }
    return false;
  }

  // Show a beautifully themed pre-request explanation dialog (Standard Pop-up Message)
  if (!context.mounted) return false;
  
  final bool? userAgreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: AppTheme.cardDeco(isDark, radius: 20),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCamera ? Icons.camera_alt_outlined : Icons.photo_library_outlined,
                  size: 40,
                  color: AppTheme.cyan,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isCamera ? t('Camera Access', 'الوصول إلى الكاميرا') : t('Photos Access', 'الوصول إلى معرض الصور'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text(isDark),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isCamera
                    ? t('This app requires access to your camera so you can take and upload exercise or clinical pictures.',
                        'يتطلب هذا التطبيق الوصول إلى الكاميرا الخاصة بك لتتمكن من التقاط وتحميل صور التمارين أو الصور الطبية.')
                    : t('This app requires access to your photo gallery so you can choose and upload exercise or clinical pictures.',
                        'يتطلب هذا التطبيق الوصول إلى معرض الصور الخاص بك لتتمكن من اختيار وتحميل صور التمارين أو الصور الطبية.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppTheme.sub(isDark),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                        foregroundColor: AppTheme.sub(isDark),
                      ),
                      child: Text(t('Cancel', 'إلغاء')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(t('Agree', 'موافق')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (userAgreed == true) {
    // Request actual system permission
    final newStatus = await permission.request();
    if (newStatus.isGranted || newStatus.isLimited) {
      return true;
    }
    
    // Check fallback for Android storage
    if (!isCamera && Platform.isAndroid) {
      final newStorageStatus = await Permission.storage.request();
      if (newStorageStatus.isGranted || newStorageStatus.isLimited) {
        return true;
      }
    }
  }

  return false;
}
