import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../themes/app_theme.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isDisabled;
  final double? width;
  final double height;
  final IconData? icon;
  final bool isSecondary;
  final bool isOutlined;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.height = 48,
    this.icon,
    this.isSecondary = false,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isOutlined) {
      return SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: OutlinedButton(
          onPressed: (isLoading || isDisabled) ? null : onPressed,
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: isDisabled ? AppColors.lightBorder : AppColors.primary,
              width: 2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.zero,
          ),
          child: _buildContent(context, isDark),
        ),
      )
          .animate(onPlay: (controller) => controller.repeat())
          .shimmer(
            duration: const Duration(milliseconds: 2000),
            color: Colors.white.withOpacity(0.1),
          );
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: isDisabled
              ? LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.3),
                    AppColors.primary.withOpacity(0.3),
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isSecondary
                      ? [
                          AppColors.secondary,
                          AppColors.secondary.withOpacity(0.8),
                        ]
                      : [
                          AppColors.primary,
                          AppColors.primary.withOpacity(0.85),
                        ],
                ),
          boxShadow: isDisabled
              ? []
              : [
                  BoxShadow(
                    color: (isSecondary ? AppColors.secondary : AppColors.primary)
                        .withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: (isLoading || isDisabled) ? null : onPressed,
            borderRadius: BorderRadius.circular(12),
            child: _buildContent(context, isDark),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 300))
        .scale(duration: const Duration(milliseconds: 300));
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    if (isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? Colors.white : Colors.white,
            ),
          ),
        ),
      );
    }

    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
