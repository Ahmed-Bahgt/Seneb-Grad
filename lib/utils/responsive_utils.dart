import 'package:flutter/material.dart';

/// Responsive design utilities for adaptive layouts across different screen sizes
class ResponsiveUtils {
  /// Get screen width
  static double width(BuildContext context) => MediaQuery.of(context).size.width;

  /// Get screen height
  static double height(BuildContext context) => MediaQuery.of(context).size.height;

  /// Check if device is mobile (width < 600)
  static bool isMobile(BuildContext context) => width(context) < 600;

  /// Check if device is tablet (600 <= width < 900)
  static bool isTablet(BuildContext context) => width(context) >= 600 && width(context) < 900;

  /// Check if device is desktop (width >= 900)
  static bool isDesktop(BuildContext context) => width(context) >= 900;

  /// Get responsive font size based on screen width
  static double fontSize(BuildContext context, double baseSize) {
    final w = width(context);
    if (w < 360) return baseSize * 0.85; // Small phones
    if (w < 600) return baseSize; // Normal phones
    if (w < 900) return baseSize * 1.1; // Tablets
    return baseSize * 1.2; // Large screens
  }

  /// Get responsive padding based on screen width
  static double padding(BuildContext context, double basePadding) {
    final w = width(context);
    if (w < 360) return basePadding * 0.75;
    if (w < 600) return basePadding;
    if (w < 900) return basePadding * 1.25;
    return basePadding * 1.5;
  }

  /// Get responsive spacing
  static double spacing(BuildContext context, double baseSpacing) {
    final w = width(context);
    if (w < 360) return baseSpacing * 0.75;
    if (w < 600) return baseSpacing;
    return baseSpacing * 1.2;
  }

  /// Get responsive icon size
  static double iconSize(BuildContext context, double baseSize) {
    final w = width(context);
    if (w < 360) return baseSize * 0.85;
    if (w < 600) return baseSize;
    if (w < 900) return baseSize * 1.15;
    return baseSize * 1.3;
  }

  /// Get responsive button height
  static double buttonHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 44.0;
    if (w < 600) return 50.0;
    return 56.0;
  }

  /// Get max content width for centering on large screens
  static double maxContentWidth(BuildContext context) {
    final w = width(context);
    if (w < 600) return w;
    if (w < 900) return 600;
    return 800;
  }

  /// Get responsive horizontal padding that increases on larger screens
  static EdgeInsets horizontalPadding(BuildContext context) {
    final w = width(context);
    if (w < 360) return const EdgeInsets.symmetric(horizontal: 16);
    if (w < 600) return const EdgeInsets.symmetric(horizontal: 24);
    if (w < 900) return const EdgeInsets.symmetric(horizontal: 48);
    return EdgeInsets.symmetric(horizontal: (w - 800) / 2);
  }

  /// Get responsive vertical spacing
  static double verticalSpacing(BuildContext context, double baseSpacing) {
    final h = height(context);
    if (h < 700) return baseSpacing * 0.75; // Small screens
    if (h < 900) return baseSpacing; // Normal screens
    return baseSpacing * 1.2; // Tall screens
  }
}
