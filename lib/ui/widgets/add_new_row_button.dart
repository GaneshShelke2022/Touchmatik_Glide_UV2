import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../localization/app_localizations.dart';
import '../../themes/app_theme.dart';

class AddNewRowButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;

  const AddNewRowButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.add_circle,
    this.iconSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        color: AppBrandColors.accent,
        size: iconSize,
      ),
      label: Text(
        AppLocalizations.of(context).t('add_new_row'),
        style: GoogleFonts.inter(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppBrandColors.accent,
        padding: padding,
      ),
    );
  }
}
