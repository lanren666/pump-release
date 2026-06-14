import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'Wearable Breast Pump'**
  String get appTitle;

  /// Warning message when devices are not synchronized
  ///
  /// In en, this message translates to:
  /// **'Devices are not synchronized. You can only stop both devices or control them separately.'**
  String get devicesNotSynchronized;

  /// Instruction to switch to individual device control
  ///
  /// In en, this message translates to:
  /// **'Switch to \"Left\" or \"Right\" to control each device individually.'**
  String get switchToLeftOrRight;

  /// Custom flow button text
  ///
  /// In en, this message translates to:
  /// **'Custom Flow'**
  String get customFlow;

  /// Instruction text for custom flow page
  ///
  /// In en, this message translates to:
  /// **'Create a custom pumping session by adding phases. Each phase can be either stimulation (fast rhythm) or expression (slower rhythm). Total duration of all phases cannot exceed 30 minutes.'**
  String get customFlowInstruction;

  /// Error when custom flow total duration exceeds limit
  ///
  /// In en, this message translates to:
  /// **'Total duration cannot exceed 30 minutes.'**
  String get customFlowTotalExceeded;

  /// Label for phase mode
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mode;

  /// Stimulation mode name
  ///
  /// In en, this message translates to:
  /// **'Stimulation'**
  String get stimulation;

  /// Expression mode name
  ///
  /// In en, this message translates to:
  /// **'Expression'**
  String get expression;

  /// Label for phase duration
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// Abbreviation for minutes
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutes;

  /// Description for stimulation mode
  ///
  /// In en, this message translates to:
  /// **'Fast rhythm to trigger milk letdown'**
  String get stimulationDescription;

  /// Description for expression mode
  ///
  /// In en, this message translates to:
  /// **'Slower rhythm to express milk efficiently'**
  String get expressionDescription;

  /// Button text to add a new phase
  ///
  /// In en, this message translates to:
  /// **'Add Phase'**
  String get addPhase;

  /// Title for flow summary section
  ///
  /// In en, this message translates to:
  /// **'Flow Summary'**
  String get flowSummary;

  /// Total duration text with parameter
  ///
  /// In en, this message translates to:
  /// **'Total: {totalMinutes} minutes'**
  String totalMinutes(int totalMinutes);

  /// Button text to save custom flow
  ///
  /// In en, this message translates to:
  /// **'Save Custom Flow'**
  String get saveCustomFlow;

  /// Description for custom flow setting in database
  ///
  /// In en, this message translates to:
  /// **'Custom pumping flow configuration'**
  String get customFlowSettingDesc;

  /// Title for device settings page
  ///
  /// In en, this message translates to:
  /// **'Device Settings'**
  String get deviceSettings;

  /// Title for system settings page
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get systemSettings;

  /// Title for device side settings section
  ///
  /// In en, this message translates to:
  /// **'Device Side Settings'**
  String get deviceSideSettings;

  /// Left side label
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get left;

  /// Right side label
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get right;

  /// Button text to switch device to right side
  ///
  /// In en, this message translates to:
  /// **'Switch to Right Side'**
  String get switchToRightSide;

  /// Button text to switch device to left side
  ///
  /// In en, this message translates to:
  /// **'Switch to Left Side'**
  String get switchToLeftSide;

  /// Hint text for device side settings
  ///
  /// In en, this message translates to:
  /// **'Swap the side assignment if you\'ve switched the physical pump position'**
  String get deviceSideSettingsHint;

  /// Battery label
  ///
  /// In en, this message translates to:
  /// **'Battery: '**
  String get battery;

  /// Message shown when settings are saved
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// Button text to save settings
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// Title for home page
  ///
  /// In en, this message translates to:
  /// **'Breast Pump Control'**
  String get breastPumpControl;

  /// Subtitle for home page
  ///
  /// In en, this message translates to:
  /// **'Connect your wearable breast pump'**
  String get connectYourWearableBreastPump;

  /// Searching status text
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searching;

  /// Button text to search for devices
  ///
  /// In en, this message translates to:
  /// **'Search for Devices'**
  String get searchForDevices;

  /// Title for available devices section
  ///
  /// In en, this message translates to:
  /// **'Available Devices'**
  String get availableDevices;

  /// Title for paired devices section
  ///
  /// In en, this message translates to:
  /// **'Paired Devices'**
  String get pairedDevices;

  /// Button text to continue to control page
  ///
  /// In en, this message translates to:
  /// **'Continue to Control'**
  String get continueToControl;

  /// Message when device is connected
  ///
  /// In en, this message translates to:
  /// **'Connected to {deviceName} ({side}).'**
  String connectedToDevice(String deviceName, String side);

  /// Message when device is removed
  ///
  /// In en, this message translates to:
  /// **'Device removed'**
  String get deviceRemoved;

  /// Message when devices are found
  ///
  /// In en, this message translates to:
  /// **'Found {count} {count, plural, =1{device} other{devices}}'**
  String foundDevices(int count);

  /// Title for pump side selection dialog
  ///
  /// In en, this message translates to:
  /// **'Select Pump Side'**
  String get selectPumpSide;

  /// Error message when connection fails
  ///
  /// In en, this message translates to:
  /// **'Failed to connect to {deviceName}'**
  String failedToConnect(String deviceName);

  /// Error message when connection error occurs
  ///
  /// In en, this message translates to:
  /// **'Error connecting to {deviceName}: {error}'**
  String errorConnecting(String deviceName, String error);

  /// Left side option label
  ///
  /// In en, this message translates to:
  /// **'Left Side'**
  String get leftSide;

  /// Right side option label
  ///
  /// In en, this message translates to:
  /// **'Right Side'**
  String get rightSide;

  /// Connecting status text
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// Button text to connect device
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Title for control page
  ///
  /// In en, this message translates to:
  /// **'Pump Control'**
  String get pumpControl;

  /// Instruction text for pump selection
  ///
  /// In en, this message translates to:
  /// **'Select which pump(s) to control'**
  String get selectWhichPumpToControl;

  /// Both pumps option
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get both;

  /// Device status section title
  ///
  /// In en, this message translates to:
  /// **'Device Status'**
  String get deviceStatus;

  /// Not available text
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get notAvailable;

  /// Device connected status
  ///
  /// In en, this message translates to:
  /// **'connected'**
  String get connected;

  /// Device disconnected status
  ///
  /// In en, this message translates to:
  /// **'disconnected'**
  String get disconnected;

  /// Device off/disconnected status label in status card
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get deviceOff;

  /// Device connected status label in status card
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get deviceConnected;

  /// Hint on disconnected device status card
  ///
  /// In en, this message translates to:
  /// **'Tap to reconnect'**
  String get tapToReconnect;

  /// Snackbar when manual reconnect fails
  ///
  /// In en, this message translates to:
  /// **'Reconnect failed. Please try again.'**
  String get reconnectFailed;

  /// Session settings section title
  ///
  /// In en, this message translates to:
  /// **'Session Settings'**
  String get sessionSettings;

  /// Default mode
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultMode;

  /// Custom mode
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// Default flow button text
  ///
  /// In en, this message translates to:
  /// **'Default Flow'**
  String get defaultFlow;

  /// Beginner mode button text
  ///
  /// In en, this message translates to:
  /// **'Beginner'**
  String get beginnerFlow;

  /// Boost milk mode button text
  ///
  /// In en, this message translates to:
  /// **'Boost Milk'**
  String get boostMilkFlow;

  /// Maximum label
  ///
  /// In en, this message translates to:
  /// **'Max:'**
  String get max;

  /// Phase label
  ///
  /// In en, this message translates to:
  /// **'Phase'**
  String get phase;

  /// Abbreviation for Stimulation
  ///
  /// In en, this message translates to:
  /// **'Stim'**
  String get stim;

  /// Abbreviation for Expression
  ///
  /// In en, this message translates to:
  /// **'Expr'**
  String get expr;

  /// Intensity settings section title
  ///
  /// In en, this message translates to:
  /// **'Intensity Settings'**
  String get intensitySettings;

  /// Suction level label
  ///
  /// In en, this message translates to:
  /// **'Suction level'**
  String get suctionLevel;

  /// Suction label (short form)
  ///
  /// In en, this message translates to:
  /// **'Suction'**
  String get suction;

  /// Hybrid pattern label
  ///
  /// In en, this message translates to:
  /// **'Hybrid Pattern'**
  String get hybridPattern;

  /// Hybrid label (short form)
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get hybrid;

  /// Hybrid pattern description
  ///
  /// In en, this message translates to:
  /// **'2 short + 1 long'**
  String get hybridPatternDescription;

  /// Hybrid pattern description (short form)
  ///
  /// In en, this message translates to:
  /// **'2s + 1L'**
  String get hybridPatternDescriptionShort;

  /// Pause button text
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Start button text
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// Stop button text
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// Switch button text
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get switchMode;

  /// Menu item to manage device connections
  ///
  /// In en, this message translates to:
  /// **'Manage Connections'**
  String get manageConnections;

  /// Menu item for database debug page
  ///
  /// In en, this message translates to:
  /// **'Database Debug'**
  String get databaseDebug;

  /// Menu item to clear all data
  ///
  /// In en, this message translates to:
  /// **'Clear All Data'**
  String get clearAllData;

  /// Confirmation message for clearing all data
  ///
  /// In en, this message translates to:
  /// **'This will delete all saved devices and settings. Are you sure?'**
  String get clearAllDataConfirm;

  /// Cancel button text
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Clear button text
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Message shown when all data is cleared
  ///
  /// In en, this message translates to:
  /// **'All data cleared'**
  String get allDataCleared;

  /// Text indicating auto-switch is enabled
  ///
  /// In en, this message translates to:
  /// **'Auto-switch enabled'**
  String get autoSwitchEnabled;

  /// Title for temporary debug information
  ///
  /// In en, this message translates to:
  /// **'Debug Info (Temporary):'**
  String get debugInfoTemporary;

  /// Language setting label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// English language option
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// Chinese language option
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get chinese;

  /// Title for bluetooth disabled dialog
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is disabled'**
  String get bluetoothDisabled;

  /// Message for bluetooth disabled dialog
  ///
  /// In en, this message translates to:
  /// **'Please enable Bluetooth to search for devices.'**
  String get bluetoothDisabledMessage;

  /// Button text to open device settings
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// Title for running state dialog
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get runningStateDialogTitle;

  /// Message when both sides are running and user tries to switch to single side
  ///
  /// In en, this message translates to:
  /// **'running with both side, please stop first to control individual side'**
  String get bothModeRunningMessage;

  /// Message when single side is running and user tries to switch to both mode
  ///
  /// In en, this message translates to:
  /// **'running with individual side, please stop first to control both side'**
  String get singleSideRunningMessage;

  /// OK button text
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Section title for diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsSection;

  /// Button to share diagnostic log files
  ///
  /// In en, this message translates to:
  /// **'Export diagnostic logs'**
  String get exportDiagnosticLogs;

  /// Hint under export diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Exports recent app and hardware communication logs for troubleshooting.'**
  String get diagnosticLogsHint;

  /// Shown when log export fails
  ///
  /// In en, this message translates to:
  /// **'Could not export logs. Please try again.'**
  String get exportLogsFailed;

  /// Title for low battery dialog
  ///
  /// In en, this message translates to:
  /// **'Low Battery'**
  String get lowBatteryTitle;

  /// Low battery warning when connecting with insufficient charge
  ///
  /// In en, this message translates to:
  /// **'Low battery for a full session (<20 mins left). Please charge before use.'**
  String get lowBatteryConnectMessage;

  /// Low battery prompt after session completes
  ///
  /// In en, this message translates to:
  /// **'Great job on your session! Battery is insufficient for your next use. Please charge now.'**
  String get lowBatterySessionCompleteMessage;

  /// Primary button on connect low battery dialog
  ///
  /// In en, this message translates to:
  /// **'Got it, go charge'**
  String get lowBatteryGoCharge;

  /// Secondary action on connect low battery dialog
  ///
  /// In en, this message translates to:
  /// **'Continue without charging'**
  String get lowBatteryContinue;

  /// Acknowledge button on session complete low battery dialog
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get lowBatteryGotIt;

  /// Debug menu item to preview connect low battery dialog
  ///
  /// In en, this message translates to:
  /// **'Low Battery Test'**
  String get lowBatteryTest;

  /// Debug menu item to preview session complete low battery dialog
  ///
  /// In en, this message translates to:
  /// **'Session Complete Test'**
  String get sessionCompleteTest;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
