import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_localizations.dart';
import 'locale_provider.dart';
import 'app_navigator.dart';

// ─── Login-page brand colors (mirrored here to avoid package coupling) ────────
const Color _kPrimary      = Color(0xFFF28C33);
const Color _kBackground   = Color(0xFFFAF5EE);
const Color _kTextPrimary  = Color(0xFF3C3C3C);
const Color _kTextSec      = Color(0xFF8E8E8E);
const Color _kBorder       = Color(0xFFE8D9C4);
const Color _kMenuBg       = Color(0xFFFAF5EE);
const Color _kMenuSelected = Color(0xFFFFF3E6);

class LanguageSwitcher extends StatefulWidget {
  const LanguageSwitcher({super.key});

  @override
  State<LanguageSwitcher> createState() => _LanguageSwitcherState();
}

class _LanguageSwitcherState extends State<LanguageSwitcher> {
  final _actionKey = GlobalKey();
  final _provider  = LocaleProvider();

  static const Map<String, String> nativeNames = {
    'en': 'English',
    'hi': 'हिंदी',
    'mr': 'मराठी',
    'gu': 'ગુજરાતી',
    'pa': 'ਪੰਜਾਬੀ',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'bn': 'বাংলা',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: _provider.locale,
      builder: (context, locale, _) {
        final display = nativeNames[locale.languageCode] ?? locale.languageCode;

        return Container(
          margin: const EdgeInsets.only(top: 8, right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _kBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: _actionKey,
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final navigatorContext =
                    AppNavigator.navigatorKey.currentContext ?? context;

                final RenderBox renderBox =
                    _actionKey.currentContext!.findRenderObject() as RenderBox;
                final Offset offset = renderBox.localToGlobal(Offset.zero);
                final Size size    = renderBox.size;
                final screenSize   = MediaQuery.of(navigatorContext).size;

                final availableBelow =
                    screenSize.height - (offset.dy + size.height) - 8;
                final availableAbove = offset.dy - 8;
                const double maxMenuHeight = 260;
                final bool preferBelow =
                    availableBelow >= 200 || availableBelow >= availableAbove;
                final double menuHeight = preferBelow
                    ? availableBelow.clamp(120.0, maxMenuHeight)
                    : availableAbove.clamp(120.0, maxMenuHeight);

                final bool isTablet = screenSize.width >= 800;
                const double horizontalMargin = 8.0;
                double menuWidth;
                double leftPos;
                if (isTablet) {
                  menuWidth = 180.0;
                  leftPos   = offset.dx;
                  if (leftPos + menuWidth > screenSize.width - horizontalMargin) {
                    leftPos = screenSize.width - menuWidth - horizontalMargin;
                  }
                  if (leftPos < horizontalMargin) leftPos = horizontalMargin;
                } else {
                  menuWidth = 140.0;
                  leftPos = offset.dx + size.width - menuWidth; // Align right edge
                  if (leftPos < horizontalMargin) {
                    leftPos = horizontalMargin;
                  }
                  if (leftPos + menuWidth > screenSize.width - horizontalMargin) {
                    leftPos = screenSize.width - menuWidth - horizontalMargin;
                  }
                }

                const double verticalGap = 6.0;
                final topPos = preferBelow
                    ? (offset.dy + size.height + verticalGap)
                    : (offset.dy - menuHeight - verticalGap);

                final selected = await showGeneralDialog<String>(
                  context: navigatorContext,
                  barrierDismissible: true,
                  barrierLabel: 'dismiss',
                  barrierColor: Colors.transparent,
                  transitionDuration: const Duration(milliseconds: 150),
                  pageBuilder: (ctx, a1, a2) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Stack(
                        children: [
                          Positioned(
                            left:  leftPos,
                            top:   topPos,
                            width: menuWidth,
                            child: Material(
                              color: _kMenuBg,
                              elevation: 10,
                              shadowColor: _kPrimary.withOpacity(0.15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: _kBorder, width: 1.2),
                              ),
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxHeight: menuHeight),
                                child: SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // ── Language list ────────────────────
                                      Flexible(
                                        child: ListView.separated(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          itemCount: nativeNames.keys.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(
                                                  color: Color(0xFFF0E6D8),
                                                  height: 1),
                                          itemBuilder: (ctx2, idx) {
                                            final code = nativeNames.keys
                                                .elementAt(idx);
                                            final name = nativeNames[code]!;
                                            final selectedNow =
                                                code == locale.languageCode;
                                            return InkWell(
                                              onTap: () => Navigator.of(ctx2).pop(code),
                                              child: Container(
                                                color: selectedNow ? _kMenuSelected : Colors.transparent,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      name,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        color: selectedNow ? _kPrimary : _kTextPrimary,
                                                        fontWeight: selectedNow ? FontWeight.w600 : FontWeight.w400,
                                                      ),
                                                    ),
                                                    if (selectedNow)
                                                      const Icon(Icons.check_rounded, color: _kPrimary, size: 16),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );

                if (selected != null) await _provider.setLocale(selected);
              },
              // ── Trigger button content ──────────────────────────────────
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_rounded,
                      color: _kPrimary, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    'Select Lan',
                    style: GoogleFonts.inter(
                      color: _kTextSec,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    display,
                    style: GoogleFonts.inter(
                      color: _kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down_rounded,
                      color: _kPrimary, size: 22),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
