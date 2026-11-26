import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../themes/app_theme.dart';

class DataTableRow extends StatelessWidget {
  final List<String> columns;
  final List<Widget> cells;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isHeader;
  final bool showBorder;

  const DataTableRow({
    super.key,
    required this.columns,
    required this.cells,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.isHeader = false,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border: showBorder
            ? Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder.withOpacity(0.5)
                      : AppColors.lightBorder.withOpacity(0.5),
                ),
              )
            : null,
        color: isHeader
            ? (isDark
                ? AppColors.darkCard.withOpacity(0.3)
                : AppColors.lightCard.withOpacity(0.5))
            : Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                ...List.generate(
                  cells.length,
                  (index) => Expanded(
                    child: isHeader
                        ? Text(
                            columns[index],
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                          )
                        : cells[index],
                  ),
                ),
                if (!isHeader && (onEdit != null || onDelete != null)) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (onEdit != null)
                          GestureDetector(
                            onTap: onEdit,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.secondary.withOpacity(0.1),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.edit,
                                size: 16,
                                color: AppColors.secondary,
                              ),
                            )
                                .animate()
                                .fadeIn(
                                    duration:
                                        const Duration(milliseconds: 300))
                                .scale(duration: const Duration(milliseconds: 300)),
                          ),
                        if (onDelete != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: onDelete,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.error.withOpacity(0.1),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: AppColors.error,
                              ),
                            )
                                .animate()
                                .fadeIn(
                                    duration:
                                        const Duration(milliseconds: 300))
                                .scale(duration: const Duration(milliseconds: 300)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
