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
      '通过添加阶段创建自定义泵奶流程。每个阶段可以是刺激（快速节奏）或吸乳（较慢节奏）。各阶段时长总和不能超过 30 分钟。';

  @override
  String get customFlowTotalExceeded => '各阶段总时长不能超过 30 分钟。';

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
  String get helpAndAbout => '帮助与关于';

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
  String get deviceOff => '关闭';

  @override
  String get deviceConnected => '已连接';

  @override
  String get tapToReconnect => '点击重新连接';

  @override
  String get reconnectFailed => '重连失败，请重试';

  @override
  String get sessionSettings => '流程设置';

  @override
  String get defaultMode => '默认';

  @override
  String get custom => '自定义';

  @override
  String get defaultFlow => '默认流程';

  @override
  String get beginnerFlow => '新手模式';

  @override
  String get boostMilkFlow => '追奶模式';

  @override
  String get boostMilkFlowTab => '追奶流程';

  @override
  String get commonCustomFlows => '常用自定义流程';

  @override
  String get customFlow1 => '自定义流程1';

  @override
  String get customFlow2 => '自定义流程2';

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

  @override
  String get lowBatteryTitle => '电量不足';

  @override
  String get lowBatteryConnectMessage => '电量不足以完成一次完整吸乳（剩余不足 20 分钟）。请先充电后再使用。';

  @override
  String get lowBatteryRunningMessage => '电量剩余不足 20 分钟，请尽快充电。';

  @override
  String get lowBatterySessionCompleteMessage => '本次吸乳已完成！电量不足以支持下次使用，请立即充电。';

  @override
  String get lowBatteryGoCharge => '知道了，去充电';

  @override
  String get lowBatteryContinue => '暂不充电，继续使用';

  @override
  String get lowBatteryGotIt => '知道了';

  @override
  String get lowBatteryTest => '低电量弹窗测试';

  @override
  String get sessionCompleteTest => '结束后充电提示测试';

  @override
  String get icpFilingSection => '备案信息';

  @override
  String get icpFilingLabel => 'ICP 备案号';

  @override
  String get icpFilingHint => '点击备案号可在工信部网站查询核对。';

  @override
  String get icpFilingOpenFailed => '无法打开备案查询页面，请稍后重试。';

  @override
  String get quickConnectGuideTitle => '如何快速连接';

  @override
  String get quickConnectStep1Title => '开机';

  @override
  String get quickConnectStep1Desc => '首先长按电源键开机。';

  @override
  String get quickConnectStep2Title => '进入蓝牙模式';

  @override
  String get quickConnectStep2Desc => '长按切换按钮进入蓝牙模式。';

  @override
  String get quickConnectStep3Title => '搜索并连接';

  @override
  String get quickConnectStep3Desc =>
      '主机屏幕上 L/R 指示灯闪烁表示已进入蓝牙连接模式，点击下方按钮即可搜索设备并建立连接。';

  @override
  String get quickConnectGuideSubtitle => '首次配对后开机自动蓝牙连接；长按切换键将重置蓝牙配对';

  @override
  String get quickConnectGuideDismiss => '知道了';

  @override
  String get videoTutorials => '视频教程';

  @override
  String get videoCategoryFirstUse => '初次使用';

  @override
  String get videoFeatured => '精选';

  @override
  String get videoCountOne => '个视频';

  @override
  String get videoCountOther => '个视频';

  @override
  String get videoUpNext => '接下来播放';

  @override
  String get videoOfficialSource => 'SporraMom 官方';

  @override
  String get videoLoadFailed => '视频加载失败，请检查网络后重试。';

  @override
  String get videoRetry => '重试';

  @override
  String get videoGettingStartedTitle => '首次使用教程';

  @override
  String get videoGettingStartedSubtitle => 'APP 下载＆使用•乳头测试卡•佩戴方法';

  @override
  String get videoGettingStartedDescription =>
      '首次使用全流程指引，涵盖三大步骤：① SporraMom麋鹿妈妈APP 下载与蓝牙配对；② 乳头测试卡的使用方法，帮您找到最适合的法兰罩尺寸；③ 吸奶器的正确佩戴姿势与舒适度调整技巧。';

  @override
  String get videoAssemblyTitle => 'W3 吸奶器安装教程';

  @override
  String get videoAssemblySubtitle => '快速组装，轻松上手';

  @override
  String get videoAssemblyDescription =>
      '手把手演示 SporraMom麋鹿妈妈W3 吸奶器各部件的正确组装顺序，包括集乳杯、硅胶隔膜、喇叭罩、鸭嘴阀等的安装方法及密封性检查，帮助您在首次使用前完成完整安装。';

  @override
  String get videoCleaningTitle => 'W3 吸奶器拆洗教程';

  @override
  String get videoCleaningSubtitle => '便捷拆装、轻松清洗';

  @override
  String get videoCleaningDescription =>
      '详细演示 W3 吸奶器各零部件的拆卸方法、清洗步骤与晾干建议，以及需清洗部件和无需清洗部件的区分，确保每次使用都卫生安全。';

  @override
  String get helpMenuSection => '帮助';

  @override
  String get faqs => '常见问题';

  @override
  String get userManual => '用户手册';

  @override
  String featureComingSoon(String feature) {
    return '$feature即将上线';
  }
}
