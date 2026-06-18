import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/custom_app_bar.dart';

/// Role Selection Screen - Choose between doctor and patient registration
class RoleSelectionScreen extends StatelessWidget {
  final VoidCallback onSelectDoctor;
  final VoidCallback onSelectPatient;
  final VoidCallback onBack;

  const RoleSelectionScreen({
    super.key,
    required this.onSelectDoctor,
    required this.onSelectPatient,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: CustomAppBar(title: t('Choose Your Role', 'اختر دورك'), onBack: onBack),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveUtils.maxContentWidth(context),
          ),
          child: Padding(
            padding: ResponsiveUtils.horizontalPadding(context).copyWith(
              top: ResponsiveUtils.padding(context, 24),
              bottom: ResponsiveUtils.padding(context, 24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  t('Are you registering as a Doctor or Patient?',
                    'هل تسجل كطبيب أم كمريض؟'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: ResponsiveUtils.fontSize(context, 18),
                      color: AppTheme.sub(isDark)),
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 40)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmallScreen = ResponsiveUtils.width(context) < 360;
                      return isSmallScreen
                          ? Column(
                              children: <Widget>[
                                Expanded(
                                  child: RoleCard(
                                    title: t("I'm a Doctor", "أنا طبيب"),
                                    icon: Icons.local_hospital_rounded,
                                    onTap: onSelectDoctor,
                                    color: const Color(0xFF00BCD4),
                                  ),
                                ),
                                SizedBox(height: ResponsiveUtils.spacing(context, 20)),
                                Expanded(
                                  child: RoleCard(
                                    title: t("I'm a Patient", "أنا مريض"),
                                    icon: Icons.self_improvement_rounded,
                                    onTap: onSelectPatient,
                                    color: const Color(0xFF8BC34A),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: <Widget>[
                                Expanded(
                                  child: RoleCard(
                                    title: t("I'm a Doctor", "أنا طبيب"),
                                    icon: Icons.local_hospital_rounded,
                                    onTap: onSelectDoctor,
                                    color: const Color(0xFF00BCD4),
                                  ),
                                ),
                                SizedBox(width: ResponsiveUtils.spacing(context, 20)),
                                Expanded(
                                  child: RoleCard(
                                    title: t("I'm a Patient", "أنا مريض"),
                                    icon: Icons.self_improvement_rounded,
                                    onTap: onSelectPatient,
                                    color: const Color(0xFF8BC34A),
                                  ),
                                ),
                              ],
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Role Card Widget - Selectable card for doctor/patient choice
class RoleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const RoleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardPadding = ResponsiveUtils.padding(context, 20);
    final borderRadius = ResponsiveUtils.spacing(context, 20);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: colorWithOpacity(color, 0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: colorWithOpacity(color, 0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: ResponsiveUtils.iconSize(context, 60), color: color),
            SizedBox(height: ResponsiveUtils.spacing(context, 15)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 20),
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
