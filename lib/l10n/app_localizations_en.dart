// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Wearable Breast Pump';

  @override
  String get devicesNotSynchronized =>
      'Devices are not synchronized. You can only stop both devices or control them separately.';

  @override
  String get switchToLeftOrRight =>
      'Switch to \"Left\" or \"Right\" to control each device individually.';

  @override
  String get customFlow => 'Custom Flow';

  @override
  String get customFlowInstruction =>
      'Create a custom pumping session by adding phases. Each phase can be either stimulation (fast rhythm) or expression (slower rhythm). Total duration of all phases cannot exceed 30 minutes.';

  @override
  String get customFlowTotalExceeded =>
      'Total duration cannot exceed 30 minutes.';

  @override
  String get mode => 'Mode';

  @override
  String get stimulation => 'Stimulation';

  @override
  String get expression => 'Expression';

  @override
  String get duration => 'Duration';

  @override
  String get minutes => 'min';

  @override
  String get stimulationDescription => 'Fast rhythm to trigger milk letdown';

  @override
  String get expressionDescription =>
      'Slower rhythm to express milk efficiently';

  @override
  String get addPhase => 'Add Phase';

  @override
  String get flowSummary => 'Flow Summary';

  @override
  String totalMinutes(int totalMinutes) {
    return 'Total: $totalMinutes minutes';
  }

  @override
  String get saveCustomFlow => 'Save Custom Flow';

  @override
  String get customFlowSettingDesc => 'Custom pumping flow configuration';

  @override
  String get deviceSettings => 'Device Settings';

  @override
  String get systemSettings => 'System Settings';

  @override
  String get deviceSideSettings => 'Device Side Settings';

  @override
  String get left => 'Left';

  @override
  String get right => 'Right';

  @override
  String get switchToRightSide => 'Switch to Right Side';

  @override
  String get switchToLeftSide => 'Switch to Left Side';

  @override
  String get deviceSideSettingsHint =>
      'Swap the side assignment if you\'ve switched the physical pump position';

  @override
  String get battery => 'Battery: ';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get saveSettings => 'Save Settings';

  @override
  String get breastPumpControl => 'Breast Pump Control';

  @override
  String get connectYourWearableBreastPump =>
      'Connect your wearable breast pump';

  @override
  String get searching => 'Searching...';

  @override
  String get searchForDevices => 'Search for Devices';

  @override
  String get availableDevices => 'Available Devices';

  @override
  String get pairedDevices => 'Paired Devices';

  @override
  String get continueToControl => 'Continue to Control';

  @override
  String connectedToDevice(String deviceName, String side) {
    return 'Connected to $deviceName ($side).';
  }

  @override
  String get deviceRemoved => 'Device removed';

  @override
  String foundDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'devices',
      one: 'device',
    );
    return 'Found $count $_temp0';
  }

  @override
  String get selectPumpSide => 'Select Pump Side';

  @override
  String failedToConnect(String deviceName) {
    return 'Failed to connect to $deviceName';
  }

  @override
  String errorConnecting(String deviceName, String error) {
    return 'Error connecting to $deviceName: $error';
  }

  @override
  String get leftSide => 'Left Side';

  @override
  String get rightSide => 'Right Side';

  @override
  String get connecting => 'Connecting...';

  @override
  String get connect => 'Connect';

  @override
  String get pumpControl => 'Pump Control';

  @override
  String get selectWhichPumpToControl => 'Select which pump(s) to control';

  @override
  String get both => 'Both';

  @override
  String get deviceStatus => 'Device Status';

  @override
  String get notAvailable => 'N/A';

  @override
  String get connected => 'connected';

  @override
  String get disconnected => 'disconnected';

  @override
  String get deviceOff => 'Off';

  @override
  String get deviceConnected => 'Connected';

  @override
  String get tapToReconnect => 'Tap to reconnect';

  @override
  String get reconnectFailed => 'Reconnect failed. Please try again.';

  @override
  String get sessionSettings => 'Session Settings';

  @override
  String get defaultMode => 'Default';

  @override
  String get custom => 'Custom';

  @override
  String get defaultFlow => 'Default Flow';

  @override
  String get beginnerFlow => 'Beginner';

  @override
  String get boostMilkFlow => 'Boost Milk';

  @override
  String get max => 'Max:';

  @override
  String get phase => 'Phase';

  @override
  String get stim => 'Stim';

  @override
  String get expr => 'Expr';

  @override
  String get intensitySettings => 'Intensity Settings';

  @override
  String get suctionLevel => 'Suction level';

  @override
  String get suction => 'Suction';

  @override
  String get hybridPattern => 'Hybrid Pattern';

  @override
  String get hybrid => 'Hybrid';

  @override
  String get hybridPatternDescription => '2 short + 1 long';

  @override
  String get hybridPatternDescriptionShort => '2s + 1L';

  @override
  String get pause => 'Pause';

  @override
  String get start => 'Start';

  @override
  String get stop => 'Stop';

  @override
  String get switchMode => 'Switch';

  @override
  String get manageConnections => 'Manage Connections';

  @override
  String get databaseDebug => 'Database Debug';

  @override
  String get clearAllData => 'Clear All Data';

  @override
  String get clearAllDataConfirm =>
      'This will delete all saved devices and settings. Are you sure?';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get allDataCleared => 'All data cleared';

  @override
  String get autoSwitchEnabled => 'Auto-switch enabled';

  @override
  String get debugInfoTemporary => 'Debug Info (Temporary):';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get chinese => '中文';

  @override
  String get bluetoothDisabled => 'Bluetooth is disabled';

  @override
  String get bluetoothDisabledMessage =>
      'Please enable Bluetooth to search for devices.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get runningStateDialogTitle => 'Notice';

  @override
  String get bothModeRunningMessage =>
      'running with both side, please stop first to control individual side';

  @override
  String get singleSideRunningMessage =>
      'running with individual side, please stop first to control both side';

  @override
  String get ok => 'OK';

  @override
  String get diagnosticsSection => 'Diagnostics';

  @override
  String get exportDiagnosticLogs => 'Export diagnostic logs';

  @override
  String get diagnosticLogsHint =>
      'Exports recent app and hardware communication logs for troubleshooting.';

  @override
  String get exportLogsFailed => 'Could not export logs. Please try again.';
}
