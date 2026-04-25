import Flutter
import UIKit
import CoreBluetooth
import CoreLocation

extension Date {
    /// ISO8601 可读时间字符串（尽量包含毫秒）。
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        if #available(iOS 11.0, *) {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        } else {
            formatter.formatOptions = [.withInternetDateTime]
        }
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: self)
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate {
    private let CHANNEL = "com.sporramom/ble_scan"
    private let EVENT_CHANNEL = "com.sporramom/ble_scan_events"
    private let CONNECTION_CHANNEL = "com.sporramom/ble_connection"
    private let CONNECTION_EVENT_CHANNEL = "com.sporramom/ble_connection_events"
    private let DP_CHANNEL = "com.sporramom/ble_dp"
    private let DP_EVENT_CHANNEL = "com.sporramom/ble_dp_events"

    private var eventSink: FlutterEventSink?
    var connectionEventSink: FlutterEventSink?
    var dpEventSink: FlutterEventSink?

    private var isScanning = false
    private var bleManager: ThingSmartBLEManager?
    private var centralManager: CBCentralManager?
    private var homeManager: ThingSmartHomeManager?
    private var locationManager: CLLocationManager?
    
    // 家庭实例，用于监听 DPS 更新
    private var home: ThingSmartHome?

    // 位置信息
    private var currentLatitude: Double = 0.0
    private var currentLongitude: Double = 0.0
    private var countryCode: String = "1" // 默认美国
    private var locationCompletion: ((Bool) -> Void)?

    // 设备连接状态管理
    private var deviceConnectionStates: [String: String] = [:] // deviceId -> state

    // 扫描到的设备信息映射（uuid -> ThingBLEAdvModel）
    private var scannedDevices: [String: ThingBLEAdvModel] = [:]

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 关键修复：先让 FlutterAppDelegate 完全初始化，不要在这里初始化第三方 SDK
        // 这可以避免干扰 Flutter 引擎的内存保护机制
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        // 确保插件已注册（FlutterAppDelegate 应该自动处理，但为了确保，我们显式注册）
        // 延迟注册以确保 Flutter 引擎完全初始化
        DispatchQueue.main.async { [weak self] in
            if let controller = self?.window?.rootViewController as? FlutterViewController {
                let engine = controller.engine
                GeneratedPluginRegistrant.register(with: engine)
                print("✅ 插件已注册")
            } else {
                // 如果 FlutterViewController 还没准备好，稍后重试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    if let controller = self?.window?.rootViewController as? FlutterViewController {
                        let engine = controller.engine
                        GeneratedPluginRegistrant.register(with: engine)
                        print("✅ 插件已注册（延迟）")
                    }
                }
            }
        }

        // 初始化 CBCentralManager（需要 delegate 来获取状态更新）
        centralManager = CBCentralManager(delegate: self, queue: nil)

        // 先获取位置信息（在初始化SDK之前）
        requestLocationPermission()

        // 延迟设置 channels，确保 FlutterViewController 已准备好
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupFlutterChannels()
            self?.initializeTuyaSDK()
        }

        return result
    }


    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateString: String
        switch central.state {
        case .unknown: stateString = "unknown"
        case .resetting: stateString = "resetting"
        case .unsupported: stateString = "unsupported"
        case .unauthorized: stateString = "unauthorized"
        case .poweredOff: stateString = "poweredOff"
        case .poweredOn: stateString = "poweredOn"
        @unknown default: stateString = "unknown"
        }
        print("🔵 蓝牙状态更新: \(stateString)")
    }

    // MARK: - Location Services
    private func requestLocationPermission() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyKilometer // 使用较低精度以节省电量
        locationManager?.requestWhenInUseAuthorization()
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 位置权限已授权，开始获取位置...")
            locationManager?.requestLocation()
        case .denied, .restricted:
            print("⚠️ 位置权限被拒绝，使用默认值")
            // 使用默认值
            countryCode = "1"
        case .notDetermined:
            print("📍 位置权限未确定")
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        currentLatitude = location.coordinate.latitude
        currentLongitude = location.coordinate.longitude

        print("📍 获取到位置: lat=\(currentLatitude), lon=\(currentLongitude)")

        // 获取国家代码
        getCountryCode(from: location)

        // 停止位置更新以节省电量
        locationManager?.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ 获取位置失败: \(error.localizedDescription)")
        // 使用默认值
        countryCode = "1"
    }

    private func getCountryCode(from location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                print("❌ 反向地理编码失败: \(error.localizedDescription)")
                self?.countryCode = "1" // 使用默认值
                return
            }

            guard let placemark = placemarks?.first else {
                print("⚠️ 未找到位置信息")
                self?.countryCode = "1"
                return
            }

            // 获取国家代码
            if let isoCountryCode = placemark.isoCountryCode {
                // 将 ISO 国家代码转换为电话国家代码
                // 这里使用一个简化的映射，实际应该使用完整的映射表
                self?.countryCode = self?.getPhoneCountryCode(from: isoCountryCode) ?? "1"
                print("✅ 获取到国家代码: ISO=\(isoCountryCode), Phone=\(self?.countryCode ?? "1")")
            } else {
                print("⚠️ 未找到国家代码")
                self?.countryCode = "1"
            }
        }
    }

    private func getPhoneCountryCode(from isoCode: String) -> String {
        // 简化的国家代码映射（常用国家）
        let countryCodeMap: [String: String] = [
            "US": "1", // 美国
            "CN": "86", // 中国
            "GB": "44", // 英国
            "JP": "81", // 日本
            "KR": "82", // 韩国
            "DE": "49", // 德国
            "FR": "33", // 法国
            "IT": "39", // 意大利
            "ES": "34", // 西班牙
            "CA": "1", // 加拿大
            "AU": "61", // 澳大利亚
            "IN": "91", // 印度
            "BR": "55", // 巴西
            "MX": "52", // 墨西哥
            "RU": "7", // 俄罗斯
        ]

        return countryCodeMap[isoCode.uppercased()] ?? "1" // 默认返回美国
    }

    private func initializeTuyaSDK() {
        // 如果已经初始化，跳过
        if bleManager != nil {
            return
        }

        // 确保 CBCentralManager 已初始化
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }

        // 初始化涂鸦SDK
        let appKey = "sh4p4gvcpe5syh7gv8ea"
        let secretKey = "qqy4sucjund43dhx9ea4rfr97349rwnt"

        print("========================================")
        print("ThingSmartApp: Initializing Tuya SDK (delayed)")

        let sdk = ThingSmartSDK.sharedInstance()

        // #if DEBUG
        // sdk.debugMode = true
        // #endif

        sdk.start(withAppKey: appKey, secretKey: secretKey)
        bleManager = ThingSmartBLEManager.sharedInstance()
        homeManager = ThingSmartHomeManager()

        if bleManager != nil {
            print("ThingSmartApp: ✓ SDK initialized")

            // 设置BLE Manager的delegate来接收扫描结果
            bleManager?.delegate = self

            // 监听设备状态变化
            setupDeviceStatusObserver()
            
            // 初始化家庭并设置 delegate 来监听 DPS 更新
            initHome()
        } else {
            print("ThingSmartApp: ✗ SDK initialization failed")
        }
        print("========================================")
    }
    
    /// 在应用变为活跃状态时，确保 home delegate 仍然有效
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        // 重新确保 home delegate 设置
        getFirstHome { [weak self] homeModel in
            guard let self = self, let homeModel = homeModel else {
                return
            }
            self.ensureHomeDelegate(homeId: homeModel.homeId)
        }
    }
    
    // MARK: - Home Initialization
    /// 初始化家庭并设置 delegate 来监听 DPS 更新
    private func initHome() {
        getFirstHome { [weak self] homeModel in
            guard let self = self, let homeModel = homeModel else {
                print("⚠️ 未找到家庭，无法初始化 DPS 监听")
                return
            }
            
            let homeId = homeModel.homeId
            self.ensureHomeDelegate(homeId: homeId)
            print("✅ 已初始化家庭 DPS 监听: homeId=\(homeId)")
            
            // 打印设备信息以便调试
            if let deviceList = self.home?.deviceList {
                print("📱 当前家庭设备列表: \(deviceList.count) 个设备")
                for device in deviceList {
                    let devId = device.devId ?? "unknown"
                    let uuid = device.uuid ?? "unknown"
                    let deviceName = device.name ?? "unknown"
                    print("  - 设备 devId: \(devId), uuid: \(uuid), 名称: \(deviceName), 在线: \(device.isOnline)")

                    // 发送设备激活事件到 Flutter 端，用于更新 available device 的 devId
                    // deviceId 对应 bluetoothId (即 uuid)，devId 对应设备的 devId
                    if uuid != "unknown" && devId != "unknown" {
                        let eventData: [String: Any] = [
                            "type": "deviceActivated",
                            "deviceId": uuid,
                            "devId": devId
                        ]

                        do {
                            let jsonData = try JSONSerialization.data(withJSONObject: eventData)
                            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                            self.connectionEventSink?(jsonString)
                            print("📤 已发送设备激活事件: uuid=\(uuid), devId=\(devId)")
                        } catch {
                            print("❌ 编码设备激活事件失败: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    /// 确保 home 实例存在且 delegate 已设置
    /// 如果 home 不存在或 delegate 未设置，则重新创建并设置
    private func ensureHomeDelegate(homeId: Int64) {
        // 检查当前 home 实例是否有效
        if let currentHome = self.home {
            // 检查 homeId 是否匹配
            if currentHome.homeModel.homeId == homeId {
                // 检查 delegate 是否已设置
                if currentHome.delegate === self {
                    print("✅ Home delegate 已正确设置: homeId=\(homeId)")
                    return
                } else {
                    print("⚠️ Home delegate 丢失，重新设置: homeId=\(homeId)")
                    currentHome.delegate = self
                    return
                }
            } else {
                // homeId 不匹配，需要重新创建
                print("⚠️ Home ID 不匹配，重新创建: 当前=\(currentHome.homeModel.homeId), 需要=\(homeId)")
            }
        }
        
        // 如果 home 不存在或 ID 不匹配，创建新实例
        print("🔄 创建新的 home 实例: homeId=\(homeId)")
        self.home = ThingSmartHome(homeId: homeId)
        self.home?.delegate = self
        print("✅ Home 实例已创建并设置 delegate: homeId=\(homeId)")
        
        // 重要：必须先调用 getDetailWithSuccess，否则无法成功获取设备列表（根据文档要求）
        self.home?.getDetailWithSuccess({ [weak self] _ in
            print("✅ Home 详细信息已获取，设备列表已更新: homeId=\(homeId)")
            if let deviceList = self?.home?.deviceList {
                print("📱 当前家庭设备列表: \(deviceList.count) 个设备")
            }
        }, failure: { (error: Error?) in
            print("⚠️ 获取 Home 详细信息失败: \(error?.localizedDescription ?? "unknown")")
        })
    }
    
    /// 刷新 home 设备列表（设备激活后调用，确保新设备能被识别）
    private func refreshHomeDeviceList(homeId: Int64, completion: @escaping () -> Void) {
        ensureHomeDelegate(homeId: homeId)
        
        // 如果 home 已存在，需要刷新设备列表以包含新激活的设备
        if let home = self.home {
            home.getDetailWithSuccess({ [weak self] _ in
                print("✅ Home 设备列表已刷新（设备激活后）")
                if let deviceList = self?.home?.deviceList {
                    print("📱 当前家庭设备列表: \(deviceList.count) 个设备")
                }
                completion()
            }, failure: { (error: Error?) in
                print("⚠️ 刷新 Home 设备列表失败: \(error?.localizedDescription ?? "unknown")")
                // 即使失败也继续执行
                completion()
            })
        } else {
            // 如果 home 不存在，直接执行 completion
            completion()
        }
    }

    // MARK: - Device Status Observer
    private var deviceDelegates: [String: ThingSmartDeviceDelegate] = [:] // deviceId -> delegate

    private func setupDeviceStatusObserver() {
        // 监听设备状态变化通知
        // Tuya SDK使用通知来通知设备状态变化

        // 设备在线状态变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOnlineStatusChanged(_:)),
            name: NSNotification.Name("kNotificationDeviceOnlineStatusChanged"),
            object: nil
        )

        // DP更新通知（备用方案，如果delegate不工作）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDpUpdate(_:)),
            name: NSNotification.Name("kNotificationDeviceDpUpdate"),
            object: nil
        )
    }

    @objc private func deviceOnlineStatusChanged(_ notification: Notification) {
        // 处理设备在线状态变化
        guard let userInfo = notification.userInfo,
              let deviceId = userInfo["deviceId"] as? String
        else {
            return
        }

        // 尝试从userInfo获取在线状态
        if let isOnline = userInfo["isOnline"] as? Bool {
            let state = isOnline ? "connected" : "disconnected"
            updateConnectionState(deviceId: deviceId, state: state)
        }
    }

    @objc private func deviceDpUpdate(_ notification: Notification) {
        // 处理DP上报（通过通知）
        guard let userInfo = notification.userInfo,
              let deviceId = userInfo["deviceId"] as? String,
              let dps = userInfo["dps"] as? [String: Any]
        else {
            return
        }

        handleDpReport(deviceId: deviceId, dps: dps)
    }

    // 为设备设置delegate以监听DP更新
    private func setupDeviceDelegate(deviceId: String) {
        guard deviceDelegates[deviceId] == nil,
              let device = ThingSmartDevice(deviceId: deviceId)
        else {
            return
        }

        let delegate = DeviceDpDelegate(deviceId: deviceId) { [weak self] deviceId, dps in
            self?.handleDpReport(deviceId: deviceId, dps: dps)
        }

        device.delegate = delegate
        deviceDelegates[deviceId] = delegate
        print("✅ 已为设备设置DP监听: \(deviceId)")
    }

    // 移除设备delegate
    private func removeDeviceDelegate(deviceId: String) {
        if let device = ThingSmartDevice(deviceId: deviceId) {
            device.delegate = nil
        }
        deviceDelegates.removeValue(forKey: deviceId)
    }

    private func setupFlutterChannels() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            // 如果rootViewController还没准备好，延迟设置
            print("⚠️ FlutterViewController 未准备好，0.2秒后重试...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.setupFlutterChannels()
            }
            return
        }

        print("✅ FlutterViewController 已准备好，设置 channels...")

        // MethodChannel for scan control
        let methodChannel = FlutterMethodChannel(
            name: CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )

        print("✅ MethodChannel 已创建: \(CHANNEL)")

        methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            print("📞 收到方1法调用: \(call.method)")
            guard let self = self else {
                return
            }

            switch call.method {
            case "checkSDKInitialized":
                // 检查SDK是否已初始化
                let isInitialized = self.bleManager != nil
                result(isInitialized)
            case "checkBluetoothEnabled":
                // 检查蓝牙是否已开启
                // 确保 centralManager 已初始化
                if self.centralManager == nil {
                    self.centralManager = CBCentralManager(delegate: self, queue: nil)
                }
                
                if let centralManager = self.centralManager {
                    let state = centralManager.state
                    // 如果状态是 unknown 或 resetting，等待一下再检查
                    if state == .unknown || state == .resetting {
                        // 等待状态更新
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            if let centralManager = self?.centralManager {
                                let isEnabled = centralManager.state == .poweredOn
                                result(isEnabled)
                            } else {
                                result(false)
                            }
                        }
                    } else {
                        let isEnabled = state == .poweredOn
                        result(isEnabled)
                    }
                } else {
                    result(false)
                }
            case "openBluetoothSettings":
                // 打开系统设置（iOS 无法直接打开蓝牙设置，只能打开应用设置）
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    if UIApplication.shared.canOpenURL(settingsUrl) {
                        UIApplication.shared.open(settingsUrl, completionHandler: { success in
                            if success {
                                print("✅ 已打开系统设置")
                            } else {
                                print("❌ 打开系统设置失败")
                            }
                        })
                        result(true)
                    } else {
                        result(FlutterError(code: "OPEN_SETTINGS_FAILED", message: "Cannot open settings", details: nil))
                    }
                } else {
                    result(FlutterError(code: "OPEN_SETTINGS_FAILED", message: "Invalid settings URL", details: nil))
                }
            case "loginAnonymous":
                self.handleLoginAnonymous(call: call, result: result)
            case "getHomeList":
                self.handleGetHomeList(result: result)
            case "addHome":
                self.handleAddHome(call: call, result: result)
            case "startScan":
                print("🔄 Processing startScan request...")
                if self.isScanning {
                    print("⚠️ Scan already in progress, stopping current scan first...")
                    self.stopBleScan()
                    // 延迟一点时间后重新开始扫描，确保停止操作完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.startBleScan(result: result)
                    }
                } else {
                    self.startBleScan(result: result)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // EventChannel for scan results
        let eventChannel = FlutterEventChannel(
            name: EVENT_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )

        print("✅ EventChannel 已创建: \(EVENT_CHANNEL)")

        eventChannel.setStreamHandler(self)

        // 设置连接相关的MethodChannel和EventChannel
        setupConnectionChannels(controller: controller)

        // 设置DP相关的MethodChannel和EventChannel
        setupDpChannels(controller: controller)
    }

    // MARK: - Connection Channels Setup
    private func setupConnectionChannels(controller: FlutterViewController) {
        let connectionMethodChannel = FlutterMethodChannel(
            name: CONNECTION_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )

        print("✅ Connection MethodChannel 已创建: \(CONNECTION_CHANNEL)")

        connectionMethodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            print("📞 收到连接方法调用: \(call.method)")
            guard let self = self else {
                return
            }

            switch call.method {
            case "connectDevice":
                self.handleConnectDevice(call: call, result: result)
            case "isDeviceOnline":
                self.handleIsDeviceOnline(call: call, result: result)
            case "checkDevicesOnline":
                self.handleCheckDevicesOnline(call: call, result: result)
            case "connectBleDevices":
                self.handleConnectBleDevices(call: call, result: result)
            case "removeDevice":
                self.handleRemoveDevice(call: call, result: result)
            case "registerDeviceListener":
                self.handleRegisterDeviceListener(call: call, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let connectionEventChannel = FlutterEventChannel(
            name: CONNECTION_EVENT_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )

        print("✅ Connection EventChannel 已创建: \(CONNECTION_EVENT_CHANNEL)")

        connectionEventChannel.setStreamHandler(ConnectionStreamHandler(delegate: self))
    }

    // MARK: - DP Channels Setup
    private func setupDpChannels(controller: FlutterViewController) {
        let dpMethodChannel = FlutterMethodChannel(
            name: DP_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )

        print("✅ DP MethodChannel 已创建: \(DP_CHANNEL)")

        dpMethodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            print("📞 收到DP方法调用: \(call.method)")
            guard let self = self else {
                return
            }

            switch call.method {
            case "publishDps":
                self.handlePublishDps(call: call, result: result)
            case "getDp":
                self.handleGetDp(call: call, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let dpEventChannel = FlutterEventChannel(
            name: DP_EVENT_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )

        print("✅ DP EventChannel 已创建: \(DP_EVENT_CHANNEL)")

        dpEventChannel.setStreamHandler(DpStreamHandler(delegate: self))
    }

    private func handleLoginAnonymous(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("🔐 开始匿名111登录...")

        // 先检查是否已经登录
        if ThingSmartUser.sharedInstance().isLogin {
            print("✅ 用户已经登录，跳过登录步骤")
            result(true)
            return
        }

        // 获取参数，如果没有则使用默认值
        let args = call.arguments as? [String: Any]
        // 使用从位置信息获取的真实国家代码，如果没有则使用参数或默认值
        let countryCode = args?["countryCode"] as? String ?? self.countryCode
        let userName = args?["userName"] as? String ?? UIDevice.current.name // 设备名称

        print("🔐 使用国家代码: \(countryCode), 用户名: \(userName)")
        loginAnonymous(countryCode: countryCode, userName: userName, result: result)
    }

    private func loginAnonymous(countryCode: String, userName: String, result: @escaping FlutterResult) {
        ThingSmartUser.sharedInstance().registerAnonymous(withCountryCode: countryCode, userName: userName, success: {
            print("✅ 匿名登录成功")
            result(true)
        }, failure: { error in
            if let e = error {
                print("❌ 匿名登录失败: \(e.localizedDescription)")
                result(FlutterError(code: "ANONYMOUS_LOGIN_FAILED", message: e.localizedDescription, details: nil))
            } else {
                print("❌ 匿名登录失败: unknown error")
                result(FlutterError(code: "ANONYMOUS_LOGIN_FAILED", message: "Unknown error", details: nil))
            }
        })
    }

    private func handleGetHomeList(result: @escaping FlutterResult) {
        print("🏠 获取家庭列表...")
        getHomeList { homes in
            guard let homes = homes else {
                result(FlutterError(code: "GET_HOME_LIST_FAILED", message: "Failed to get home list", details: nil))
                return
            }

            // 将家庭列表转换为字典数组
            var homeList: [[String: Any]] = []
            for home in homes {
                var homeDict: [String: Any] = [
                    "homeId": home.homeId,
                    "name": home.name ?? "",
                    "geoName": home.geoName ?? "",
                    "latitude": home.latitude,
                    "longitude": home.longitude
                ]
                homeList.append(homeDict)
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: homeList)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
                print("✅ 获取家庭列表成功: \(homes.count) 个家庭")
                result(jsonString)
            } catch {
                print("❌ 序列化家庭列表失败: \(error)")
                result(FlutterError(code: "JSON_ERROR", message: "Failed to encode home list", details: nil))
            }
        }
    }

    private func handleAddHome(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("🏠 创建家庭...")

        guard let args = call.arguments as? [String: Any],
              let homeName = args["homeName"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "homeName is required", details: nil))
            return
        }

        let geoName = args["geoName"] as? String ?? ""
        let rooms = args["rooms"] as? [String] ?? ["默认房间"]
        let latitude = args["latitude"] as? Double ?? currentLatitude
        let longitude = args["longitude"] as? Double ?? currentLongitude

        print("🏠 创建家庭: name=\(homeName), geoName=\(geoName), lat=\(latitude), lon=\(longitude)")

        // 确保 homeManager 已初始化
        let manager = homeManager ?? ThingSmartHomeManager()

        manager.addHome(withName: homeName, geoName: geoName, rooms: rooms, latitude: latitude, longitude: longitude, success: { [weak self] homeId in
            print("✅ 创建家庭成功: homeId=\(homeId)")
            // 创建家庭成功后，确保 home delegate 设置
            self?.ensureHomeDelegate(homeId: homeId)
            result(String(homeId))
        }, failure: { error in
            if let e = error {
                print("❌ 创建家庭失败: \(e.localizedDescription)")
                result(FlutterError(code: "ADD_HOME_FAILED", message: e.localizedDescription, details: nil))
            } else {
                print("❌ 创建家庭失败: unknown error")
                result(FlutterError(code: "ADD_HOME_FAILED", message: "Unknown error", details: nil))
            }
        })
    }

    private func startBleScan(result: @escaping FlutterResult) {
        // 确保 centralManager 已初始化
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }

        // 检查蓝牙状态
        let bluetoothState = centralManager?.state ?? .unknown

        let stateString: String
        switch bluetoothState {
        case .unknown: stateString = "unknown"
        case .resetting: stateString = "resetting"
        case .unsupported: stateString = "unsupported"
        case .unauthorized: stateString = "unauthorized"
        case .poweredOff: stateString = "poweredOff"
        case .poweredOn: stateString = "poweredOn"
        @unknown default: stateString = "unknown"
        }

        print("🔵 开始扫描前检查蓝牙状态: \(stateString) (rawValue: \(bluetoothState.rawValue))")

        // 如果状态是 unknown 或 resetting，等待一下再检查（CBCentralManager 需要时间初始化）
        if bluetoothState == .unknown || bluetoothState == .resetting {
            print("⚠️ 蓝牙状态未就绪(\(stateString))，等待 1 秒后重试...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startBleScan(result: result)
            }
            return
        }

        if bluetoothState != .poweredOn {
            let errorMsg = "Bluetooth is not enabled (state: \(stateString))"
            print("❌ \(errorMsg)")
            result(FlutterError(code: "BLUETOOTH_DISABLED", message: errorMsg, details: nil))
            return
        }

        guard let bleManager = bleManager else {
            result(FlutterError(code: "SDK_ERROR", message: "BLE manager not available", details: nil))
            return
        }

        isScanning = true

        // 根据文档使用 startListening 方法开始扫描
        // 扫描结果会通过 ThingSmartBLEManagerDelegate 的 didDiscoveryDeviceWithDeviceInfo 方法返回
        bleManager.startListening(false) // false 表示不清除缓存

        // 设置扫描超时定时器（10秒）
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self else { return }
            if self.isScanning {
                print("⏰ Scan timeout (10s), resetting isScanning flag")
                self.isScanning = false
                self.bleManager?.stopListening(false)
                DispatchQueue.main.async {
                    self.eventSink?("SCAN_TIMEOUT")
                }
            }
        }

        result("Scan started")
    }

    private func stopBleScan() {
        if !isScanning {
            print("stopBleScan called but not scanning")
            return
        }

        print("Stopping BLE scan...")
        isScanning = false
        // bleManager?.stopListenCore(true)
        bleManager?.stopListening(false)

        DispatchQueue.main.async { [weak self] in
            self?.eventSink?("SCAN_STOPPED")
        }
    }

    // MARK: - Connection Handlers
    private func handleConnectDevice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              let uuid = args["uuid"] as? String,
              let productKey = args["productKey"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "deviceId, uuid, and productKey are required", details: nil))
            return
        }

        let timeout = (args["timeout"] as? Int) ?? 10
        // 处理 homeId，可能是 Int 或 NSNumber
        let homeId: NSNumber?
        if let homeIdInt = args["homeId"] as? Int {
            homeId = NSNumber(value: homeIdInt)
        } else if let homeIdNumber = args["homeId"] as? NSNumber {
            homeId = homeIdNumber
        } else {
            homeId = nil
        }

        print("🔗 开始连接设备: \(deviceId), uuid: \(uuid), productKey: \(productKey), 超时: \(timeout)秒")

        // 使用BLE Manager连接设备
        guard let bleManager = bleManager else {
            result(FlutterError(code: "SDK_ERROR", message: "BLE manager not available", details: nil))
            updateConnectionState(deviceId: deviceId, state: "disconnected", error: "BLE manager not available")
            return
        }

        // 检查设备是否需要配网
        if let deviceInfo = scannedDevices[uuid] {
            if !deviceInfo.isActive {
                print("📱 设备未配网，需要先激活: \(uuid)")
                // 需要先配网
                activeDevice(deviceInfo: deviceInfo, homeId: homeId, deviceId: deviceId, uuid: uuid, productKey: productKey, result: result)
            } else {
                print("✅ 设备已配网，直接连接: \(uuid)")
                // 设备已配网，直接连接
                connectDeviceDirectly(deviceId: deviceId, uuid: uuid, productKey: productKey, devId: nil, result: result)
            }
        } else {
            // 设备信息不在扫描结果中，可能是已配网的设备，直接尝试连接
            print("⚠️ 设备信息不在扫描结果中，尝试直接连接: \(uuid)")
            connectDeviceDirectly(deviceId: deviceId, uuid: uuid, productKey: productKey, devId: nil, result: result)
        }
    }

    // 激活设备（配网）
    private func activeDevice(deviceInfo: ThingBLEAdvModel, homeId: NSNumber?, deviceId: String, uuid: String, productKey: String, result: @escaping FlutterResult) {
        // 开始配网时立即停止扫描（如果还在扫描的话）
        if isScanning {
            print("📱 开始配网，停止扫描...")
            stopBleScan()
        }
        
        // 获取 homeId，优先使用传入的，否则从数据库读取
        if let homeId = homeId {
            // 如果已传入 homeId，直接使用
            performActiveDevice(deviceInfo: deviceInfo, homeId: homeId, deviceId: deviceId, uuid: uuid, productKey: productKey, result: result)
        } else {
            // 如果没有传入 homeId，尝试从第一个家庭获取
            getFirstHome { [weak self] homeModel in
                guard let self = self, let homeModel = homeModel else {
                    result(FlutterError(code: "HOME_NOT_FOUND", message: "Home not found, please create a home first", details: nil))
                    return
                }
                let targetHomeId = NSNumber(value: homeModel.homeId)
                self.performActiveDevice(deviceInfo: deviceInfo, homeId: targetHomeId, deviceId: deviceId, uuid: uuid, productKey: productKey, result: result)
            }
        }
    }

    private func performActiveDevice(deviceInfo: ThingBLEAdvModel, homeId: NSNumber, deviceId: String, uuid: String, productKey: String, result: @escaping FlutterResult) {
        print("📱 开始激活设备: \(uuid), homeId: \(homeId)")
        updateConnectionState(deviceId: deviceId, state: "activating")

        let homeIdInt64 = homeId.int64Value

        ThingSmartBLEManager.sharedInstance().activeBLE(deviceInfo, homeId: homeIdInt64, success: { [weak self] deviceModel in
            print("✅ 设备激活成功: \(deviceId)")
            print("deviceModel: \(deviceModel)")
            // 配网连接成功后，获取当前家庭的设备列表
            // self?.getHomeDataInfo()
            let eventData: [String: Any] = [
                "type": "deviceActivated",
                "deviceId": deviceModel.uuid ?? "",
                "devId": deviceModel.devId ?? ""
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: eventData)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                self?.connectionEventSink?(jsonString)
                print("📤 已发送设备激活事件: uuid=\(deviceModel.uuid ?? ""), devId=\(deviceModel.devId ?? "")")
            } catch {
                print("❌ 编码设备激活事件失败: \(error)")
            }
            let devId = deviceModel.devId ?? ""
            let homeIdInt64 = homeId.int64Value
            
            // 设备激活成功后，刷新 home 设备列表（确保新激活的设备能被识别）
            // 然后连接设备
            self?.refreshHomeDeviceList(homeId: homeIdInt64) { [weak self] in
                self?.connectDeviceDirectly(deviceId: deviceId, uuid: uuid, productKey: productKey, devId: devId, result: result)
            }
        }, failure: { [weak self] in
            let errorMessage = "Device activation failed"
            let errorDetails: [String: Any] = [
                "deviceId": deviceId,
                "uuid": uuid,
                "productKey": productKey,
                "homeId": homeIdInt64
            ]

            print("❌ 设备激活失败: \(errorMessage), details=\(errorDetails)")
            self?.updateConnectionState(deviceId: deviceId, state: "disconnected", error: errorMessage)
            result(FlutterError(
                code: "ACTIVATION_FAILED",
                message: errorMessage,
                details: errorDetails
            ))
        })
    }

    // 直接连接设备（已配网）
    private func connectDeviceDirectly(deviceId: String, uuid: String, productKey: String, devId: String? = nil, result: @escaping FlutterResult) {
        print("🔗 开始连接设备: \(deviceId)")
        updateConnectionState(deviceId: deviceId, state: "connecting")

        // 如果devId为空，尝试从home的设备列表中查找
        var finalDevId = devId ?? ""
        if finalDevId.isEmpty {
            if let deviceList = home?.deviceList {
                if let device = deviceList.first(where: { $0.uuid == uuid }) {
                    finalDevId = device.devId ?? ""
                    print("📱 从home设备列表获取devId: \(finalDevId)")
                }
            }
        }

        // 根据文档使用 connectBLEWithUUID 方法连接离线设备
        ThingSmartBLEManager.sharedInstance().connectBLE(withUUID: uuid, productKey: productKey, success: { [weak self] in
            let successMsg = "✅ 设备连接成功: \(deviceId)"
            NSLog("%@", successMsg)
            print(successMsg)
            self?.updateConnectionState(deviceId: deviceId, state: "connected")
            // 连接成功后设置DP监听（使用devId，不是bluetoothId）
            if !finalDevId.isEmpty {
                self?.setupDeviceDelegate(deviceId: finalDevId)
                print("📡 已为设备设置DP监听: devId=\(finalDevId), bluetoothId=\(deviceId)")
            } else {
                print("⚠️ devId为空，无法设置DP监听: bluetoothId=\(deviceId)")
            }
            
            // 返回包含devId的字典
            let resultData: [String: Any] = [
                "success": true,
                "devId": finalDevId
            ]
            result(resultData)
        }, failure: { [weak self] in
            let errorMessage = "Connection failed"
            self?.updateConnectionState(deviceId: deviceId, state: "disconnected", error: errorMessage)
            result(FlutterError(
                code: "CONNECTION_FAILED",
                message: errorMessage,
                details: [
                    "deviceId": deviceId,
                    "uuid": uuid,
                    "productKey": productKey,
                    "note": "ThingFailureHandler does not provide error details"
                ]
            ))
        })
    }

    private func handleIsDeviceOnline(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "deviceId is required", details: nil))
            return
        }

        // 检查设备是否在线（本地BLE连接）
        guard let bleManager = bleManager else {
            result(false)
            return
        }

        // 通过Home Manager获取设备信息（包含UUID）
        getDevice(deviceId: deviceId) { device in
            guard let device = device, let uuid = device.uuid else {
                result(false)
                return
            }

            // 使用 deviceStatueWithUUID 方法查询蓝牙是否本地连接
            let isBleOnline = bleManager.deviceStatue(withUUID: uuid)

            // 如果是双模设备，需要结合 ThingSmartDeviceModel 的 isOnline 判断
            if device.isOnline {
                // 设备在线（可能是蓝牙或Wi-Fi）
                // 如果 isBleOnline 为 true，说明是蓝牙在线
                // 如果 isBleOnline 为 false，说明是 Wi-Fi 在线
                result(isBleOnline)
            } else {
                // 设备完全离线
                result(false)
            }
        }
    }

    private func handleCheckDevicesOnline(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceIds = args["deviceIds"] as? [String]
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "deviceIds is required", details: nil))
            return
        }

        print("🔍 批量检查设备在线状态: \(deviceIds)")

        guard let bleManager = bleManager else {
            result([String: Bool]())
            return
        }

        var onlineStatusMap: [String: Bool] = [:]
        let group = DispatchGroup()

        for deviceId in deviceIds {
            group.enter()
            getDevice(deviceId: deviceId) { device in
                if let device = device, let uuid = device.uuid {
                    let isBleOnline = bleManager.deviceStatue(withUUID: uuid)
                    onlineStatusMap[deviceId] = device.isOnline ? isBleOnline : false
                    print("  设备 \(deviceId) 在线状态: \(onlineStatusMap[deviceId] ?? false)")
                } else {
                    onlineStatusMap[deviceId] = false
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            result(onlineStatusMap)
        }
    }

    private func handleConnectBleDevices(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceIds = args["deviceIds"] as? [String]
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "deviceIds is required", details: nil))
            return
        }

        print("🔗 批量连接设备: \(deviceIds)")

        guard let bleManager = bleManager else {
            result(FlutterError(code: "SDK_ERROR", message: "BLE manager not available", details: nil))
            return
        }

        var connectionResults: [String: Bool] = [:]
        let group = DispatchGroup()

        for deviceId in deviceIds {
            group.enter()
            updateConnectionState(deviceId: deviceId, state: "connecting")

            getDevice(deviceId: deviceId) { [weak self] device in
                guard let self = self,
                      let device = device,
                      let uuid = device.uuid,
                      let productKey = device.productId
                else {
                    connectionResults[deviceId] = false
                    self?.updateConnectionState(deviceId: deviceId, state: "disconnected")
                    group.leave()
                    return
                }

                let delegateDevId = device.devId ?? deviceId
                bleManager.connectBLE(withUUID: uuid, productKey: productKey, success: {
                    print("✅ 设备连接成功: \(deviceId)")
                    self.updateConnectionState(deviceId: deviceId, state: "connected")
                    self.setupDeviceDelegate(deviceId: delegateDevId)
                    connectionResults[deviceId] = true
                    group.leave()
                }, failure: {
                    print("❌ 设备连接失败: \(deviceId)")
                    self.updateConnectionState(deviceId: deviceId, state: "disconnected")
                    connectionResults[deviceId] = false
                    group.leave()
                })
            }
        }

        group.notify(queue: .main) {
            result(connectionResults)
        }
    }

    private func handleRemoveDevice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let devId = args["devId"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "devId is required", details: nil))
            return
        }

        print("🗑️ 开始移除设备: \(devId)")

        guard let device = ThingSmartDevice(deviceId: devId) else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found", details: nil))
            return
        }

        device.remove({
            print("✅ 设备移除成功: \(devId)")
            result(nil)
        }, failure: { error in
            let errorMsg = error?.localizedDescription ?? "Unknown error"
            print("❌ 移除设备失败: \(errorMsg)")
            result(FlutterError(code: "REMOVE_FAILED", message: errorMsg, details: [
                "errorMsg": errorMsg
            ]))
        })
    }

    private func handleRegisterDeviceListener(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "deviceId is required", details: nil))
            return
        }

        print("📝 Flutter 请求注册设备监听器: deviceId=\(deviceId)")

        // 检查设备是否在线
        guard let bleManager = bleManager else {
            result(FlutterError(code: "SDK_ERROR", message: "BLE manager not available", details: nil))
            return
        }

        // 从 home 的设备列表中通过 uuid (bluetoothId) 查找对应的设备
        // Flutter 端传入的 deviceId 实际上是 bluetoothId (uuid)
        getDeviceByUuid(uuid: deviceId) { [weak self] deviceModel in
            guard let self = self else {
                result(FlutterError(code: "INTERNAL_ERROR", message: "Self is nil", details: nil))
                return
            }

            guard let device = deviceModel,
                  let uuid = device.uuid,
                  let devId = device.devId
            else {
                print("⚠️ 未找到设备信息: deviceId=\(deviceId)")
                result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found", details: nil))
                return
            }

            // 检查设备是否在线（本地BLE连接）
            let isBleOnline = bleManager.deviceStatue(withUUID: uuid)
            if !device.isOnline || !isBleOnline {
                print("⚠️ 设备未在线，无法注册监听器: deviceId=\(deviceId), devId=\(devId), isOnline=\(device.isOnline), isBleOnline=\(isBleOnline)")
                result(FlutterError(code: "DEVICE_OFFLINE", message: "Device is not online", details: nil))
                return
            }

            // 注册监听器（使用 devId）
            self.setupDeviceDelegate(deviceId: devId)
            print("✅ 设备监听器注册成功: deviceId=\(deviceId), devId=\(devId)")
            result(nil)
        }
    }

    // MARK: - DP Handlers
    private func handlePublishDps(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              let dpsArray = args["dps"] as? [[String: Any]]
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "deviceId and dps are required", details: nil))
            return
        }

        let timeout = (args["timeout"] as? Int) ?? 10

        let timestamp = Date().toISO8601String()
        print("📤 下发DP前带时间: \(deviceId), DPs: \(dpsArray.count), 超时: \(timeout)秒, timestamp: \(timestamp)")

        // 构建DP字典，确保数据类型正确
        // 根据Tuya文档：
        // - 数值型（value）：发送数字，如 {"2": 25}
        // - 布尔型（bool）：发送布尔值
        // - 枚举型（enum）：发送字符串或数字
        // - 透传型（raw）：发送16进制字符串，必须是偶数位，如 {"1": "011f"}
        var dps: [String: Any] = [:]
        for dpDict in dpsArray {
            if let dpId = dpDict["dpId"] as? String,
               let rawValue = dpDict["value"] {
                // 确保数据类型正确
                // let formattedValue = formatDpValue(dpId: dpId, value: rawValue)
                dps[dpId] = rawValue
                print("  DP[\(dpId)] = \(rawValue) (type: \(type(of: rawValue)))")
            }
        }

        // 根据Tuya SDK文档，使用 ThingSmartDevice 的 publishDps 方法
        // 支持自动选择通道、局域网控制和云端控制
        guard let device = ThingSmartDevice(deviceId: deviceId) else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found or cannot create device instance", details: nil))
            return
        }

        // 发送DP数据，使用自动模式
        // 根据头文件定义，ThingDevicePublishMode 枚举包含：
        // - ThingDevicePublishModeLocal (0) -> .local
        // - ThingDevicePublishModeInternet (1) -> .internet
        // - ThingDevicePublishModeAuto (2) -> .auto
        // 如果 .auto 编译错误，可能是 Xcode 缓存问题，尝试清理构建缓存
        // 当前使用原始值 2 来确保兼容性
        device.publishDps(dps, mode: ThingDevicePublishModeAuto, success: {
            // 加上时间
            let timestamp = Date().toISO8601String()
            print("✅ DP下发成功后带时间 [\(timestamp)] devId=\(deviceId) DPs=\(dps.keys.joined(separator: ", "))")
            result(true)
        }, failure: { error in
            let errorMsg = error?.localizedDescription ?? "Unknown error"
            print("❌ DP下发失败: \(deviceId), 错误: \(errorMsg)")
            result(FlutterError(
                code: "PUBLISH_FAILED",
                message: errorMsg,
                details: [
                    "deviceId": deviceId,
                    "dps": dps
                ]
            ))
        })
    }

    private func handleGetDp(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              let dpId = args["dpId"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "deviceId and dpId are required", details: nil))
            return
        }

        print("📥 获取DP: deviceId=\(deviceId), dpId=\(dpId)")

        // 方法1: 优先从 ThingSmartDeviceModel.dps 获取（常规查询方式）
        getDevice(deviceId: deviceId) { [weak self] deviceModel in
            guard let self = self else {
                result(FlutterError(code: "INTERNAL_ERROR", message: "Self is nil", details: nil))
                return
            }
            
            // 如果设备模型存在且有 dps 数据，直接返回
            if let deviceModel = deviceModel,
               let dps = deviceModel.dps as? [String: Any],
               let dpValue = dps[dpId] {
                print("✅ 从设备模型成功获取 DP[\(dpId)] = \(dpValue) (类型: \(type(of: dpValue)))")
                result([
                    "dpId": dpId,
                    "value": dpValue
                ])
                return
            }
            
            // 方法2: 如果设备模型中没有，使用 publishDps 查询（针对不主动发送数据的设备 DP）
            print("⚠️ 设备模型中未找到 DP[\(dpId)]，使用 publishDps 查询")
            self.queryDpWithPublishDps(deviceId: deviceId, dpId: dpId, result: result)
        }
    }

    private func queryDpWithPublishDps(deviceId: String, dpId: String, result: @escaping FlutterResult) {
        // 获取设备实例
        guard let device = ThingSmartDevice(deviceId: deviceId) else {
            print("❌ 获取设备实例失败: \(deviceId)")
            result(FlutterError(
                code: "DEVICE_NOT_FOUND",
                message: "Device not found or cannot create device instance",
                details: nil
            ))
            return
        }

        // 使用 publishDps 查询单个 DP，传入 NSNull() 作为值
        // 查询后会通过代理 device:dpsUpdate: 回调数据
        let queryDpInfo = [dpId: NSNull()]
        
        device.publishDps(queryDpInfo, mode: ThingDevicePublishModeAuto, success: {
            print("✅ publishDps 查询成功")
            // 注意：查询后会通过代理方法 device:dpsUpdate: 回调数据
            // 但由于 Flutter MethodChannel 需要同步返回，我们等待一小段时间后
            // 再次从设备模型获取（代理回调会更新设备模型的 dps）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 再次从设备模型获取，因为代理回调会更新设备模型的 dps
                self.getDevice(deviceId: deviceId) { deviceModel in
                    if let deviceModel = deviceModel,
                       let dps = deviceModel.dps as? [String: Any],
                       let dpValue = dps[dpId] {
                        print("✅ 从查询后的设备模型成功获取 DP[\(dpId)] = \(dpValue) (类型: \(type(of: dpValue)))")
                        result([
                            "dpId": dpId,
                            "value": dpValue
                        ])
                    } else {
                        print("⚠️ 查询后仍未找到 DP[\(dpId)]")
                        result(FlutterError(
                            code: "DP_NOT_FOUND",
                            message: "DP not found after query",
                            details: [
                                "deviceId": deviceId,
                                "dpId": dpId
                            ]
                        ))
                    }
                }
            }
        }, failure: { error in
            let errorMsg = error?.localizedDescription ?? "Unknown error"
            print("❌ publishDps 查询失败: \(errorMsg)")
            result(FlutterError(
                code: "QUERY_DP_FAILED",
                message: "Failed to query DP: \(errorMsg)",
                details: [
                    "deviceId": deviceId,
                    "dpId": dpId,
                    "error": errorMsg
                ]
            ))
        })
    }

    // MARK: - DP Value Formatting
    /// 格式化DP值，确保数据类型正确
    /// 根据DP ID和值类型进行格式化
    private func formatDpValue(dpId: String, value: Any) -> Any {
        // 根据实际DP定义进行格式化
        // DP 101: session_setting (透传型) - 16进制字符串，偶数位
        if dpId == "101" {
            if let str = value as? String {
                var hexString = str.uppercased()
                // 如果是奇数位，前面补0
                if hexString.count % 2 != 0 {
                    hexString = "0" + hexString
                }
                return hexString
            }
            return "00"
        }

        // DP 102, 103, 107, 109, 112, 113: 布尔型
        if ["102", "103", "107", "109", "112", "113"].contains(dpId) {
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let intValue = value as? Int {
                return intValue != 0
            }
            if let str = value as? String {
                return str.lowercased() == "true" || str == "1"
            }
            return false
        }

        // DP 104: battery_level (枚举型, 1, 2, 3)
        if dpId == "104" {
            if let intValue = value as? Int {
                return (intValue >= 1 && intValue <= 3) ? intValue : 1
            }
            if let str = value as? String, let intValue = Int(str) {
                return (intValue >= 1 && intValue <= 3) ? intValue : 1
            }
            return 1
        }

        // DP 105: session_status (透传型) - 只上报，不需要格式化
        if dpId == "105" {
            if let str = value as? String {
                var hexString = str.uppercased()
                if hexString.count % 2 != 0 {
                    hexString = "0" + hexString
                }
                return hexString
            }
            return "00"
        }

        // DP 106, 108: 数值型 (0-9)
        if dpId == "106" || dpId == "108" {
            if let intValue = value as? Int {
                return max(0, min(9, intValue))
            }
            if let doubleValue = value as? Double {
                return max(0, min(9, Int(doubleValue)))
            }
            if let str = value as? String, let intValue = Int(str) {
                return max(0, min(9, intValue))
            }
            return 0
        }

        // DP 110: light_stay_duration (枚举型, 10, 20, 30)
        if dpId == "110" {
            if let intValue = value as? Int {
                if intValue == 10 || intValue == 20 || intValue == 30 {
                    return intValue
                }
                return 10
            }
            if let str = value as? String, let intValue = Int(str) {
                if intValue == 10 || intValue == 20 || intValue == 30 {
                    return intValue
                }
                return 10
            }
            return 10
        }

        // DP 111: device_symbol (枚举型, "left", "right")
        if dpId == "111" {
            if let str = value as? String {
                let lowerStr = str.lowercased()
                return (lowerStr == "left" || lowerStr == "right") ? lowerStr : "left"
            }
            return "left"
        }

        // 默认：保持原值
        return value
    }

    // MARK: - Helper Methods
    /// 获取家庭列表（返回所有家庭）
    /// - Parameter completion: 完成回调，返回家庭列表数组
    func getHomeList(completion: @escaping ([ThingSmartHomeModel]?) -> Void) {
        // 如果 homeManager 未初始化，创建新实例
        let manager = homeManager ?? ThingSmartHomeManager()

        manager.getHomeList(success: { homes in
            print("✅ 获取家庭列表成功: \(homes?.count ?? 0) 个家庭")
            completion(homes)
        }, failure: { error in
            if let e = error {
                print("❌ 获取家庭列表失败: \(e.localizedDescription)")
            } else {
                print("❌ 获取家庭列表失败: unknown error")
            }
            completion(nil)
        })
    }

    /// 获取第一个家庭（向后兼容的便捷方法）
    /// - Parameter completion: 完成回调，返回第一个家庭模型
    private func getFirstHome(completion: @escaping (ThingSmartHomeModel?) -> Void) {
        getHomeList { homes in
            completion(homes?.first)
        }
    }

    /// 获取当前家庭的数据信息（包括设备列表）
    /// 在配网连接成功后调用，用于刷新设备列表
    // private func getHomeDataInfo() {
    //     getFirstHome { [weak self] homeModel in
    //         guard let self = self, let homeModel = homeModel else {
    //             print("⚠️ 未找到家庭，无法获取设备列表")
    //             return
    //         }
    //
    //         let homeId = homeModel.homeId
    //         // 确保使用 self.home 实例，而不是创建新的实例
    //         // 这样可以保持 delegate 设置
    //         self.ensureHomeDelegate(homeId: homeId)
    //
    //         guard let home = self.home else {
    //             print("❌ 无法获取家庭实例: \(homeId)")
    //             return
    //         }
    //
    //         home.getDataWithSuccess({ [weak self] homeModel in
    //             print("✅ 获取家庭数据成功")
    //             guard let self = self else { return }
    //
    //             if let deviceList = home.deviceList {
    //                 print("📱 当前家庭设备列表: \(deviceList.count) 个设备")
    //                 for device in deviceList {
    //                     let devId = device.devId ?? "unknown"
    //                     let uuid = device.uuid ?? "unknown"
    //                     let deviceName = device.name ?? "unknown"
    //
    //                     print("  - 设备ID: \(devId), 名称: \(deviceName), 在线: \(device.isOnline), uuid: \(uuid)")
    //
    //                     // 发送设备激活事件到 Flutter 端，用于更新 available device 的 devId
    //                     // deviceId 对应 bluetoothId (即 uuid)，devId 对应设备的 devId
    //                     if uuid != "unknown" && devId != "unknown" {
    //                         let eventData: [String: Any] = [
    //                             "type": "deviceActivated",
    //                             "deviceId": uuid,
    //                             "devId": devId
    //                         ]
    //
    //                         do {
    //                             let jsonData = try JSONSerialization.data(withJSONObject: eventData)
    //                             let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
    //                             self.connectionEventSink?(jsonString)
    //                             print("📤 已发送设备激活事件: uuid=\(uuid), devId=\(devId)")
    //                         } catch {
    //                             print("❌ 编码设备激活事件失败: \(error)")
    //                         }
    //                     }
    //                 }
    //             } else {
    //                 print("⚠️ 设备列表为空")
    //             }
    //         }, failure: { error in
    //             if let e = error {
    //                 print("❌ 获取家庭数据失败: \(e.localizedDescription)")
    //             } else {
    //                 print("❌ 获取家庭数据失败: unknown error")
    //             }
    //         })
    //     }
    // }

    private func getDevicesFromHome(_ homeModel: ThingSmartHomeModel, completion: @escaping ([ThingSmartDeviceModel]?) -> Void) {
        let homeId = homeModel.homeId
        // 确保使用 self.home 实例，保持 delegate 设置
        ensureHomeDelegate(homeId: homeId)
        
        guard let home = self.home else {
            completion(nil)
            return
        }

        home.getDetailWithSuccess({ _ in
                                      completion(home.deviceList)
                                  }, failure: { error in
            print("❌ Failed to get home details: \(error?.localizedDescription ?? "unknown")")
            completion(nil)
        })
    }

    private func getDevice(deviceId: String, completion: @escaping (ThingSmartDeviceModel?) -> Void) {
        getFirstHome { [weak self] homeModel in
            guard let self = self, let homeModel = homeModel else {
                completion(nil)
                return
            }

            self.getDevicesFromHome(homeModel) { devices in
                // deviceId may be a Tuya devId or a bluetooth uuid (bluetoothId in Flutter).
                // Prefer devId match, then fallback to uuid match.
                let device =
                    devices?.first(where: { $0.devId == deviceId }) ??
                    devices?.first(where: { $0.uuid == deviceId })
                completion(device)
            }
        }
    }

    /// 通过 bluetoothId (uuid) 查找设备
    private func getDeviceByUuid(uuid: String, completion: @escaping (ThingSmartDeviceModel?) -> Void) {
        getFirstHome { [weak self] homeModel in
            guard let self = self, let homeModel = homeModel else {
                completion(nil)
                return
            }

            self.getDevicesFromHome(homeModel) { devices in
                let device = devices?.first(where: { $0.uuid == uuid })
                completion(device)
            }
        }
    }

    private func updateConnectionState(deviceId: String, state: String, error: String? = nil) {
        deviceConnectionStates[deviceId] = state

        let eventData: [String: Any] = [
            "deviceId": deviceId,
            "state": state,
            "error": error ?? NSNull()
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: eventData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            connectionEventSink?(jsonString)
        } catch {
            print("Error encoding connection event: \(error)")
        }
    }

    // 处理DP上报
    func handleDpReport(deviceId: String, dps: [String: Any]) {
        print("📥 收到DP上报: \(deviceId), DPs: \(dps.keys.joined(separator: ", "))")
        for (dpId, value) in dps {
            print("  DP[\(dpId)] 类型: \(type(of: value)), 值: \(value)")
        }

        var dpArray: [[String: Any]] = []
        for (dpId, value) in dps {
            // 处理 DP 105 (sessionStatus): iOS SDK 可能返回 Data 类型，需要转换为十六进制字符串
            var processedValue: Any = value
            if dpId == "105" {
                if let data = value as? Data {
                    // 将 Data 转换为十六进制字符串
                    processedValue = data.map { String(format: "%02x", $0) }.joined().uppercased()
                    print("📥 DP 105 值类型为 Data，已转换为十六进制字符串: \(processedValue)")
                } else if let str = value as? String {
                    // 如果已经是字符串，确保是大写
                    processedValue = str.uppercased()
                } else {
                    print("⚠️ DP 105 值类型未知: \(type(of: value)), 值: \(value)")
                    processedValue = String(describing: value)
                }
            }
            
            dpArray.append([
                               "dpId": dpId,
                               "value": processedValue,
                               "timestamp": Int(Date().timeIntervalSince1970)
                           ])
        }

        let eventData: [String: Any] = [
            "type": "report",
            "data": [
                "deviceId": deviceId,
                "dps": dpArray,
                "timestamp": Int(Date().timeIntervalSince1970)
            ]
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: eventData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            dpEventSink?(jsonString)
        } catch {
            print("Error encoding DP report event: \(error)")
        }
    }
    
    /// 根据 devId 获取对应的 bluetooth_id (uuid)
    /// 因为数据库中使用的是 bluetooth_id，而 delegate 回调中使用的是 devId
    private func getBluetoothIdFromDevId(_ devId: String, completion: @escaping (String?) -> Void) {
        // 首先尝试从 home 的设备列表中查找
        if let deviceList = home?.deviceList {
            if let device = deviceList.first(where: { $0.devId == devId }) {
                completion(device.uuid)
                return
            }
        }
        
        // 如果 home 中没有，尝试从数据库查询（通过 Flutter 端）
        // 这里我们使用 devId 作为 deviceId 返回，因为 Flutter 端可能会处理映射
        // 但更好的方式是先尝试从 home 获取
        getFirstHome { [weak self] homeModel in
            guard let self = self, let homeModel = homeModel else {
                completion(devId) // 如果找不到，返回 devId 作为 fallback
                return
            }
            
            self.getDevicesFromHome(homeModel) { devices in
                if let device = devices?.first(where: { $0.devId == devId }) {
                    completion(device.uuid)
                } else {
                    completion(devId) // 如果找不到，返回 devId 作为 fallback
                }
            }
        }
    }
}

