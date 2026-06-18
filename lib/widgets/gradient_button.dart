import 'package:flutter/material.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive_utils.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color startColor;
  final Color endColor;
  final Widget? icon;
  final Color textColor;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.startColor = const Color(0xFF00BCD4),
    this.endColor = const Color(0xFF4DD0E1),
    this.icon,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = ResponsiveUtils.spacing(context, 12);
    final verticalPadding = ResponsiveUtils.buttonHeight(context) * 0.32;
    final horizontalPadding = ResponsiveUtils.padding(context, 24);
    final fontSize = ResponsiveUtils.fontSize(context, 18);
    
    return Container(
      width: double.infinity,
      height: ResponsiveUtils.buttonHeight(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colorWithOpacity(endColor, 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          textStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Padding(
                padding: EdgeInsets.only(right: ResponsiveUtils.spacing(context, 8)),
                child: IconTheme(
                  data: IconThemeData(
                    color: textColor,
                    size: ResponsiveUtils.iconSize(context, 20),
                  ), 
                  child: icon!,
                ),
              ),
            Flexible(
              child: Text(
                text, 
                style: TextStyle(color: textColor, fontSize: fontSize),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
