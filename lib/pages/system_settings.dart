import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_color.dart';
import '../config/app_config.dart';
import '../config/responsive_text.dart';
import '../config/locale_manager.dart';
import '../services/database_service.dart';
import '../l10n/app_localizations.dart';
import '../models/setting.dart';
import '../services/diagnostics/diagnostic_export_service.dart';
import '../services/diagnostics/app_logger.dart';
import '../services/external_link_service.dart';

const String _languageKey = 'app_language';
const String _languageDesc = 'Application language setting';

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  final DatabaseService _dbService = DatabaseService();
  final LocaleManager _localeManager = LocaleManager();
  String _selectedLanguage = 'en';
  bool _isLoading = true;
  bool _exportingLogs = false;
  final GlobalKey _exportLogsButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadLanguageSetting();
  }

  Future<void> _loadLanguageSetting() async {
    final languageSetting = await _dbService.getSettingByKey(_languageKey);
    if (mounted) {
      setState(() {
        if (languageSetting != null) {
          _selectedLanguage = languageSetting.value;
        } else {
          // 未保存偏好：下拉框展示当前系统语言（与首次启动时应用界面一致）
          _selectedLanguage = LocaleManager.systemLanguageCode;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final existingSetting = await _dbService.getSettingByKey(_languageKey);

    if (existingSetting != null) {
      await _dbService.updateSettingByKey(_languageKey, _selectedLanguage);
    } else {
      await _dbService.insertSetting(
        Setting(
          key: _languageKey,
          desc: _languageDesc,
          value: _selectedLanguage,
        ),
      );
    }

    // 保存后立即生效
    _localeManager.updateLocale(_selectedLanguage);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.settingsSaved),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _exportDiagnosticLogs() async {
    setState(() => _exportingLogs = true);
    try {
      Rect? origin;
      final ctx = _exportLogsButtonKey.currentContext;
      final renderObject = ctx?.findRenderObject();
      if (renderObject is RenderBox) {
        final topLeft = renderObject.localToGlobal(Offset.zero);
        origin = topLeft & renderObject.size;
      }
      await DiagnosticExportService.shareDiagnosticLogs(
        sharePositionOrigin: origin,
      );
    } catch (e, st) {
      debugPrint('❌ Export diagnostic logs failed: $e');
      debugPrint(st.toString());
      try {
        // Best-effort: may be unavailable when diagnostics are disabled or not initialized.
        AppLogger.e('diag', 'exportDiagnosticLogs failed', {
          'error': e.toString(),
          'stack': st.toString().split('\n').take(12).join('\n'),
        });
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.exportLogsFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exportingLogs = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColor.primaryPurple,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.grey[300],
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColor.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: ResponsiveText.symmetric(
                    context,
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        _buildLanguageSection(),
                        SizedBox(height: ResponsiveText.getSize(context, 24)),
                        _buildIcpFilingSection(),
                        if (AppConfig.diagnosticsEnabled) ...[
                          SizedBox(height: ResponsiveText.getSize(context, 24)),
                          _buildDiagnosticsSection(),
                        ],
                      ],
                      SizedBox(height: ResponsiveText.getSize(context, 24)),
                      _buildSaveButton(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: ResponsiveText.getSize(context, 8),
        right: ResponsiveText.getSize(context, 20),
        top: statusBarHeight + ResponsiveText.getSize(context, 8),
        bottom: ResponsiveText.getSize(context, 16),
      ),
      decoration: const BoxDecoration(color: AppColor.primaryPurple),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColor.white),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          Text(
            AppLocalizations.of(context)!.systemSettings,
            style: ResponsiveText.title(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSection() {
    return Container(
      padding: ResponsiveText.symmetric(context, vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.language,
            style: ResponsiveText.title(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.textPrimary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 36)),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: DropdownButtonFormField<String>(
              value: _selectedLanguage,
              decoration: InputDecoration(
                contentPadding: ResponsiveText.symmetric(
                  context,
                  horizontal: 12,
                  vertical: 8,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              items: [
                DropdownMenuItem(
                  value: 'en',
                  child: Text(
                    AppLocalizations.of(context)!.english,
                    style: ResponsiveText.smallTitle(
                      context,
                      color: AppColor.textPrimary,
                    ),
                  ),
                ),
                DropdownMenuItem(
                  value: 'zh',
                  child: Text(
                    AppLocalizations.of(context)!.chinese,
                    style: ResponsiveText.body(
                      context,
                      color: AppColor.textPrimary,
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedLanguage = value;
                  });
                }
              },
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: AppColor.textSecondary,
              ),
              dropdownColor: AppColor.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcpFilingSection() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: ResponsiveText.symmetric(context, vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.icpFilingSection,
            style: ResponsiveText.title(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.textPrimary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 12)),
          Text(
            l10n.icpFilingHint,
            style: ResponsiveText.bodySmall(
              context,
              color: AppColor.textSecondary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 20)),
          InkWell(
            onTap: _openIcpFilingWebsite,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: ResponsiveText.symmetric(
                context,
                horizontal: 4,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.icpFilingLabel,
                          style: ResponsiveText.caption(
                            context,
                            color: AppColor.textSecondary,
                          ),
                        ),
                        SizedBox(height: ResponsiveText.getSize(context, 4)),
                        Text(
                          AppConfig.icpFilingNumber,
                          style: ResponsiveText.body(
                            context,
                            color: AppColor.primaryPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new,
                    size: ResponsiveText.getSize(context, 18),
                    color: AppColor.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openIcpFilingWebsite() async {
    final launched = await ExternalLinkService.openHttpUrl(
      AppConfig.icpFilingQueryUrl,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.icpFilingOpenFailed),
        ),
      );
    }
  }

  Widget _buildDiagnosticsSection() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: ResponsiveText.symmetric(context, vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.diagnosticsSection,
            style: ResponsiveText.title(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.textPrimary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 12)),
          Text(
            l10n.diagnosticLogsHint,
            style: ResponsiveText.bodySmall(
              context,
              color: AppColor.textSecondary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 20)),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: _exportLogsButtonKey,
              onPressed: _exportingLogs ? null : _exportDiagnosticLogs,
              icon: _exportingLogs
                  ? SizedBox(
                      width: ResponsiveText.getSize(context, 18),
                      height: ResponsiveText.getSize(context, 18),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
              label: Text(l10n.exportDiagnosticLogs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          await _saveSettings();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.primaryPurple,
          foregroundColor: AppColor.white,
          padding: ResponsiveText.padding(context, all: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(
          AppLocalizations.of(context)!.saveSettings,
          style: ResponsiveText.title(context, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
