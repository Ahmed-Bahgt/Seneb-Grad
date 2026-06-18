import 'package:flutter/material.dart';
import '../utils/theme_provider.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const CustomAppBar({super.key, required this.title, this.onBack, this.actions});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.canPop(context);
    final showBack = onBack != null || canPop;

    return AppBar(
      backgroundColor: AppTheme.bg(isDark),
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  size: 20, color: AppTheme.cyan),
              onPressed: onBack ?? () => Navigator.pop(context),
            )
          : null,
      automaticallyImplyLeading: showBack,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.text(isDark),
          letterSpacing: 0.2,
        ),
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.border(isDark)),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);
}
