import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../localization/app_localizations.dart';
import '../themes/app_theme.dart';

class CustomDropdown<T> extends StatefulWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final IconData? prefixIcon;
  final String? Function(T?)? validator;
  final bool enabled;

  const CustomDropdown({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.hint,
    this.prefixIcon,
    this.validator,
    this.enabled = true,
  });

  @override
  State<CustomDropdown<T>> createState() => _CustomDropdownState<T>();
}

class _CustomDropdownState<T> extends State<CustomDropdown<T>>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isOpen = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.enabled) return;

    if (_isOpen) {
      _animationController.reverse();
    } else {
      _animationController.forward();
    }
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedItem = widget.items
        .firstWhere(
          (item) => item.value == widget.value,
          orElse: () => DropdownMenuItem<T>(value: null, child: Text(widget.hint ?? AppLocalizations.of(context).t('select'))),
        )
        .child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _toggle,
          child: Focus(
            focusNode: _focusNode,
            onKey: (node, event) {
              _toggle();
              return KeyEventResult.handled;
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isOpen || _focusNode.hasFocus
                      ? AppColors.primary
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  width: _isOpen || _focusNode.hasFocus ? 2 : 1,
                ),
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                boxShadow: _isOpen || _focusNode.hasFocus
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (widget.prefixIcon != null) ...[
                          Icon(
                            widget.prefixIcon,
                            color: _isOpen || _focusNode.hasFocus
                                ? AppColors.primary
                                : null,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: DefaultTextStyle(
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium!
                                .copyWith(
                                  color: widget.value == null
                                      ? AppColors.lightSubtext
                                      : null,
                                ),
                            child: selectedItem,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ScaleTransition(
                    scale: Tween<double>(begin: 1, end: 1).animate(_animationController),
                    child: RotationTransition(
                      turns: Tween<double>(begin: 0, end: 0.5)
                          .animate(_animationController),
                      child: Icon(
                        Icons.expand_more,
                        color: _isOpen || _focusNode.hasFocus
                            ? AppColors.primary
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isOpen)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary,
                width: 1,
              ),
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: widget.items.map<Widget>((item) {
                  final isSelected = item.value == widget.value;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        widget.onChanged?.call(item.value);
                        _toggle();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.1)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            if (isSelected)
                              const SizedBox(width: 12),
                            Expanded(
                              child: DefaultTextStyle(
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(
                                      color: isSelected
                                          ? AppColors.primary
                                          : null,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                child: item.child,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          )
              .animate()
              .fadeIn(duration: const Duration(milliseconds: 200))
              .slideY(duration: const Duration(milliseconds: 200), begin: -0.2),
      ],
    )
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 300))
        .slideY(duration: const Duration(milliseconds: 300), begin: 0.1);
  }
}
