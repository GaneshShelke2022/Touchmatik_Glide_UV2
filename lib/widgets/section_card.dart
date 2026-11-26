import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_animate/flutter_animate.dart';
import '../themes/app_theme.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool useGlassmorphism;
  final bool useGradient;
  final Color? backgroundColor;
  final List<BoxShadow>? shadows;
  final BorderRadius? borderRadius;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.useGlassmorphism = false,
    this.useGradient = false,
    this.backgroundColor,
    this.shadows,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final br = borderRadius ?? BorderRadius.circular(16);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: br,
          boxShadow: shadows ??
              [
                BoxShadow(
                  color: (isDark ? Colors.black : Colors.black)
                      .withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
        ),
        child: ClipRRect(
          borderRadius: br,
          child: useGlassmorphism
              ? _buildGlassCard(context, isDark)
              : _buildRegularCard(context, isDark),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 400))
        .slideY(duration: const Duration(milliseconds: 400), begin: 0.2);
  }

  Widget _buildGlassCard(BuildContext context, bool isDark) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.white.withOpacity(0.7),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    Colors.white.withOpacity(0.08),
                    Colors.white.withOpacity(0.03),
                  ]
                : [
                    Colors.white.withOpacity(0.8),
                    Colors.white.withOpacity(0.6),
                  ],
          ),
        ),
        child: _buildCardContent(context, isDark),
      ),
    );
  }

  Widget _buildRegularCard(BuildContext context, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: backgroundColor ??
            (isDark ? AppColors.darkCard : AppColors.lightCard),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
        gradient: useGradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        AppColors.darkCard,
                        AppColors.darkCard.withOpacity(0.7),
                      ]
                    : [
                        AppColors.lightCard,
                        AppColors.lightCard.withOpacity(0.5),
                      ],
              )
            : null,
      ),
      child: _buildCardContent(context, isDark),
    );
  }

  Widget _buildCardContent(BuildContext context, bool isDark) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}
