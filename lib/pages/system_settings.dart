import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../config/locale_manager.dart';
import '../services/database_service.dart';
import '../l10n/app_localizations.dart';
import '../models/setting.dart';

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
  String _selectedLanguage = 'en'; // 默认英文
  bool _isLoading = true;

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
          // 没找到设置就用默认值
          _selectedLanguage = 'en';
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
                      else
                        _buildLanguageSection(),
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
