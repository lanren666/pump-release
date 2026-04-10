# 项目介绍

## 项目概述

智能吸奶器控制应用，支持通过蓝牙连接设备并进行远程控制。项目集成了涂鸦（Tuya）IoT SDK，实现了设备扫描、配网、连接、控制等功能。

### 原型设计参考

以下 Figma 链接为产品/UI 原型，**仅作参考**；实际界面与交互以代码实现为准，可能与原型存在出入。

- [Wearable Breast Pump App](https://www.figma.com/make/1t9jMRwTbgOf8sSmhYScWk/Wearable-Breast-Pump-App?p=f&t=aptnH90n1RTMHFQD-0)
- [SporraMom W3 App Design](https://www.figma.com/design/99Mu0VeW2nhD5cXE0D86gF/SporraMom-W3-App-Design?node-id=31-1541&t=Oj4agYqPH8Q6cTWJ-0)

### 主要功能

- 蓝牙设备扫描和发现
- 设备配网和连接管理
- 双设备（左右）独立控制
- 自定义吸奶流程设置
- 设备状态实时监控
- 多语言支持（中文/英文）
- 本地数据存储
- 调试模式：可选数据库查看器（首页浮动按钮，需 `AppConfig.debug = true`）

## 技术栈

- **框架**: Flutter 3.8.1+
- **语言**: Dart
- **数据库**: SQLite (sqflite)
- **IoT SDK**: 涂鸦智能 SDK
  - Android: ThingSmart SDK 6.11.0
  - iOS: ThingSmartHomeKit
- **图标**: material_symbols_icons
- **原生开发**:
  - Android: Kotlin
  - iOS: Swift

## 项目结构

### Flutter 代码结构 (`lib/`)

```
lib/
├── main.dart                    # 应用入口，初始化SDK和周期性任务
├── config/                      # 配置文件
│   ├── app_config.dart          # 应用全局配置（涂鸦开关、调试开关、调试语言、Mock 设备等）
│   ├── app_color.dart           # 颜色定义
│   ├── ble_channels.dart        # 蓝牙通信通道定义
│   ├── locale_manager.dart      # 语言管理
│   └── responsive_text.dart     # 响应式文本样式
├── l10n/                        # 国际化资源
│   ├── app_en.arb              # 英文翻译
│   ├── app_zh.arb               # 中文翻译
│   ├── app_localizations.dart   # 本地化代理
│   ├── app_localizations_en.dart
│   └── app_localizations_zh.dart
├── models/                      # 数据模型
│   ├── bluetooth_device.dart    # 蓝牙设备模型
│   ├── connected_device.dart   # 已连接设备模型
│   ├── search_state.dart        # 搜索状态枚举
│   └── setting.dart             # 设置项模型
├── pages/                       # 页面
│   ├── home.dart                # 首页（设备搜索和连接）
│   ├── control.dart             # 控制页（设备控制主界面）
│   ├── custom_flow.dart         # 自定义流程设置页
│   ├── database_viewer.dart     # 数据库查看器（调试用，弹窗展示库表与路径）
│   ├── settings.dart            # 设置页
│   ├── system_settings.dart     # 系统设置页
│   └── widgets/
│       └── pump_side_dialog.dart # 设备侧边选择对话框
└── services/                    # 服务层
    ├── database_service.dart    # 数据库服务（设备、设置存储）
    └── tuya/                    # 涂鸦相关服务
        ├── tuya_sdk_service.dart    # SDK初始化、登录、家庭管理
        ├── ble_dp_service.dart      # DP数据下发服务
        ├── dp_change_handle.dart     # DP上报监听处理
        ├── dp_constants.dart         # DP常量定义
        └── ble_types.dart            # 蓝牙类型定义
```

### Android 原生代码结构

```
android/
├── app/
│   ├── build.gradle.kts         # 应用构建配置
│   ├── src/main/
│   │   ├── AndroidManifest.xml  # 应用清单（权限、SDK配置）
│   │   └── kotlin/com/sporramom/pump/
│   │       ├── MainActivity.kt   # 主Activity（蓝牙扫描、连接、DP处理）
│   │       └── ThingSmartApp.kt # 应用入口（SDK初始化）
│   └── libs/
│       └── security-algorithm-1.0.0-beta.aar  # 涂鸦安全算法库
├── build.gradle.kts             # 项目构建配置
└── gradle.properties            # Gradle属性配置
```

**关键文件说明**:
- `MainActivity.kt`: 实现了所有与 Flutter 的通信通道，包括：
  - 蓝牙扫描（MethodChannel: `com.sporramom/ble_scan`）
  - 设备连接（MethodChannel: `com.sporramom/ble_connection`）
  - DP数据下发（MethodChannel: `com.sporramom/ble_dp`）
  - 事件流（EventChannel）用于实时推送扫描结果、连接状态、DP上报等

### iOS 原生代码结构

```
ios/
├── Runner/
│   ├── AppDelegate.swift         # 应用代理（SDK初始化、蓝牙、连接、DP处理）
│   ├── SceneDelegate.swift       # 场景代理
│   ├── Info.plist               # 应用配置（权限、后台模式）
│   └── Assets.xcassets/         # 资源文件
├── Podfile                      # CocoaPods依赖配置
├── Podfile.lock                 # 依赖锁定文件
└── ThingSmartCryption.podspec   # 涂鸦加密库配置
```

**关键文件说明**:
- `AppDelegate.swift`: 实现了与 Android 端类似的功能，包括：
  - 涂鸦SDK初始化
  - 蓝牙扫描和连接管理
  - DP数据下发和上报监听
  - 位置服务（用于获取国家代码）

## 核心功能模块

### 1. 设备扫描与连接

**流程**:
1. 用户点击"搜索设备"按钮
2. Flutter 调用原生方法 `startScan`
3. 原生端使用涂鸦SDK扫描蓝牙设备
4. 扫描结果通过 EventChannel 实时推送到 Flutter
5. Flutter 展示设备列表
6. 用户选择设备并选择左右位置
7. 调用 `connectDevice` 进行配网或连接

**关键代码位置**:
- Flutter: `lib/pages/home.dart` 的 `_startSearch()` 和 `_connectDevice()`
- Android: `MainActivity.kt` 的 `startBleScan()` 和 `handleConnectDevice()`
- iOS: `AppDelegate.swift` 的 `startBleScan()` 和 `handleConnectDevice()`

### 2. 设备配网（激活）

**流程**:
1. 检查设备是否已配网（`isActive` 属性）
2. 如果未配网，调用涂鸦SDK的配网接口
3. 配网成功后获取 `devId`
4. 通过 EventChannel 发送 `deviceActivated` 事件
5. Flutter 端更新数据库中的 `devId`

**关键代码位置**:
- Android: `MainActivity.kt` 的 `performActiveDevice()`
- iOS: `AppDelegate.swift` 的 `performActiveDevice()`

### 3. DP数据下发

**DP (Data Point) 说明**:
DP是涂鸦设备的功能点，每个DP代表设备的一个功能或状态。

**常用DP定义** (参考 `lib/services/tuya/dp_constants.dart`):
- `deviceSymbol` (111): 设备标识（left/right）
- `sessionSetting` (101): 会话设置（透传型，16进制字符串）
- `sessionStatus` (105): 会话状态（透传型，只上报）
- `batteryLevel` (104): 电池电量（1/2/3）
- 其他控制相关的DP...

**下发流程**:
1. Flutter 调用 `BleDpService.publishDp()` 或 `publishDps()`
2. 通过 MethodChannel 调用原生方法 `publishDps`
3. 原生端使用涂鸦SDK的 `publishDps()` 方法下发
4. 返回成功或失败结果

**关键代码位置**:
- Flutter: `lib/services/tuya/ble_dp_service.dart`
- Android: `MainActivity.kt` 的 `handlePublishDps()`
- iOS: `AppDelegate.swift` 的 `handlePublishDps()`

### 4. DP数据上报监听

**流程**:
1. 设备连接成功后，原生端注册设备监听器
2. 当设备上报DP数据时，SDK回调监听器
3. 原生端通过 EventChannel 推送上报数据到 Flutter
4. Flutter 的 `DpChangeHandle` 处理上报数据
5. 更新UI状态

**关键代码位置**:
- Flutter: `lib/services/tuya/dp_change_handle.dart`
- Android: `MainActivity.kt` 的 `registerDeviceListener()` 和 `onDpUpdate()`
- iOS: `AppDelegate.swift` 的 `setupDeviceDelegate()` 和 `home(_:device:dpsUpdate:)`

### 5. 周期性重连任务

**功能**: 应用启动后，每3秒检查一次已记住但未运行的设备，尝试自动重连。

**实现位置**: `lib/main.dart` 的 `_executePeriodicTask()`

**注意事项**:
- 任务有超时保护（30秒）
- 应用进入后台时继续运行
- 应用退出时清理资源

### 6. 数据库存储

**数据库结构**:
- `connected_devices` 表：存储已连接的设备信息
  - `bluetooth_id`: 蓝牙ID（唯一标识）
  - `dev_id`: 涂鸦设备ID（配网后获取）
  - `name`: 设备名称
  - `battery`: 电量（1/2/3）
  - `position`: 位置（left/right）
  - `is_running`: 是否运行中
  - `is_remembered`: 是否已记住
- `settings` 表：存储应用设置
  - `key`: 设置键
  - `value`: 设置值
  - `desc`: 描述

**关键代码位置**: `lib/services/database_service.dart`

## 配置说明

### 应用配置 (`lib/config/app_config.dart`)

```dart
class AppConfig {
  // 是否启用涂鸦功能
  // true: 启用涂鸦SDK功能
  // false: 禁用涂鸦SDK功能（使用 Mock 设备列表 mockDevices）
  static const bool tuyaEnabled = true;

  // 开发环境指定语言（仅开发环境生效）
  // null: 使用系统语言
  static const Locale? debugLocale = null;

  // 是否启用调试模式
  // true: 首页显示浮动按钮，可打开数据库查看器查看 connected_devices / settings 表内容及库路径
  // false: 不显示调试入口
  static const bool debug = false;

  // Mock 设备列表（当 tuyaEnabled = false 时用于测试）
  static final List<BluetoothDevice> mockDevices = [ ... ];
}
```

**重要**: 生产环境请确保 `tuyaEnabled = true`、`debugLocale = null`、`debug = false`。

### Android 配置

**SDK密钥** (`android/app/src/main/AndroidManifest.xml`):
```xml
<meta-data
    android:name="THING_SMART_APPKEY"
    android:value="ercfdcfwd374mmx9jksq" />
<meta-data
    android:name="THING_SMART_SECRET"
    android:value="yfu9fpp9sth8f5vt4ug5qaguudyfgtcp" />
```

**权限配置**: 已在 `AndroidManifest.xml` 中配置蓝牙和位置权限。

**依赖版本** (`android/app/build.gradle.kts`):
- `compileSdk`: 使用 Flutter 默认版本
- `minSdk`: 23
- `targetSdk`: 使用 Flutter 默认版本
- ThingSmart SDK: 6.11.0

### iOS 配置

**SDK密钥** (`ios/Runner/AppDelegate.swift`):
```swift
let appKey = "sh4p4gvcpe5syh7gv8ea"
let secretKey = "qqy4sucjund43dhx9ea4rfr97349rwnt"
```

**权限配置** (`ios/Runner/Info.plist`):
- `NSBluetoothAlwaysUsageDescription`: 蓝牙权限说明
- `NSLocationWhenInUseUsageDescription`: 位置权限说明
- `UIBackgroundModes`: 支持蓝牙后台模式

**依赖版本** (`ios/Podfile`):
- iOS 最低版本: 12.0
- ThingSmartHomeKit、ThingSmartActivatorBizBundle: 涂鸦 Pod 仓库
- ThingSmartCryption: 本地 podspec（需从涂鸦开发者中心构建）

### 涂鸦官方文档

- [iOS 开发指南（Smart App SDK）](https://developer.tuya.com/cn/docs/app-development/feature-overview?id=Ka5cgmlybhjk8)
- [安卓开发指南（Smart App SDK）](https://developer.tuya.com/cn/docs/app-development/featureoverview?id=Ka69nt97vtsfu)
- [应用发布](https://developer.tuya.com/cn/docs/iot/app-realease?id=Kaiuys16nexhd)（App Store / Google Play / 国内安卓市场等）

## 开发环境搭建

### 前置要求

1. **Flutter SDK**: 3.8.1 或更高版本
2. **Android Studio**: 最新版本
   - Android SDK
   - Kotlin 插件
3. **Xcode**: 最新版本（macOS）
   - CocoaPods
4. **设备**: 
   - Android 设备（Android 6.0+）或模拟器
   - iOS 设备（iOS 12.0+）或模拟器

### 安装步骤

1. **克隆项目**（如果适用）

2. **安装 Flutter 依赖**:
```bash
flutter pub get
```

3. **Android 配置**:
```bash
cd android
# 确保 local.properties 中配置了 Android SDK 路径
# 如果需要，运行 gradlew 构建一次以验证配置
./gradlew build
```

4. **iOS 配置**:
```bash
cd ios
pod install
cd ..
```

5. **生成国际化文件**:
```bash
flutter gen-l10n
```

### TestFlight 上架

1. 用已加入该团队的 Apple ID 在 Xcode 里登录；
2. 打开本工程，在 **Signing & Capabilities** 里勾选 **Automatically manage signing** 并选对 Team;
3. Xcode 会自动从苹果后台拉取/生成描述文件，也可以自己在 [Certificates](https://developer.apple.com/account/resources/certificates/list) 里申请 Distribution 证书（生成 CSR → 上传 → 下载 .cer 安装）。
