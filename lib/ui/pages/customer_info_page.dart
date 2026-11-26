// customer_info_page.dart - Touchmatik Glide V1.1.0 (Agragamee, Oct-2026): customer details and "Open TXT".
// V1.1.0: the TXT parser moved to services/txt_reader.dart (loadTxt: one panel number, keys at their
// SW-NN places, commas kept inside values), with one dialog listing what moved; the junk config.hex
// ("00000000") is no longer written on Next (M5); files live in appDocumentsDir() (M10).
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../../localization/app_localizations.dart';
import 'panel_switch_assign_page.dart';
import 'configuration_page.dart';
import '../../data/app_data.dart';
import '../../services/txt_reader.dart';
import '../../themes/app_theme.dart';
import '../../utils/file_helper.dart';

class CustomerInfoPage extends StatefulWidget {
  const CustomerInfoPage({super.key});

  @override
  State<CustomerInfoPage> createState() => _CustomerInfoPageState();
}

class _CustomerInfoPageState extends State<CustomerInfoPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String? selectedFile;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;



  @override
  void initState() {
    super.initState();
    final data = AppDataManager();
    if (data.customerName != null) _nameCtrl.text = data.customerName!;
    if (data.customerAddress != null) _addressCtrl.text = data.customerAddress!;
    if (data.selectedFile != null) selectedFile = data.selectedFile;

    // Setup fade-in animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _openFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        String fileName = result.files.single.name;
        File file = File(filePath);
        String content = await file.readAsString();
        // the picker hands out a cached copy: the TXT is written back to the documents folder
        final String savePath = p.join(await appDocumentsDir(), fileName);
        if (!mounted) return;

        _parseAndLoadData(content, savePath);
      }
    } catch (e) {
      debugPrint("Error opening file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).t('error_opening_file', params: {'error': e.toString()}))),
        );
      }
    }
  }

  // V1.1.0: the parser is loadTxt (services/txt_reader.dart): one panel number for keys, inputs and
  // the network page, keys at their SW-NN places, commas kept inside values (B2b, M1, B8)
  void _parseAndLoadData(String content, String filePath) {
    final data = AppDataManager();
    final result = loadTxt(content);

    setState(() {
      _nameCtrl.text = data.customerName ?? '';
      _addressCtrl.text = data.customerAddress ?? '';
      selectedFile = filePath;
      data.selectedFile = filePath;
      data.selectedFileFromCustomerInfo = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context).t('file_loaded_success'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          width: MediaQuery.of(context).size.width > 600 ? 400 : 280,
        ),
      );
    }
    if (mounted && result.warnings.isNotEmpty) {
      _showLoadWarnings(result.warnings);
    }
  }

  // a localised text, or the English one while the key is not in app_en.arb yet
  String _tr(String key, String english) {
    final text = AppLocalizations.of(context).t(key);
    return text == key ? english : text;
  }

  // V1.1.0 (B2b, M1): what loadTxt moved or skipped, in one dialog
  void _showLoadWarnings(List<String> warnings) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('txt_open_changes_title', 'Opened with changes')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tr('txt_open_changes_intro', 'Touchmatik Glide edits one panel per file. While opening this file:')),
              const SizedBox(height: 8),
              for (final warning in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('- $warning'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_tr('ok', 'OK')),
          ),
        ],
      ),
    );
  }

  void _next() {
    // Validation is removed as per request to make fields optional.
    // The validate call is commented out.
    // if (!_formKey.currentState!.validate()) return;

    AppDataManager().customerName = _nameCtrl.text;
    AppDataManager().customerAddress = _addressCtrl.text;
    AppDataManager().selectedFile = selectedFile;
    AppDataManager().selectedFileFromCustomerInfo = true;

    _saveFiles();

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PanelSwitchAssignPage()));
  }

  // V1.1.0 (M5): only customer_info.txt; the placeholder config.hex ("00000000") is gone
  Future<void> _saveFiles() async {
    try {
      final String path = await appDocumentsDir();
      final File txtFile = File(p.join(path, 'customer_info.txt'));
      await txtFile.writeAsString(
          "Name: ${_nameCtrl.text}\nAddress: ${_addressCtrl.text}\nFile: $selectedFile");
    } catch (e) {
      debugPrint("Error saving files: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: AppBrandColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 100, 16, 30),
          child: Center(
            child: Column(
              children: [
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 900 : 530),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildCard(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppBrandColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppBrandColors.border),
        boxShadow: const [BoxShadow(color: Color(0x1AF28C33), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: AppBrandColors.accentLight, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppBrandColors.border)),
                child: const Icon(Icons.person, size: 30, color: AppBrandColors.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).t('customer_information'), style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(AppLocalizations.of(context).t('fill_details'), style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Form
          Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, c) {
                bool wide = c.maxWidth > 600;
                return wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildNameField()),
                          const SizedBox(width: 14),
                          Expanded(child: _buildAddressField()),
                        ],
                      )
                    : Column(
                        children: [
                          _buildNameField(),
                          const SizedBox(height: 14),
                          _buildAddressField(),
                        ],
                      );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (selectedFile != null)
            Text(AppLocalizations.of(context).t('selected_file', params: {'file': selectedFile ?? ''}),
                style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          // Buttons
          Row(
            children: [
              Expanded(child: _buildOpenButton()),
              const SizedBox(width: 14),
              Expanded(child: _buildNextButton()),
            ],
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: _buildSkipLink()),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameCtrl,
      style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontSize: 14),
      cursorColor: AppBrandColors.accent,
      decoration: AppBrandColors.styledInputDecoration(label: AppLocalizations.of(context).t('customer_name'), radius: 14).copyWith(
        prefixIcon: const Icon(Icons.person_outline, color: AppBrandColors.textSecondary, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildAddressField() {
    return TextFormField(
      controller: _addressCtrl,
      maxLines: 3,
      style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontSize: 14),
      cursorColor: AppBrandColors.accent,
      decoration: AppBrandColors.styledInputDecoration(label: AppLocalizations.of(context).t('address'), radius: 14).copyWith(
        prefixIcon: const Icon(Icons.location_on_outlined, color: AppBrandColors.textSecondary, size: 20),
        alignLabelWithHint: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildOpenButton() {
    return InkWell(
      onTap: _openFile,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppBrandColors.toggleInactive,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppBrandColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, color: AppBrandColors.textPrimary, size: 20),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context).t('open_txt_file'), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppBrandColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    return InkWell(
      onTap: _next,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppBrandColors.accent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x33F28C33), blurRadius: 15, offset: Offset(0, 5))],
        ),
        child: Center(
          child: Text(AppLocalizations.of(context).t('next'), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ),
    );
  }

  // Skip link widget
  Widget _buildSkipLink() {
    return GestureDetector(
      onTap: () {
        // Mark that the user already has a HEX file so ConfigurationPage
        // will open in flash-only mode and skip generation/process steps.
        AppDataManager().alreadyHaveHexSelected = true;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ConfigurationPage(),
        ));
      },
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.textPrimary),
          children: [
            TextSpan(text: '${AppLocalizations.of(context).t('already_have_hex')} '),
            TextSpan(
              text: AppLocalizations.of(context).t('skip_this_step'),
              style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
            ),
          ],
        ),
      ),
    );
  }
}