// MARK: - Device DP Delegate
/// 设备DP更新代理类
class DeviceDpDelegate: NSObject, ThingSmartDeviceDelegate {
    let deviceId: String
    let onDpUpdate: (String, [String: Any]) -> Void

    init(deviceId: String, onDpUpdate: @escaping (String, [String: Any]) -> Void) {
        self.deviceId = deviceId
        self.onDpUpdate = onDpUpdate
        super.init()
    }

    // 设备DP更新回调
    func device(_ device: ThingSmartDevice, didUpdateDps dps: [String: Any]) {
        print("📥 设备DP更新 (delegate): \(deviceId)")
        onDpUpdate(deviceId, dps)
    }

    // 设备在线状态变化回调
    func device(_ device: ThingSmartDevice, didUpdateOnlineStatus online: Bool) {
        print("📡 设备在线状态变化: \(deviceId), online: \(online)")
    }
}

// MARK: - Connection Stream Handler
class ConnectionStreamHandler: NSObject, FlutterStreamHandler {
    weak var delegate: AppDelegate?

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        delegate?.connectionEventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        delegate?.connectionEventSink = nil
        return nil
    }
}

// MARK: - DP Stream Handler
class DpStreamHandler: NSObject, FlutterStreamHandler {
    weak var delegate: AppDelegate?

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        delegate?.dpEventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        delegate?.dpEventSink = nil
        return nil
    }
}

