// login_view.dart - Touchmatik Glide (Keetronics), V1.1.0 (Agragamee, Oct-2026):
// the About line (app version, BLE protocol, minimum panel firmware) under the card.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_version.dart';
import '../localization/app_localizations.dart';
import 'login_controller.dart';
import '../ui/pages/customer_info_page.dart';

// ─── Brand Colors ────────────────────────────────────────────────────────────
class _LoginColors {
  static const Color primary = Color(0xFFF28C33); // Action Orange
  static const Color background = Color(0xFFFAF5EE); // Comfort Cream 0xFFFAF5EE
  static const Color cardBg = Color(0xFFFAF5EE); // Soft Cream card
  static const Color inputGroupBg = Color(0xFFF0E6D8); // Input group container
  static const Color textPrimary = Color(0xFF3C3C3C); // Deep Charcoal
  static const Color textSecondary = Color(0xFF8E8E8E); // Medium Gray
  static const Color socialBorder = Color(0xFFE0D8CE); // Subtle border
}

// ─── Widget ──────────────────────────────────────────────────────────────────
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView>
    with SingleTickerProviderStateMixin {
  // ── Existing state (unchanged) ─────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final LoginController _controller = LoginController();
  bool _obscure = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  void _onController() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ── Existing submit logic (unchanged) ─────────────────────────────────────
  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    _controller.setEmail(_emailCtrl.text.trim());
    _controller.setPassword(_pwCtrl.text);

    final ok = await _controller.login();
    if (ok) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CustomerInfoPage()),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: _LoginColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isWide ? 48 : 20,
              56, // breathing room below the global top-bar logo
              isWide ? 48 : 20,
              24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 480 : 420),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCard(isWide),
                    const SizedBox(height: 14),
                    _buildAboutLine(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Card Container ────────────────────────────────────────────────────────
  Widget _buildCard(bool isWide) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _LoginColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0E0CC), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF28C33).withOpacity(0.08),
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
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 40 : 28,
          vertical: 36,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTitleSection(),
              const SizedBox(height: 28),
              _buildInputGroup(),
              const SizedBox(height: 20),

              // Error message
              if (_controller.error != null) ...[
                _buildErrorBanner(_controller.error!),
                const SizedBox(height: 16),
              ],

              _buildLoginButton(),
              const SizedBox(height: 24),
              _buildSocialButtons(),
              const SizedBox(height: 22),
              _buildSignUpLink(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Title Section ─────────────────────────────────────────────────────────
  Widget _buildTitleSection() {
    return Column(
      children: [
        Text(
          AppLocalizations.of(context).t('login_title'),
          style: GoogleFonts.inter(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: _LoginColors.textPrimary,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          AppLocalizations.of(context).t('login_subtitle'),
          style: GoogleFonts.inter(
            fontSize: 14,
            color: _LoginColors.textSecondary,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Input Group (cream container holding both fields) ─────────────────────
  Widget _buildInputGroup() {
    return Container(
      decoration: BoxDecoration(
        color: _LoginColors.inputGroupBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _buildInputField(
            controller: _emailCtrl,
            label: AppLocalizations.of(context).t('email'),
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _controller.validateEmail,
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _pwCtrl,
            label: AppLocalizations.of(context).t('password'),
            icon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            onVisibilityToggle: () => setState(() => _obscure = !_obscure),
            validator: _controller.validatePassword,
          ),
        ],
      ),
    );
  }

  // ── Single Input Field ────────────────────────────────────────────────────
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    VoidCallback? onVisibilityToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.inter(
        fontSize: 15,
        color: _LoginColors.textPrimary,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: GoogleFonts.inter(
          fontSize: 15,
          color: _LoginColors.textSecondary,
        ),
        filled: true,
        fillColor: _LoginColors.cardBg,
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Icon(icon, color: _LoginColors.textPrimary, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 52),
        suffixIcon: onVisibilityToggle != null
            ? IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _LoginColors.textSecondary,
                  size: 20,
                ),
                onPressed: onVisibilityToggle,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _LoginColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
        ),
      ),
    );
  }

  // ── Error Banner ──────────────────────────────────────────────────────────
  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        message,
        style: GoogleFonts.inter(fontSize: 12.5, color: Colors.red.shade700),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Login Button ──────────────────────────────────────────────────────────
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: _controller.loading ? null : _submit,
          borderRadius: BorderRadius.circular(30),
          child: Ink(
            decoration: BoxDecoration(
              color: _LoginColors.primary,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: _LoginColors.primary.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: _controller.loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context).t('login_button'),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Social Buttons ────────────────────────────────────────────────────────
  Widget _buildSocialButtons() {
    return Row(
      children: [
        _buildSocialButton(
          icon: Icons.facebook_rounded,
          label: AppLocalizations.of(context).t('facebook'),
          iconColor: const Color(0xFF1877F2),
        ),
        const SizedBox(width: 12),
        _buildSocialButton(
          icon: Icons.g_mobiledata_rounded,
          label: AppLocalizations.of(context).t('google'),
          iconColor: const Color(0xFFEA4335),
        ),
        const SizedBox(width: 12),
        _buildSocialButton(
          icon: Icons.apple_rounded,
          label: AppLocalizations.of(context).t('apple'),
          iconColor: _LoginColors.textPrimary,
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color iconColor,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: _LoginColors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _LoginColors.socialBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _LoginColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── About line (V1.1.0): which app, which protocol, which panel firmware ──
  Widget _buildAboutLine() {
    return Semantics(
      label: AppLocalizations.of(context).t('about'),
      child: Text(
        kAppAbout,
        key: const ValueKey('about_line'),
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 11.5, color: _LoginColors.textSecondary, height: 1.4),
      ),
    );
  }

  // ── Sign Up Link ──────────────────────────────────────────────────────────
  Widget _buildSignUpLink() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 13.5,
          color: _LoginColors.textPrimary,
        ),
        children: [
          TextSpan(
            text: '${AppLocalizations.of(context).t('no_account_question')} ',
          ),
          TextSpan(
            text: AppLocalizations.of(context).t('sign_up'),
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: _LoginColors.primary,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: _LoginColors.primary,
            ),
            recognizer: null, // Placeholder for future navigation
          ),
        ],
      ),
    );
  }
}

// ─── HomeScreen (unchanged) ───────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).t('home'))),
      body: Center(
        child: Text(
          AppLocalizations.of(context).t('welcome_logged_in'),
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
