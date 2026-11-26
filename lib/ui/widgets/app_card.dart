import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: AppBrandColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppBrandColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppBrandColors.accent.withOpacity(0.08),
            blurRadius: 32,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
