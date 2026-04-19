// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '可穿戴吸奶器';

  @override
  String get devicesNotSynchronized => '设备未同步。您只能同时停止两个设备或分别控制它们。';

  @override
  String get switchToLeftOrRight => '切换到\"左侧\"或\"右侧\"以单独控制每个设备。';

  @override
  String get customFlow => '自定义流程';

  @override
  String get customFlowInstruction =>
      '通过添加阶段创建自定义泵奶流程。每个阶段可以是刺激（快速节奏）或吸乳（较慢节奏）。';

  @override
  String get mode => '模式';

  @override
  String get stimulation => '刺激';

  @override
  String get expression => '吸乳';

  @override
  String get duration => '流程时长';

  @override
  String get minutes => '分钟';

  @override
  String get stimulationDescription => '快速节奏以激发奶阵';

  @override
  String get expressionDescription => '较慢节奏以高效吸乳';

  @override
  String get addPhase => '添加阶段';

  @override
  String get flowSummary => '流程摘要';

  @override
  String totalMinutes(int totalMinutes) {
    return '总计：$totalMinutes 分钟';
  }

  @override
  String get saveCustomFlow => '保存自定义流程';

  @override
  String get customFlowSettingDesc => '自定义泵奶流程设置';

  @override
  String get deviceSettings => '吸奶器设置';

  @override
  String get systemSettings => '系统设置';

  @override
  String get deviceSideSettings => '吸奶器单边设置';

  @override
  String get left => '左侧';

  @override
  String get right => '右侧';

  @override
  String get switchToRightSide => '切换到右侧';

  @override
  String get switchToLeftSide => '切换到左侧';

  @override
  String get deviceSideSettingsHint => '如果您已切吸奶器使用侧边位置，请交换侧边分配';

  @override
  String get battery => '电量：';

  @override
  String get settingsSaved => '设置保存成功';

  @override
  String get saveSettings => '保存设置';

  @override
  String get breastPumpControl => '吸奶器控制';

  @override
  String get connectYourWearableBreastPump => '连接您的可穿戴吸奶器';

  @override
  String get searching => '搜索中...';

  @override
  String get searchForDevices => '搜索设备';

  @override
  String get availableDevices => '可用设备';

  @override
  String get pairedDevices => '已配对设备';

  @override
  String get continueToControl => '前往控制';

  @override
  String connectedToDevice(String deviceName, String side) {
    return '已连接到 $deviceName ($side)。';
  }

  @override
  String get deviceRemoved => '设备已移除';

  @override
  String foundDevices(int count) {
    return '找到 $count 个设备';
  }

  @override
  String get selectPumpSide => '选择吸奶器侧边分配';

  @override
  String failedToConnect(String deviceName) {
    return '连接 $deviceName 失败';
  }

  @override
  String errorConnecting(String deviceName, String error) {
    return '连接 $deviceName 时出错：$error';
  }

  @override
  String get leftSide => '左侧';

  @override
  String get rightSide => '右侧';

  @override
  String get connecting => '连接中...';

  @override
  String get connect => '连接';

  @override
  String get pumpControl => '吸奶器控制';

  @override
  String get selectWhichPumpToControl => '选择要控制的吸奶器';

  @override
  String get both => '两侧';

  @override
  String get deviceStatus => '设备状态';

  @override
  String get notAvailable => '不可用';

  @override
  String get connected => '已连接';

  @override
  String get disconnected => '未连接';

  @override
  String get sessionSettings => '流程设置';

  @override
  String get defaultMode => '默认';

  @override
  String get custom => '自定义';

  @override
  String get defaultFlow => '默认流程';

  @override
  String get max => '最大：';

  @override
  String get phase => '阶段';

  @override
  String get stim => '刺激';

  @override
  String get expr => '吸乳';

  @override
  String get intensitySettings => '强度设置';

  @override
  String get suctionLevel => '吸力级别';

  @override
  String get suction => '吸力';

  @override
  String get hybridPattern => '混合模式';

  @override
  String get hybrid => '混合';

  @override
  String get hybridPatternDescription => '2短 + 1长';

  @override
  String get hybridPatternDescriptionShort => '2短 + 1长';

  @override
  String get pause => '暂停';

  @override
  String get start => '开始';

  @override
  String get stop => '停止';

  @override
  String get switchMode => '切换';

  @override
  String get manageConnections => '管理连接';

  @override
  String get databaseDebug => '数据库调试';

  @override
  String get clearAllData => '清除所有数据';

  @override
  String get clearAllDataConfirm => '这将删除所有已保存的设备和设置。您确定吗？';

  @override
  String get cancel => '取消';

  @override
  String get clear => '清除';

  @override
  String get allDataCleared => '所有数据已清除';

  @override
  String get autoSwitchEnabled => '自动切换已启用';

  @override
  String get debugInfoTemporary => '调试信息（临时）：';

  @override
  String get language => '语言';

  @override
  String get english => 'English';

  @override
  String get chinese => '中文';

  @override
  String get bluetoothDisabled => '蓝牙未开启';

  @override
  String get bluetoothDisabledMessage => '请开启蓝牙以搜索设备。';

  @override
  String get openSettings => '打开设置';

  @override
  String get runningStateDialogTitle => '提示';

  @override
  String get bothModeRunningMessage => '同步控制运行中，需要先停止，再进入单侧控制';

  @override
  String get singleSideRunningMessage => '单侧控制运行中，需要先停止，再进入同步控制';

  @override
  String get ok => '好的';

  @override
  String get diagnosticsSection => '诊断与日志';

  @override
  String get exportDiagnosticLogs => '导出诊断日志';

  @override
  String get diagnosticLogsHint => '导出近期应用与硬件交互记录，便于内测排查问题。';

  @override
  String get exportLogsFailed => '导出失败，请重试。';
}