// MARK: - FlutterStreamHandler
extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        stopBleScan()
        return nil
    }
}

// MARK: - ThingSmartBLEManagerDelegate
extension AppDelegate: ThingSmartBLEManagerDelegate {
    // 扫描到设备时的回调
    func didDiscoveryDevice(withDeviceInfo deviceInfo: ThingBLEAdvModel) {
        // 在主线程发送扫描结果
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }

            // 从advModel获取设备信息
            let advModel = deviceInfo
            let peripheral = advModel.peripheral

            // 保存设备信息到映射表（用于后续配网）
            if let uuid = advModel.uuid {
                self.scannedDevices[uuid] = deviceInfo
            }

            // 从CBPeripheral获取设备名称
            let deviceName = peripheral?.cbPeripheral?.name ?? ""

            // 处理 bleType（枚举类型，获取原始值）
            let bleTypeRawValue = advModel.bleType.rawValue

            var isOnline: Bool = ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: advModel.uuid ?? "")

            let deviceData: [String: Any] = [
                "id": advModel.uuid ?? "",
                "name": deviceName,
                "uuid": advModel.uuid ?? "",
                "devId": advModel.uuid ?? "",
                "providerName": advModel.productId ?? "",
                "rssi": peripheral?.rssi ?? 0,
                "bleType": bleTypeRawValue,
                "isActive": advModel.isActive,
                "isProuductKey": advModel.isProuductKey,
                "productId": advModel.productId ?? "",
                "isOnline": isOnline
            ]

            print("🔍 deviceData: \(deviceData)")

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: deviceData)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                self.eventSink?(jsonString)
            } catch {
                print("Error encoding device info: \(error)")
            }
        }
    }

    // 蓝牙状态变化通知
    func bluetoothDidUpdateState(_ isPoweredOn: Bool) {
        print("🔵 蓝牙状态变化: \(isPoweredOn ? "开启" : "关闭")")
    }
}

