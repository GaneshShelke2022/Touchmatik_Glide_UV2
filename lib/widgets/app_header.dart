import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../themes/app_theme.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final VoidCallback? onBackPressed;
  final bool showBackButton;
  final bool useGradient;
  final Color? backgroundColor;
  final PreferredSizeWidget? bottom;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.onBackPressed,
    this.showBackButton = true,
    this.useGradient = false,
    this.backgroundColor,
    this.bottom,
  });

  @override
  Size get preferredSize {
    final height = 56.0 + (bottom?.preferredSize.height ?? 0);
    return Size.fromHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ??
            (isDark ? AppColors.darkSurface : AppColors.lightSurface),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
        gradient: useGradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        AppColors.darkSurface,
                        AppColors.darkSurface.withOpacity(0.9),
                      ]
                    : [
                        AppColors.lightSurface,
                        AppColors.lightSurface.withOpacity(0.8),
                      ],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AppColors.primary)
                .withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showBackButton) ...[
                      GestureDetector(
                        onTap: onBackPressed ?? () => Navigator.of(context).pop(),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? AppColors.darkCard
                                : AppColors.lightCard,
                            border: Border.all(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                              width: 1,
                            ),
                          ),
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.arrow_back,
                            size: 20,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.lightText,
                          ),
                        )
                            .animate()
                            .fadeIn(duration: const Duration(milliseconds: 300))
                            .scale(duration: const Duration(milliseconds: 300)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style:
                                Theme.of(context).textTheme.headlineSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (actions != null) ...[
                      const SizedBox(width: 12),
                      Row(
                        children: actions!
                            .map((action) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: action,
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}
