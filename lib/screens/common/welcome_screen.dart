/// Welcome Screen — fully redesigned & theme responsive.
/// Palette: Dynamic (AppTheme).
/// Admin Login + Dev Test Mode hidden behind 5-tap on version number.
library;

import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';

// Brand constant for consistency
const _kCyan = AppTheme.cyan;

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onLoginDoctor;
  final VoidCallback onLoginPatient;
  final VoidCallback onLoginAdmin;
  final Function(String role) onTestMode;

  const WelcomeScreen({
    super.key,
    required this.onCreateAccount,
    required this.onLoginDoctor,
    required this.onLoginPatient,
    required this.onLoginAdmin,
    required this.onTestMode,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {

  late final AnimationController _pulseCtrl;
  late final AnimationController _entryCtrl;
  late final Animation<double>   _fadeIn;
  late final Animation<Offset>   _slideIn;

  int _tapCount = 0;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    _fadeIn = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutQuart));

    globalThemeProvider.addListener(_rebuild);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    globalThemeProvider.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // ── Hidden 5-tap trigger ────────────────────────────────────────────────────

  void _onVersionTap() {
    _tapCount++;
    if (_tapCount >= 5) {
      _tapCount = 0;
      _showHiddenSheet();
    }
  }

  void _showHiddenSheet() {
    final isAr = globalThemeProvider.language == 'ar';
    final isDark = globalThemeProvider.isDarkMode;
    
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            _SheetTile(
              icon: Icons.admin_panel_settings_rounded,
              label: isAr ? 'تسجيل دخول الإدمن' : 'Admin Login',
              isDark: isDark,
              onTap: () { Navigator.pop(context); widget.onLoginAdmin(); },
            ),
            const SizedBox(height: 12),
            _SheetTile(
              icon: Icons.science_outlined,
              label: isAr ? 'وضع الاختبار' : 'Dev Test Mode',
              isDark: isDark,
              onTap: () { Navigator.pop(context); _showTestDialog(); },
            ),
          ],
        ),
      ),
    );
  }

  void _showTestDialog() {
    final isDark = globalThemeProvider.isDarkMode;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card(isDark),
        surfaceTintColor: Colors.transparent,
        title: Text('Dev Test Mode',
            style: TextStyle(color: AppTheme.text(isDark), fontWeight: FontWeight.bold)),
        content: Text('Skip login and go directly to a dashboard.',
            style: TextStyle(color: AppTheme.sub(isDark))),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.medical_services_rounded, color: _kCyan, size: 20),
            label: const Text('Doctor', style: TextStyle(color: _kCyan, fontWeight: FontWeight.bold)),
            onPressed: () { Navigator.pop(ctx); widget.onTestMode('doctor'); },
          ),
          TextButton.icon(
            icon: const Icon(Icons.accessibility_new_rounded, color: _kCyan, size: 20),
            label: const Text('Patient', style: TextStyle(color: _kCyan, fontWeight: FontWeight.bold)),
            onPressed: () { Navigator.pop(ctx); widget.onTestMode('patient'); },
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.sizeOf(context);
    final isAr   = globalThemeProvider.language == 'ar';
    final isDark = globalThemeProvider.isDarkMode;
    final bg     = AppTheme.bg(isDark);
    final text   = AppTheme.text(isDark);
    final sub    = AppTheme.sub(isDark);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Animated radial-pulse background
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => CustomPaint(
              size: size,
              painter: _PulsePainter(_pulseCtrl.value, isDark),
            ),
          ),

          // Content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideIn,
                child: Column(
                  children: [
                    _TopBar(isAr: isAr, isDark: isDark),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            SizedBox(height: size.height * 0.04),

                            // Logo mark
                            _LogoMark(isDark: isDark),

                            const SizedBox(height: 24),

                            // App name
                            Text(
                              'Seneb',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                color: _kCyan,
                                letterSpacing: 4,
                                shadows: [
                                  Shadow(
                                    color: _kCyan.withValues(alpha: isDark ? 0.4 : 0.2),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              isAr
                                  ? 'طريقك للشفاء في يديك'
                                  : 'Your path to recovery, in your hands.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: sub,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                                height: 1.5,
                              ),
                            ),

                            SizedBox(height: size.height * 0.06),

                            // Role cards
                            _RoleCard(
                              icon: Icons.accessibility_new_rounded,
                              title: isAr ? 'أنا مريض' : "I'm a Patient",
                              subtitle: isAr
                                  ? 'تابع علاجك وتمارينك اليومية'
                                  : 'Track your rehab & daily exercises',
                              isDark: isDark,
                              onTap: widget.onLoginPatient,
                            ),

                            const SizedBox(height: 16),

                            _RoleCard(
                              icon: Icons.medical_services_rounded,
                              title: isAr ? 'أنا طبيب' : "I'm a Doctor",
                              subtitle: isAr
                                  ? 'أدر مرضاك وجلساتهم العلاجية'
                                  : 'Manage your patients & sessions',
                              isDark: isDark,
                              onTap: widget.onLoginDoctor,
                            ),

                            const SizedBox(height: 20),

                            // Action buttons
                            _ActionButton(
                              icon: Icons.person_add_alt_1_rounded,
                              label: isAr ? 'إنشاء حساب جديد' : 'Create Account',
                              isDark: isDark,
                              isPrimary: false,
                              onTap: widget.onCreateAccount,
                            ),

                            const SizedBox(height: 12),

                            _ActionButton(
                              icon: Icons.admin_panel_settings_rounded,
                              label: isAr ? 'دخول الإدارة' : 'Admin Login',
                              isDark: isDark,
                              isPrimary: false,
                              onTap: widget.onLoginAdmin,
                            ),

                            SizedBox(height: size.height * 0.04),
                          ],
                        ),
                      ),
                    ),

                    // Version string
                    GestureDetector(
                      onTap: _onVersionTap,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'v1.0.0',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: text.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated radial-pulse background ──────────────────────────────────────────

class _PulsePainter extends CustomPainter {
  final double progress;
  final bool isDark;
  const _PulsePainter(this.progress, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    final bg1 = AppTheme.bg(isDark);
    final bg2 = isDark ? const Color(0xFF0D2F3F) : const Color(0xFFE0F2F1);
    
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bg1, bg2],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final centre = Offset(size.width / 2, size.height * 0.35);
    for (int i = 0; i < 3; i++) {
      final phase   = (progress + i / 3) % 1.0;
      final radius  = size.width * 0.12 + size.width * 0.7 * phase;
      // Increased opacity for Light Mode (from 0.08 to 0.15) for better visibility
      final opacity = isDark ? (1.0 - phase) * 0.12 : (1.0 - phase) * 0.15;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = _kCyan.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isDark ? 1.5 : 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.progress != progress || old.isDark != isDark;
}

// ── Components ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isAr;
  final bool isDark;
  const _TopBar({required this.isAr, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pillBg = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
    final iconColor = isDark ? Colors.white70 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          _LangPill(label: 'EN', active: !isAr, isDark: isDark,
              onTap: () => globalThemeProvider.setLanguage('en')),
          const SizedBox(width: 10),
          _LangPill(label: 'AR', active: isAr, isDark: isDark,
              onTap: () => globalThemeProvider.setLanguage('ar')),
          const Spacer(),
          Material(
            color: pillBg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: globalThemeProvider.toggleTheme,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: iconColor,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;
  const _LangPill({required this.label, required this.active, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inactiveBg = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04);
    final inactiveText = isDark ? Colors.white38 : Colors.black38;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kCyan : inactiveBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: active ? [
            BoxShadow(color: _kCyan.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))
          ] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : inactiveText,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  final bool isDark;
  const _LogoMark({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.card(isDark),
        border: Border.all(color: _kCyan.withValues(alpha: 0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: _kCyan.withValues(alpha: isDark ? 0.3 : 0.15),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.healing_rounded, size: 48, color: _kCyan),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDeco(isDark).copyWith(
        boxShadow: isDark ? [] : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: _kCyan.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: _kCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: _kCyan, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            color: AppTheme.text(isDark),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 6),
                      Text(subtitle,
                          style: TextStyle(
                            color: AppTheme.sub(isDark),
                            fontSize: 13,
                            height: 1.4,
                          )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: _kCyan.withValues(alpha: 0.5), size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isPrimary ? _kCyan : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03));
    final textColor = isPrimary ? Colors.white : AppTheme.text(isDark).withValues(alpha: 0.8);
    final borderColor = isPrimary ? Colors.transparent : (isDark ? Colors.white12 : Colors.black12);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isPrimary ? Colors.white : _kCyan.withValues(alpha: 0.7), size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: _kCyan, size: 24),
              const SizedBox(width: 16),
              Text(label,
                  style: TextStyle(
                    color: AppTheme.text(isDark),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