// MARK: - ThingSmartHomeDelegate
extension AppDelegate: ThingSmartHomeDelegate {
    /// 设备信息更新回调，例如设备名称、在线状态等
    /// - Parameters:
    ///   - home: 家庭实例
    ///   - device: 设备模型
    func home(_ home: ThingSmartHome!, deviceInfoUpdate device: ThingSmartDeviceModel!) {
        guard let device = device else {
            return
        }
        
        let devId = device.devId ?? "unknown"
        let uuid = device.uuid ?? "unknown"
        let deviceName = device.name ?? "unknown"
        let isOnline = device.isOnline
        
        // 打印设备信息以便调试
        print("📱 设备信息更新 - devId: \(devId), uuid: \(uuid), 名称: \(deviceName), 在线: \(isOnline)")
        
        // 打印设备的所有属性以便调试（用户建议）
        print("📱 设备属性详情:")
        print("  - devId: \(devId)")
        print("  - uuid: \(uuid)")
        print("  - name: \(deviceName)")
        print("  - isOnline: \(isOnline)")
        print("  - productId: \(device.productId ?? "unknown")")
        print("  - iconUrl: \(device.iconUrl ?? "unknown")")
        print("  - isLocalOnline: \(device.isLocalOnline)")
        print("  - isCloudOnline: \(device.isCloudOnline)")
        
        // 使用 uuid (bluetooth_id) 作为 deviceId 来更新连接状态
        // 因为数据库中使用的是 bluetooth_id
        if uuid != "unknown" {
            let state = isOnline ? "connected" : "disconnected"
            updateConnectionState(deviceId: devId, state: state)
            
            // 发送 networkStatusChanged 事件（与 Android 端保持一致）
            // Flutter 端通过这个事件来更新数据库中的设备状态
            let networkEventData: [String: Any] = [
                "devId": devId,
                "type": "networkStatusChanged",
                "status": isOnline
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: networkEventData)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                connectionEventSink?(jsonString)
                print("📤 已发送网络状态变化事件: devId=\(devId), status=\(isOnline)")
            } catch {
                print("❌ 编码网络状态变化事件失败: \(error)")
            }
            
            // 如果设备离线，尝试重连（如果需要）
            if !isOnline {
                // 检查是否需要重连（可以根据业务需求决定）
                // 这里先不自动重连，由 Flutter 端控制
                print("⚠️ 设备离线: \(uuid)，可以考虑重连")
            }
        }
    }
    
    /// 家庭下设备的 DPS 变化代理回调
    /// - Parameters:
    ///   - home: 家庭实例
    ///   - device: 设备模型
    ///   - dps: DPS 数据字典，格式如 ["101": true, "102": false]
    func home(_ home: ThingSmartHome!, device: ThingSmartDeviceModel!, dpsUpdate dps: [AnyHashable : Any]!) {
        guard let device = device, let dps = dps as? [String: Any] else {
            print("⚠️ DPS 更新回调参数无效")
            return
        }
        
        let devId = device.devId ?? "unknown"
        let uuid = device.uuid ?? "unknown"
        
        
        // 打印每个 DP 的详细信息
        for (dpId, value) in dps {
            if dpId == "105" {
                // 记录人类可读时间（尽量含毫秒），避免使用纯时间戳
                let timestamp = Date().toISO8601String()
                let dpKeys = dps.keys.sorted().joined(separator: ", ")
                print("📊 DPS上报带时间 [\(timestamp)] devId=\(devId) uuid=\(uuid) DPs=\(dpKeys)")
            }
        }

        // print("⚠️ 设备 uuid 未知，使用 devId: \(devId)")
        handleDpReport(deviceId: devId, dps: dps)
    }
}
