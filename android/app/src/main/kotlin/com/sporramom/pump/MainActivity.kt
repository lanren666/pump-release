package com.sporramom.pump

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.android.ble.api.LeScanSetting
import com.thingclips.smart.android.ble.api.ScanDeviceBean
import com.thingclips.smart.android.ble.api.ScanType
import com.thingclips.smart.android.ble.api.BleScanResponse
import com.thingclips.smart.android.user.api.IRegisterCallback
import com.thingclips.smart.android.user.bean.User
import com.thingclips.smart.home.sdk.bean.HomeBean
import com.thingclips.smart.home.sdk.callback.IThingGetHomeListCallback
import com.thingclips.smart.home.sdk.callback.IThingHomeResultCallback
import com.thingclips.smart.sdk.api.IBleActivatorListener
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.bean.BleActivatorBean
import com.thingclips.smart.android.ble.builder.BleConnectBuilder
import com.thingclips.smart.sdk.api.IThingDevice
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IDevListener
import com.alibaba.fastjson.JSON
import io.flutter.plugin.common.MethodCall
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

class MainActivity : FlutterActivity(), LocationListener {
    private val CHANNEL = "com.sporramom/ble_scan"
    private val EVENT_CHANNEL = "com.sporramom/ble_scan_events"
    private val CONNECTION_CHANNEL = "com.sporramom/ble_connection"
    private val CONNECTION_EVENT_CHANNEL = "com.sporramom/ble_connection_events"
    private val DP_CHANNEL = "com.sporramom/ble_dp"
    private val DP_EVENT_CHANNEL = "com.sporramom/ble_dp_events"

    private var eventSink: EventChannel.EventSink? = null
    private var connectionEventSink: EventChannel.EventSink? = null
    private var dpEventSink: EventChannel.EventSink? = null
    private var isScanning = false
    private val PERMISSION_REQUEST_CODE = 1001
    private val LOCATION_PERMISSION_REQUEST_CODE = 1002
    private val mainHandler = Handler(Looper.getMainLooper())

    // 位置信息
    private var currentLatitude: Double = 0.0
    private var currentLongitude: Double = 0.0
    private var countryCode: String = "1" // 默认美国
    private var locationManager: LocationManager? = null

    // 设备连接状态管理
    private val deviceConnectionStates = mutableMapOf<String, String>() // deviceId -> state
    private val scannedDevices = mutableMapOf<String, ScanDeviceBean>() // uuid -> ScanDeviceBean

    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.BLUETOOTH_CONNECT
                    ) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.ACCESS_FINE_LOCATION
                    ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                    ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasLocationPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestBluetoothPermissions() {
        android.util.Log.d("MainActivity", "Requesting permissions, SDK: ${Build.VERSION.SDK_INT}")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val permissions = arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
            android.util.Log.d(
                "MainActivity",
                "Requesting Android 12+ permissions: ${permissions.joinToString()}"
            )
            ActivityCompat.requestPermissions(
                this,
                permissions,
                PERMISSION_REQUEST_CODE
            )
        } else {
            val permissions = arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
            android.util.Log.d(
                "MainActivity",
                "Requesting Android 11- permissions: ${permissions.joinToString()}"
            )
            ActivityCompat.requestPermissions(
                this,
                permissions,
                PERMISSION_REQUEST_CODE
            )
        }
    }

    private fun requestLocationPermissions() {
        val permissions = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        ActivityCompat.requestPermissions(
            this,
            permissions,
            LOCATION_PERMISSION_REQUEST_CODE
        )
    }

    private fun isBluetoothEnabled(): Boolean {
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        return bluetoothAdapter != null && bluetoothAdapter.isEnabled
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 12+ 立即隐藏启动画面
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val splashScreen = installSplashScreen()
            // 立即隐藏启动画面，不等待 Flutter 第一帧
            splashScreen.setKeepOnScreenCondition { false }
        }
        
        super.onCreate(savedInstanceState)
        // 初始化位置管理器
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        
        // 提前申请蓝牙权限，避免在搜索时中断流程
        if (!hasBluetoothPermissions()) {
            android.util.Log.d("MainActivity", "提前申请蓝牙权限...")
            requestBluetoothPermissions()
        }
        
        // 请求位置权限并获取位置信息
        if (hasLocationPermissions()) {
            requestLocation()
        } else {
            requestLocationPermissions()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        android.util.Log.i("MainActivity", "Flutter engine configured")

        // MethodChannel for scan control
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            android.util.Log.d(
                "MainActivity",
                "📞 MethodChannel call received: method=${call.method}"
            )

            when (call.method) {
                "checkSDKInitialized" -> {
                    val isInitialized = try {
                        ThingHomeSdk.getBleOperator() != null
                    } catch (e: Exception) {
                        false
                    }
                    result.success(isInitialized)
                }

                "checkBluetoothEnabled" -> {
                    val isEnabled = isBluetoothEnabled()
                    result.success(isEnabled)
                }

                "openBluetoothSettings" -> {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "❌ 打开蓝牙设置失败: ${e.message}")
                        result.error("OPEN_SETTINGS_FAILED", "Failed to open bluetooth settings: ${e.message}", null)
                    }
                }

                "loginAnonymous" -> {
                    handleLoginAnonymous(call, result)
                }

                "getHomeList" -> {
                    handleGetHomeList(result)
                }

                "addHome" -> {
                    handleAddHome(call, result)
                }

                "startScan" -> {
                    android.util.Log.d("MainActivity", "🔄 Processing startScan request...")
                    if (isScanning) {
                        android.util.Log.d(
                            "MainActivity",
                            "⚠️ Scan already in progress, stopping current scan first..."
                        )
                        stopBleScan()
                        mainHandler.postDelayed({
                            processStartScan(result)
                        }, 200)
                        return@setMethodCallHandler
                    }
                    processStartScan(result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // EventChannel for scan results
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopBleScan()
                }
            }
        )

        // 设置连接相关的MethodChannel和EventChannel
        setupConnectionChannels(flutterEngine)

        // 设置DP相关的MethodChannel和EventChannel
        setupDpChannels(flutterEngine)
    }

    // MARK: - Connection Channels Setup
    private fun setupConnectionChannels(flutterEngine: FlutterEngine) {
        val connectionMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONNECTION_CHANNEL
        )

        android.util.Log.d("MainActivity", "✅ Connection MethodChannel 已创建: $CONNECTION_CHANNEL")

        connectionMethodChannel.setMethodCallHandler { call, result ->
            android.util.Log.d("MainActivity", "📞 收到连接方法调用: ${call.method}")

            when (call.method) {
                "connectDevice" -> {
                    handleConnectDevice(call, result)
                }

                "isDeviceOnline" -> {
                    handleIsDeviceOnline(call, result)
                }

                "checkDevicesOnline" -> {
                    handleCheckDevicesOnline(call, result)
                }

                "connectBleDevices" -> {
                    handleConnectBleDevices(call, result)
                }

                "removeDevice" -> {
                    handleRemoveDevice(call, result)
                }

                "registerDeviceListener" -> {
                    handleRegisterDeviceListener(call, result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        val connectionEventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONNECTION_EVENT_CHANNEL
        )

        android.util.Log.d(
            "MainActivity",
            "✅ Connection EventChannel 已创建: $CONNECTION_EVENT_CHANNEL"
        )

        connectionEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    connectionEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    connectionEventSink = null
                }
            }
        )
    }

    // MARK: - Location Services
    private fun requestLocation() {
        if (!hasLocationPermissions()) {
            android.util.Log.w("MainActivity", "⚠️ 位置权限未授予")
            return
        }

        locationManager?.let { manager ->
            try {
                // 检查GPS是否可用
                val isGpsEnabled = manager.isProviderEnabled(LocationManager.GPS_PROVIDER)
                val isNetworkEnabled = manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)

                if (isGpsEnabled || isNetworkEnabled) {
                    android.util.Log.d("MainActivity", "📍 开始获取位置...")
                    if (isGpsEnabled) {
                        manager.requestLocationUpdates(
                            LocationManager.GPS_PROVIDER,
                            0L,
                            0f,
                            this
                        )
                    } else if (isNetworkEnabled) {
                        manager.requestLocationUpdates(
                            LocationManager.NETWORK_PROVIDER,
                            0L,
                            0f,
                            this
                        )
                    }
                } else {
                    android.util.Log.w("MainActivity", "⚠️ GPS和网络定位都未启用")
                }
            } catch (e: SecurityException) {
                android.util.Log.e("MainActivity", "❌ 获取位置失败: ${e.message}")
            }
        }
    }

    override fun onLocationChanged(location: Location) {
        currentLatitude = location.latitude
        currentLongitude = location.longitude

        android.util.Log.d(
            "MainActivity",
            "📍 获取到位置: lat=$currentLatitude, lon=$currentLongitude"
        )

        // 停止位置更新以节省电量
        locationManager?.removeUpdates(this)

        // 获取国家代码
        getCountryCode(location)
    }

    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {}
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun getCountryCode(location: Location) {
        try {
            val geocoder = Geocoder(this, Locale.getDefault())
            val addresses = geocoder.getFromLocation(location.latitude, location.longitude, 1)

            if (addresses != null && addresses.isNotEmpty()) {
                val countryCodeIso = addresses[0].countryCode
                if (countryCodeIso != null) {
                    countryCode = getPhoneCountryCode(countryCodeIso)
                    android.util.Log.d(
                        "MainActivity",
                        "✅ 获取到国家代码: ISO=$countryCodeIso, Phone=$countryCode"
                    )
                } else {
                    android.util.Log.w("MainActivity", "⚠️ 未找到国家代码")
                    countryCode = "1"
                }
            } else {
                android.util.Log.w("MainActivity", "⚠️ 未找到位置信息")
                countryCode = "1"
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ 反向地理编码失败: ${e.message}")
            countryCode = "1"
        }
    }

    private fun getPhoneCountryCode(isoCode: String): String {
        // 简化的国家代码映射（常用国家）
        val countryCodeMap = mapOf(
            "US" to "1",      // 美国
            "CN" to "86",     // 中国
            "GB" to "44",     // 英国
            "JP" to "81",     // 日本
            "KR" to "82",     // 韩国
            "DE" to "49",     // 德国
            "FR" to "33",     // 法国
            "IT" to "39",     // 意大利
            "ES" to "34",     // 西班牙
            "CA" to "1",      // 加拿大
            "AU" to "61",     // 澳大利亚
            "IN" to "91",     // 印度
            "BR" to "55",     // 巴西
            "MX" to "52",     // 墨西哥
            "RU" to "7"       // 俄罗斯
        )

        return countryCodeMap[isoCode.uppercase()] ?: "1" // 默认返回美国
    }

    // MARK: - Login Handlers
    private fun handleLoginAnonymous(call: MethodCall, result: MethodChannel.Result) {
        android.util.Log.d("MainActivity", "🔐 开始匿名登录...")

        // 确保在主线程执行，并且 Context 可用
        if (applicationContext == null) {
            android.util.Log.e("MainActivity", "❌ Application Context 不可用")
            result.error("ANONYMOUS_LOGIN_FAILED", "Application context not available", null)
            return
        }

        // 确保 SDK 已初始化
        try {
            val bleOperator = ThingHomeSdk.getBleOperator()
            if (bleOperator == null) {
                android.util.Log.e("MainActivity", "❌ SDK 未初始化，BLE Operator 为空")
                result.error("ANONYMOUS_LOGIN_FAILED", "SDK not initialized", null)
                return
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ SDK 初始化检查失败: ${e.message}")
            result.error(
                "ANONYMOUS_LOGIN_FAILED",
                "SDK initialization check failed: ${e.message}",
                null
            )
            return
        }

        // 获取参数，如果没有则使用默认值
        val args = call.arguments as? Map<*, *>
        val countryCodeParam = args?.get("countryCode") as? String ?: countryCode
        val userName = args?.get("userName") as? String ?: Build.MODEL // 设备名称

        android.util.Log.d("MainActivity", "🔐 使用国家代码: $countryCodeParam, 用户名: $userName")

        // 在主线程执行，确保 Context 可用
        mainHandler.post {
            try {
                // 获取用户实例
                val userInstance = try {
                    ThingHomeSdk.getUserInstance()
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ 获取用户实例失败: ${e.message}")
                    e.printStackTrace()
                    result.error(
                        "ANONYMOUS_LOGIN_FAILED",
                        "Failed to get user instance: ${e.message}",
                        null
                    )
                    return@post
                }

                if (userInstance == null) {
                    android.util.Log.e("MainActivity", "❌ 用户实例为空")
                    result.error("ANONYMOUS_LOGIN_FAILED", "User instance is null", null)
                    return@post
                }

                // 检查是否已经登录
                try {
                    if (userInstance.isLogin) {
                        android.util.Log.d("MainActivity", "✅ 用户已经登录，跳过登录步骤")
                        result.success(true)
                        return@post
                    }
                } catch (e: Exception) {
                    android.util.Log.w(
                        "MainActivity",
                        "⚠️ 检查登录状态失败，继续登录流程: ${e.message}"
                    )
                }

                // 执行登录
                try {
                    userInstance.touristRegisterAndLogin(
                        countryCodeParam,
                        userName,
                        object : IRegisterCallback {
                            override fun onSuccess(user: User) {
                                android.util.Log.d("MainActivity", "✅ 匿名登录成功")
                                result.success(true)
                            }

                            override fun onError(code: String, error: String) {
                                android.util.Log.e(
                                    "MainActivity",
                                    "❌ 匿名登录失败: code=$code, error=$error"
                                )
                                result.error("ANONYMOUS_LOGIN_FAILED", error, null)
                            }
                        }
                    )
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ 调用登录方法失败: ${e.message}")
                    e.printStackTrace()
                    result.error("ANONYMOUS_LOGIN_FAILED", "Login call failed: ${e.message}", null)
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "❌ 登录流程异常: ${e.message}")
                e.printStackTrace()
                result.error("ANONYMOUS_LOGIN_FAILED", "Login process failed: ${e.message}", null)
            }
        }
    }

    // MARK: - Home Handlers
    private fun handleGetHomeList(result: MethodChannel.Result) {
        android.util.Log.d("MainActivity", "🏠 获取家庭列表...")

        ThingHomeSdk.getHomeManagerInstance().queryHomeList(
            object : IThingGetHomeListCallback {
                override fun onSuccess(homeBeans: List<HomeBean>) {
                    android.util.Log.d(
                        "MainActivity",
                        "✅ 获取家庭列表成功: ${homeBeans.size} 个家庭"
                    )

                    val homeList = JSONArray()
                    for (home in homeBeans) {
                        val homeDict = JSONObject().apply {
                            put("homeId", home.homeId)
                            put("name", home.name ?: "")
                            put("geoName", home.geoName ?: "")
                            // HomeBean 可能使用不同的属性名，尝试使用反射或默认值
                            try {
                                val latField = home.javaClass.getDeclaredField("latitude")
                                latField.isAccessible = true
                                put("latitude", latField.getDouble(home))
                            } catch (e: Exception) {
                                put("latitude", 0.0)
                            }
                            try {
                                val lonField = home.javaClass.getDeclaredField("longitude")
                                lonField.isAccessible = true
                                put("longitude", lonField.getDouble(home))
                            } catch (e: Exception) {
                                put("longitude", 0.0)
                            }
                        }
                        homeList.put(homeDict)
                        
                        // 测试：获取家庭详情
                        ThingHomeSdk.newHomeInstance(home.homeId).getHomeDetail(object : IThingHomeResultCallback {
                            override fun onSuccess(bean: HomeBean) {
                                android.util.Log.d("MainActivity", "✅ 获取家庭详情成功 - homeId: ${bean.homeId}, name: ${bean.name}")

                                // 打印设备列表
                                try {
                                    val deviceList = bean.deviceList
                                    if (deviceList != null) {
                                        android.util.Log.d("MainActivity", "📱 设备列表数量: ${deviceList.size}")
                                        for ((index, device) in deviceList.withIndex()) {
                                            android.util.Log.d("MainActivity", "  设备[$index]: id=${device.devId}, name=${device.name}, online=${device.isOnline}")
                                        }
                                    } else {
                                        android.util.Log.d("MainActivity", "📱 设备列表为空")
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("MainActivity", "❌ 获取设备列表失败: ${e.message}")
                                    e.printStackTrace()
                                }
                            }

                            override fun onError(errorCode: String, errorMsg: String) {
                                android.util.Log.e("MainActivity", "❌ 获取家庭详情失败 - homeId: ${home.homeId}, code: $errorCode, msg: $errorMsg")
                            }
                        })
                    }

                    result.success(homeList.toString())
                }

                override fun onError(errorCode: String, error: String) {
                    android.util.Log.e(
                        "MainActivity",
                        "❌ 获取家庭列表失败: code=$errorCode, error=$error"
                    )
                    result.error("GET_HOME_LIST_FAILED", error, null)
                }
            }
        )
    }

    private fun handleAddHome(call: MethodCall, result: MethodChannel.Result) {
        android.util.Log.d("MainActivity", "🏠 创建家庭...")

        val args = call.arguments as? Map<*, *>
        val homeName = args?.get("homeName") as? String
            ?: run {
                result.error("INVALID_ARGUMENT", "homeName is required", null)
                return
            }

        val geoName = args?.get("geoName") as? String ?: ""
        val rooms = (args?.get("rooms") as? List<*>)?.map { it.toString() }?.toList()
            ?: listOf("默认房间")
        val latitude = (args?.get("latitude") as? Number)?.toDouble() ?: currentLatitude
        val longitude = (args?.get("longitude") as? Number)?.toDouble() ?: currentLongitude

        android.util.Log.d(
            "MainActivity",
            "🏠 创建家庭: name=$homeName, geoName=$geoName, lat=$latitude, lon=$longitude"
        )

        ThingHomeSdk.getHomeManagerInstance().createHome(
            homeName,
            longitude,
            latitude,
            geoName,
            rooms,
            object : IThingHomeResultCallback {
                override fun onSuccess(bean: HomeBean) {
                    android.util.Log.d("MainActivity", "✅ 创建家庭成功: homeId=${bean.homeId}")
                    result.success(bean.homeId.toString())
                }

                override fun onError(errorCode: String, errorMsg: String) {
                    android.util.Log.e(
                        "MainActivity",
                        "❌ 创建家庭失败: code=$errorCode, error=$errorMsg"
                    )
                    result.error("ADD_HOME_FAILED", errorMsg, null)
                }
            }
        )
    }

    // MARK: - Connection Handlers
    private fun handleConnectDevice(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val deviceId = args?.get("deviceId") as? String
        val uuid = args?.get("uuid") as? String
        val productKey = args?.get("productKey") as? String
        val homeId = (args?.get("homeId") as? Number)?.toLong()

        if (deviceId == null || uuid == null || productKey == null) {
            result.error("INVALID_ARGUMENT", "deviceId, uuid, and productKey are required", null)
            return
        }

        android.util.Log.d(
            "MainActivity",
            "🔗 开始连接设备: $deviceId, uuid: $uuid, productKey: $productKey"
        )

        // 检查设备是否需要配网
        val deviceInfo = scannedDevices[uuid]
        // 尝试检查设备是否已配网（通过反射或默认假设未配网）
        val isActive = try {
            val isActiveField = deviceInfo?.javaClass?.getDeclaredField("isActive")
            isActiveField?.isAccessible = true
            isActiveField?.getBoolean(deviceInfo) ?: false
        } catch (e: Exception) {
            // 如果无法获取 isActive，默认假设需要配网
            false
        }

        if (deviceInfo != null && !isActive) {
            android.util.Log.d("MainActivity", "📱 设备未配网，需要先激活: $uuid")
            // 需要先配网
            activeDevice(deviceInfo, homeId, deviceId, uuid, productKey, result)
        } else {
            android.util.Log.d("MainActivity", "✅ 设备已配网，直接连接: $uuid")
            // 设备已配网，尝试从home的设备列表中查找devId
            val targetHomeId = homeId ?: run {
                // 如果没有传入homeId，尝试从第一个家庭获取
                var foundHomeId: Long? = null
                ThingHomeSdk.getHomeManagerInstance().queryHomeList(
                    object : IThingGetHomeListCallback {
                        override fun onSuccess(homeBeans: List<HomeBean>) {
                            if (homeBeans.isNotEmpty()) {
                                foundHomeId = homeBeans[0].homeId
                            }
                        }
                        override fun onError(errorCode: String, error: String) {
                            android.util.Log.e("MainActivity", "获取家庭列表失败: $error")
                        }
                    }
                )
                foundHomeId
            }
            
            // 尝试从home的设备列表中查找devId
            var foundDevId: String? = null
            if (targetHomeId != null) {
                ThingHomeSdk.newHomeInstance(targetHomeId).getHomeDetail(
                    object : IThingHomeResultCallback {
                        override fun onSuccess(bean: HomeBean) {
                            val deviceList = bean.deviceList
                            if (deviceList != null) {
                                for (device in deviceList) {
                                    // 通过uuid匹配设备
                                    if (device.uuid == uuid) {
                                        foundDevId = device.devId
                                        android.util.Log.d("MainActivity", "从home设备列表找到devId: $foundDevId")
                                        break
                                    }
                                }
                            }
                            // 连接设备（即使没找到devId也尝试连接）
                            connectDeviceDirectly(
                                foundDevId ?: "",
                                deviceId,
                                uuid,
                                productKey,
                                result
                            )
                        }
                        override fun onError(errorCode: String, errorMsg: String) {
                            android.util.Log.e("MainActivity", "获取家庭详情失败: $errorMsg")
                            // 即使获取失败也尝试连接
                            connectDeviceDirectly("", deviceId, uuid, productKey, result)
                        }
                    }
                )
            } else {
                // 没有homeId，直接连接（devId为空）
                connectDeviceDirectly("", deviceId, uuid, productKey, result)
            }
        }
    }

    // 激活设备（配网）
    private fun activeDevice(
        deviceInfo: ScanDeviceBean,
        homeId: Long?,
        deviceId: String,
        uuid: String,
        productKey: String,
        result: MethodChannel.Result
    ) {
        // 获取 homeId，优先使用传入的，否则从第一个家庭获取
        if (homeId != null) {
            performActiveDevice(deviceInfo, homeId, deviceId, uuid, productKey, result)
        } else {
            // 如果没有传入 homeId，尝试从第一个家庭获取
            ThingHomeSdk.getHomeManagerInstance().queryHomeList(
                object : IThingGetHomeListCallback {
                    override fun onSuccess(homeBeans: List<HomeBean>) {
                        if (homeBeans.isNotEmpty()) {
                            val firstHomeId = homeBeans[0].homeId
                            performActiveDevice(
                                deviceInfo,
                                firstHomeId,
                                deviceId,
                                uuid,
                                productKey,
                                result
                            )
                        } else {
                            result.error(
                                "HOME_NOT_FOUND",
                                "Home not found, please create a home first",
                                null
                            )
                        }
                    }

                    override fun onError(errorCode: String, error: String) {
                        result.error("GET_HOME_FAILED", error, null)
                    }
                }
            )
        }
    }

    private fun performActiveDevice(
        deviceInfo: ScanDeviceBean,
        homeId: Long,
        deviceId: String,
        uuid: String,
        productKey: String,
        result: MethodChannel.Result
    ) {
        android.util.Log.d("MainActivity", "📱 开始激活设备: $uuid, homeId: $homeId")
        
        // 配网时立即停止扫描
        try {
            ThingHomeSdk.getBleOperator().stopLeScan()
            android.util.Log.d("MainActivity", "✅ 已停止扫描")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ 停止扫描失败: ${e.message}")
        }
        
        updateConnectionState(deviceId, "activating")

        // 创建 BleActivatorBean`
        val bleActivatorBean = BleActivatorBean(deviceInfo)
        bleActivatorBean.homeId = homeId
        bleActivatorBean.address = deviceInfo.address
        bleActivatorBean.deviceType = deviceInfo.deviceType
        bleActivatorBean.uuid = deviceInfo.uuid
        bleActivatorBean.productId = deviceInfo.productId
        val flag = try {
            deviceInfo.javaClass.getDeclaredField("flag").apply { isAccessible = true }
                .getInt(deviceInfo)
        } catch (e: Exception) {
            0
        }
        bleActivatorBean.isShare = ((flag shr 2) and 0x01) == 1

        ThingHomeSdk.getActivator().newBleActivator().startActivator(
            bleActivatorBean,
            object : IBleActivatorListener {
                override fun onSuccess(deviceBean: DeviceBean) {
                    val devId = deviceBean.getDevId()
                    android.util.Log.d("MainActivity", "✅ 设备激活成功: $deviceId")
                    android.util.Log.d("MainActivity", "devId: $devId")

                    // 通过 EventChannel 发送 devId 到 Flutter 端
                    val eventData = JSONObject().apply {
                        put("deviceId", deviceId)
                        put("devId", devId)
                        put("type", "deviceActivated")
                    }
                    android.util.Log.d("MainActivity", "📤 准备发送设备激活事件: $eventData")
                    mainHandler.post {
                        if (connectionEventSink != null) {
                            android.util.Log.d(
                                "MainActivity",
                                "✅ 发送设备激活事件到 Flutter: $eventData"
                            )
                            connectionEventSink?.success(eventData.toString())
                        } else {
                            android.util.Log.w(
                                "MainActivity",
                                "⚠️ connectionEventSink 为 null，无法发送设备激活事件"
                            )
                        }
                    }

                    // 激活成功后连接设备（连接成功后再注册监听器）
                    connectDeviceDirectly(devId, deviceId, uuid, productKey, result)
                }

                override fun onFailure(code: Int, msg: String, handle: Any?) {
                    val errorMessage = "Device activation failed: $msg"
                    android.util.Log.e("MainActivity", "❌ 设备激活失败: $errorMessage")
                    updateConnectionState(deviceId, "disconnected", errorMessage)
                    result.error(
                        "ACTIVATION_FAILED", msg, mapOf(
                            "deviceId" to deviceId,
                            "uuid" to uuid,
                            "productKey" to productKey
                        )
                    )
                }
            }
        )
    }

    // 注册设备监听器
    private fun registerDeviceListener(devId: String) {
        android.util.Log.d("MainActivity", "📝 注册设备监听器: devId=$devId")
        
        val mDevice: IThingDevice? = ThingHomeSdk.newDeviceInstance(devId)
        
        mDevice?.registerDevListener(object : IDevListener {

            /**
             * DP 数据更新
             * devId 设备 ID
             * dpStr 设备发生变动的功能点，为 JSON 字符串，数据格式：{"101": true}
             */
            override fun onDpUpdate(devId: String, dpStr: String) {
                android.util.Log.d(
                    "MainActivity",
                    "📊 onDpUpdate - devId: $devId, dpStr: $dpStr"
                )

                try {
                    // 解析 dpStr JSON 字符串，格式如 {"101": true}
                    val dpJson = JSONObject(dpStr)
                    val dpsArray = JSONArray()
                    val timestamp = System.currentTimeMillis() / 1000 // 秒级时间戳

                    // 遍历所有 DP 数据点
                    val keys = dpJson.keys()
                    while (keys.hasNext()) {
                        val dpId = keys.next()
                        val dpValue = dpJson.get(dpId)

                        val dpData = JSONObject().apply {
                            put("dpId", dpId)
                            put("value", dpValue)
                            put("timestamp", timestamp)
                        }
                        dpsArray.put(dpData)
                    }

                    // 构建 DpReportData 格式的事件
                    val reportData = JSONObject().apply {
                        put("deviceId", devId)
                        put("dps", dpsArray)
                        put("timestamp", timestamp)
                    }

                    // 构建完整的事件格式
                    val eventData = JSONObject().apply {
                        put("type", "report")
                        put("data", reportData)
                    }

                    // 通过 EventChannel 发送到 Flutter 端
                    mainHandler.post {
                        dpEventSink?.success(eventData.toString())
                    }

                    android.util.Log.d(
                        "MainActivity",
                        "✅ DP 更新事件已发送到 Flutter: $eventData"
                    )
                } catch (e: Exception) {
                    android.util.Log.e(
                        "MainActivity",
                        "❌ 解析 DP 数据失败: ${e.message}",
                        e
                    )
                }
            }

            /**
             * 设备移除回调
             * devId 设备 ID
             */
            override fun onRemoved(devId: String) {
                android.util.Log.d("MainActivity", "🗑️ onRemoved - devId: $devId")
            }

            /**
             * 设备上下线回调。如果设备断电或断网，服务端将会在3分钟后回调到此方法。
             * devId  设备 ID
             * online 是否在线，在线为 true
             */
            override fun onStatusChanged(devId: String, online: Boolean) {
                android.util.Log.d(
                    "MainActivity",
                    "🔄 onStatusChanged - devId: $devId, online: $online"
                )

                // 通过 EventChannel 发送网络状态变化事件到 Flutter 端
                val eventData = JSONObject().apply {
                    put("devId", devId)
                    put("type", "networkStatusChanged")
                    put("status", online)
                }

                if (online === false) {
                    val mDevice: IThingDevice? = ThingHomeSdk.newDeviceInstance(devId)
                    mDevice?.unRegisterDevListener();
                }

                mainHandler.post {
                    if (connectionEventSink != null) {
                        android.util.Log.d(
                            "MainActivity",
                            "✅ 发送网络状态变化事件到 Flutter: $eventData"
                        )
                        connectionEventSink?.success(eventData.toString())
                    } else {
                        android.util.Log.w(
                            "MainActivity",
                            "⚠️ connectionEventSink 为 null，无法发送网络状态变化事件"
                        )
                    }
                }
            }

            /**
             * 网络状态发生变动时的回调
             *  devId  设备 ID
             *  status 网络状态是否可用，可用为 true
             */
            override fun onNetworkStatusChanged(devId: String, status: Boolean) {
                // 设备断开蓝牙会走这里
                android.util.Log.d(
                    "MainActivity",
                    "🌐 onNetworkStatusChanged - devId: $devId, status: $status"
                )

                // 通过 EventChannel 发送网络状态变化事件到 Flutter 端
                val eventData = JSONObject().apply {
                    put("devId", devId)
                    put("type", "networkStatusChanged")
                    put("status", status)
                }

                mainHandler.post {
                    if (connectionEventSink != null) {
                        android.util.Log.d(
                            "MainActivity",
                            "✅ 发送网络状态变化事件到 Flutter: $eventData"
                        )
                        connectionEventSink?.success(eventData.toString())
                    } else {
                        android.util.Log.w(
                            "MainActivity",
                            "⚠️ connectionEventSink 为 null，无法发送网络状态变化事件"
                        )
                    }
                }
            }

            /**
             * 设备信息更新回调
             * devId  设备 ID
             */
            override fun onDevInfoUpdate(devId: String) {
                android.util.Log.d("MainActivity", "ℹ️ onDevInfoUpdate - devId: $devId")
            }
        })

        val dps: Map<String, Any>? = ThingHomeSdk.getDataInstance().getDps(devId)
        
        if (dps != null) {
            android.util.Log.d("MainActivity", "📊 获取设备 DPS 数据: devId=$devId")
            android.util.Log.d("MainActivity", "📊 DPS 数据内容: $dps")
            // 格式化打印每个 DPS 项
            dps.forEach { (key, value) ->
                android.util.Log.d("MainActivity", "   - DPS[$key] = $value (类型: ${value.javaClass.simpleName})")
                
                // 通过 getDp 方法获取单个 DP 的详细信息
                mDevice?.getDp(key, object : IResultCallback {
                    override fun onError(errorCode: String, errorMsg: String) {
                        android.util.Log.e(
                            "MainActivity",
                            "❌ 获取 DP[$key] 失败: code=$errorCode, error=$errorMsg"
                        )
                    }

                    override fun onSuccess() {
                        android.util.Log.d(
                            "MainActivity",
                            "✅ 成功获取 DP[$key] 的值: $value"
                        )
                    }
                })
            }
        } else {
            android.util.Log.w("MainActivity", "⚠️ 获取 DPS 数据为空: devId=$devId")
        }
        
        android.util.Log.d("MainActivity", "✅ 设备监听器注册完成: devId=$devId")
    }

    // 直接连接设备（已配网）
    private fun connectDeviceDirectly(
        devId: String,
        deviceId: String,
        uuid: String,
        productKey: String,
        result: MethodChannel.Result
    ) {
        android.util.Log.d("MainActivity", "🔗 开始连接设备: devId=$devId, deviceId=$deviceId")

        // 在主线程中执行连接操作（官方要求）
        mainHandler.post {
            updateConnectionState(deviceId, "connecting")

            val builderList = mutableListOf<BleConnectBuilder>()
            val bleConnectBuilder = BleConnectBuilder()
            bleConnectBuilder.setDevId(devId)
            bleConnectBuilder.setDirectConnect(true)
//            bleConnectBuilder.setLevel(BleConnectBuilder.Level.FORCE)
            builderList.add(bleConnectBuilder)

            ThingHomeSdk.getBleManager().connectBleDevice(builderList)

            // 由于连接是异步的，我们需要通过监听连接状态来判断是否成功
            // 这里先返回成功，实际状态通过 EventChannel 通知
            mainHandler.postDelayed({
                // 检查设备是否在线（使用 devId 检查连接状态）
                val isOnline = ThingHomeSdk.getBleManager().isBleLocalOnline(devId)
                if (isOnline) {
                    android.util.Log.d("MainActivity", "✅ 设备连接成功: devId=$devId")
                    updateConnectionState(deviceId, "connected")
                    // 连接成功后再注册监听器
                    registerDeviceListener(devId)
                    
                    // 返回包含devId的字典
                    val resultData = mapOf(
                        "success" to true,
                        "devId" to devId
                    )
                    result.success(resultData)
                } else {
                    android.util.Log.w("MainActivity", "⚠️ 设备连接可能失败: devId=$devId")
                    // 仍然返回成功，让 EventChannel 处理状态更新，但包含devId
                    val resultData = mapOf(
                        "success" to true,
                        "devId" to devId
                    )
                    result.success(resultData)
                }
            }, 2000) // 等待2秒检查连接状态
        }
    }

    private fun handleIsDeviceOnline(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val deviceId = args?.get("deviceId") as? String
            ?: run {
                result.error("INVALID_ARGUMENT", "deviceId is required", null)
                return
            }

        val isOnline = ThingHomeSdk.getBleManager().isBleLocalOnline(deviceId)
        result.success(isOnline)
    }

    private fun handleCheckDevicesOnline(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val deviceIds = args?.get("deviceIds") as? List<*>
            ?: run {
                result.error("INVALID_ARGUMENT", "deviceIds is required", null)
                return
            }

        android.util.Log.d("MainActivity", "🔍 批量检查设备在线状态: $deviceIds")

        val onlineStatusMap = mutableMapOf<String, Boolean>()
        for (deviceId in deviceIds) {
            val devId = deviceId.toString()
            val isOnline = ThingHomeSdk.getBleManager().isBleLocalOnline(devId)
            onlineStatusMap[devId] = isOnline
            android.util.Log.d("MainActivity", "  设备 $devId 在线状态: $isOnline")
        }

        result.success(onlineStatusMap)
    }

    private fun handleConnectBleDevices(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val deviceIds = args?.get("deviceIds") as? List<*>
            ?: run {
                result.error("INVALID_ARGUMENT", "deviceIds is required", null)
                return
            }

        android.util.Log.d("MainActivity", "🔗 批量连接设备: $deviceIds")

        // 在主线程中执行连接操作（官方要求）
        mainHandler.post {
            val builderList = mutableListOf<BleConnectBuilder>()
            for (deviceId in deviceIds) {
                val devId = deviceId.toString()
                updateConnectionState(devId, "connecting")
                val bleConnectBuilder = BleConnectBuilder()
                bleConnectBuilder.setDevId(devId)
                bleConnectBuilder.setDirectConnect(true)
//                bleConnectBuilder.setLevel(BleConnectBuilder.Level.FORCE)
                builderList.add(bleConnectBuilder)
            }

            ThingHomeSdk.getBleManager().connectBleDevice(builderList)

            // 等待一段时间后检查连接状态
            mainHandler.postDelayed({
                val connectionResults = mutableMapOf<String, Boolean>()
                for (deviceId in deviceIds) {
                    val devId = deviceId.toString()
                    android.util.Log.d("MainActivity", "xxxxxxxxxx: $devId")
                    val isOnline = ThingHomeSdk.getBleManager().isBleLocalOnline(devId)
                    connectionResults[devId] = isOnline
                    if (isOnline) {
                        android.util.Log.d("MainActivity", "✅ 设备连接成功: $devId")
                        updateConnectionState(devId, "connected")
                        // 连接成功后再注册监听器
                        registerDeviceListener(devId)
                    } else {
                        android.util.Log.w("MainActivity", "⚠️ 设备连接失败: $devId")
                        updateConnectionState(devId, "disconnected")
                    }
                }
                result.success(connectionResults)
            }, 3000) // 等待3秒检查连接状态
        }
    }

    private fun handleRemoveDevice(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val devId = args?.get("devId") as? String
            ?: run {
                result.error("INVALID_ARGUMENT", "devId is required", null)
                return
            }

        android.util.Log.d("MainActivity", "🗑️ 开始移除设备: $devId")

        val mDevice: IThingDevice? = ThingHomeSdk.newDeviceInstance(devId)

        mDevice?.removeDevice(object : IResultCallback {
            override fun onError(errorCode: String, errorMsg: String) {
                android.util.Log.e("MainActivity", "❌ 移除设备失败: $errorCode - $errorMsg")
                result.error(
                    "REMOVE_FAILED", errorMsg, mapOf(
                        "errorCode" to errorCode,
                        "errorMsg" to errorMsg
                    )
                )
            }

            override fun onSuccess() {
                android.util.Log.d("MainActivity", "✅ 设备移除成功: $devId")
                result.success(null)
            }
        })
    }

    private fun handleRegisterDeviceListener(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val devId = args?.get("deviceId") as? String
            ?: run {
                result.error("INVALID_ARGUMENT", "deviceId is required", null)
                return
            }

        android.util.Log.d("MainActivity", "📝 Flutter 请求注册设备监听器: devId=$devId")

        try {
            // 检查设备是否在线
            val isOnline = ThingHomeSdk.getBleManager().isBleLocalOnline(devId)
            if (!isOnline) {
                android.util.Log.w("MainActivity", "⚠️ 设备未在线，无法注册监听器: devId=$devId")
                result.error("DEVICE_OFFLINE", "Device is not online", null)
                return
            }

            // 注册监听器
            registerDeviceListener(devId)
            android.util.Log.d("MainActivity", "✅ 设备监听器注册成功: devId=$devId")
            result.success(null)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ 注册设备监听器失败: ${e.message}", e)
            result.error("REGISTER_FAILED", e.message ?: "Unknown error", null)
        }
    }

    private fun updateConnectionState(deviceId: String, state: String, error: String? = null) {
        deviceConnectionStates[deviceId] = state

        val eventData = JSONObject().apply {
            put("deviceId", deviceId)
            put("state", state)
            put("error", error ?: JSONObject.NULL)
        }

        mainHandler.post {
            connectionEventSink?.success(eventData.toString())
        }
    }

    // MARK: - DP Channels Setup
    private fun setupDpChannels(flutterEngine: FlutterEngine) {
        val dpMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DP_CHANNEL
        )

        android.util.Log.d("MainActivity", "✅ DP MethodChannel 已创建: $DP_CHANNEL")

        dpMethodChannel.setMethodCallHandler { call, result ->
            android.util.Log.d("MainActivity", "📞 收到DP方法调用: ${call.method}")

            when (call.method) {
                "publishDps" -> {
                    handlePublishDps(call, result)
                }
                "getDp" -> {
                    handleGetDp(call, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        val dpEventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DP_EVENT_CHANNEL
        )

        android.util.Log.d("MainActivity", "✅ DP EventChannel 已创建: $DP_EVENT_CHANNEL")

        dpEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    dpEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    dpEventSink = null
                }
            }
        )
    }

    // MARK: - DP Handlers
    private fun handlePublishDps(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val deviceId = args?.get("deviceId") as? String
        val dpsArray = args?.get("dps") as? List<*>

        if (deviceId == null || dpsArray == null) {
            result.error("INVALID_ARGUMENT", "deviceId and dps are required", null)
            return
        }

        android.util.Log.d("MainActivity", "📤 下发DP: $deviceId, DPs: ${dpsArray.size}")

        // 构建DP字典，格式: {"dpId": value}
        val dps = mutableMapOf<String, Any>()
        for (dpItem in dpsArray) {
            val dpMap = dpItem as? Map<*, *>
            val dpId = dpMap?.get("dpId") as? String
            val value = dpMap?.get("value")

            if (dpId != null && value != null) {
                dps[dpId] = value
                android.util.Log.d(
                    "MainActivity",
                    "  DP[$dpId] = $value (type: ${value.javaClass.simpleName})"
                )
            }
        }

        // 获取设备实例
        val device: IThingDevice? = try {
            ThingHomeSdk.newDeviceInstance(deviceId)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ 获取设备实例失败: ${e.message}")
            result.error(
                "DEVICE_NOT_FOUND",
                "Device not found or cannot create device instance: ${e.message}",
                null
            )
            return
        }

        if (device == null) {
            android.util.Log.e("MainActivity", "❌ 设备实例为空")
            result.error("DEVICE_NOT_FOUND", "Device instance is null", null)
            return
        }

        // 将DP Map转换为JSON字符串（Android SDK需要JSON字符串格式）
        val dpsJsonString = JSON.toJSONString(dps)
        android.util.Log.d("MainActivity", "  DP JSON: $dpsJsonString")

        // 发送DP数据
        device.publishDps(dpsJsonString, object : IResultCallback {
            override fun onError(code: String?, error: String?) {
                val errorCode = code ?: "UNKNOWN"
                val errorMsg = error ?: "Unknown error"
                android.util.Log.e(
                    "MainActivity",
                    "❌ DP下发失败: $deviceId, code=$errorCode, error=$errorMsg, originalErr=$error"
                )

                // 错误码 11001 有下面几种原因：
                // 1：数据类型发送格式错误，例如，String 类型格式发成 Boolean 类型数据。
                // 2：不能下发只读类型 DP 数据，参考 SchemaBean getMode，"ro" 是只读类型。
                // 3：Raw 格式数据发送的不是 16 进制字符串。
                val errorMessage = when (errorCode) {
                    "11001" -> {
                        when {
                            errorMsg.contains(
                                "类型",
                                ignoreCase = true
                            ) || errorMsg.contains("type", ignoreCase = true) -> {
                                "数据类型发送格式错误，例如，String 类型格式发成 Boolean 类型数据"
                            }

                            errorMsg.contains(
                                "只读",
                                ignoreCase = true
                            ) || errorMsg.contains(
                                "readonly",
                                ignoreCase = true
                            ) || errorMsg.contains("ro", ignoreCase = true) -> {
                                "不能下发只读类型 DP 数据，参考 SchemaBean getMode，\"ro\" 是只读类型"
                            }

                            errorMsg.contains(
                                "hex",
                                ignoreCase = true
                            ) || errorMsg.contains(
                                "16进制",
                                ignoreCase = true
                            ) || errorMsg.contains("raw", ignoreCase = true) -> {
                                "Raw 格式数据发送的不是 16 进制字符串"
                            }

                            else -> "DP下发失败: $errorMsg"
                        }
                    }

                    else -> "DP下发失败: $errorMsg (code: $errorCode)"
                }

                result.error(
                    "PUBLISH_FAILED", errorMessage, mapOf(
                        "code" to errorCode,
                        "error" to errorMsg,
                        "deviceId" to deviceId,
                        "dps" to dps
                    )
                )
            }

            override fun onSuccess() {
                android.util.Log.d("MainActivity", "✅ DP下发成功: $deviceId")
                result.success(true)
            }
        })
    }

    // 获取单个 DP 的值
    private fun handleGetDp(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val deviceId = args?.get("deviceId") as? String
        val dpId = args?.get("dpId") as? String

        if (deviceId == null || dpId == null) {
            result.error("INVALID_ARGUMENT", "deviceId and dpId are required", null)
            return
        }

        android.util.Log.d("MainActivity", "📥 获取DP: deviceId=$deviceId, dpId=$dpId")

        // 获取设备实例
        val device: IThingDevice? = try {
            ThingHomeSdk.newDeviceInstance(deviceId)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ 获取设备实例失败: ${e.message}")
            result.error(
                "DEVICE_NOT_FOUND",
                "Device not found or cannot create device instance: ${e.message}",
                null
            )
            return
        }

        if (device == null) {
            android.util.Log.e("MainActivity", "❌ 设备实例为空")
            result.error("DEVICE_NOT_FOUND", "Device instance is null", null)
            return
        }

        // 使用 getDp 方法获取单个 DP 的值
        device.getDp(dpId, object : IResultCallback {
            override fun onError(errorCode: String, errorMsg: String) {
                android.util.Log.e(
                    "MainActivity",
                    "❌ 获取 DP[$dpId] 失败: code=$errorCode, error=$errorMsg"
                )
                result.error(
                    "GET_DP_FAILED",
                    "Failed to get DP: $errorMsg",
                    mapOf(
                        "code" to errorCode,
                        "error" to errorMsg,
                        "deviceId" to deviceId,
                        "dpId" to dpId
                    )
                )
            }

            override fun onSuccess() {
                // getDp 成功后，需要从 getDps 获取实际值
                // 因为 getDp 的回调不返回具体值，我们需要通过 getDps 来获取
                try {
                    val allDps: Map<String, Any>? = ThingHomeSdk.getDataInstance().getDps(deviceId)
                    if (allDps != null && allDps.containsKey(dpId)) {
                        val dpValue = allDps[dpId]
                        android.util.Log.d(
                            "MainActivity",
                            "✅ 成功获取 DP[$dpId] = $dpValue (类型: ${dpValue?.javaClass?.simpleName})"
                        )
                        result.success(mapOf(
                            "dpId" to dpId,
                            "value" to dpValue
                        ))
                    } else {
                        android.util.Log.w("MainActivity", "⚠️ DP[$dpId] 不存在或值为空")
                        result.error(
                            "DP_NOT_FOUND",
                            "DP not found or value is null",
                            mapOf("deviceId" to deviceId, "dpId" to dpId)
                        )
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ 获取 DP 值失败: ${e.message}")
                    result.error(
                        "GET_DP_VALUE_FAILED",
                        "Failed to get DP value: ${e.message}",
                        null
                    )
                }
            }
        })
    }

    private fun processStartScan(result: MethodChannel.Result) {
        val hasPermissions = hasBluetoothPermissions()
        android.util.Log.d("MainActivity", "Has permissions: $hasPermissions")

        if (!hasPermissions) {
            android.util.Log.w("MainActivity", "⚠️ 蓝牙权限未授予，尝试再次申请...")
            requestBluetoothPermissions()
            result.error("PERMISSION_DENIED", "蓝牙权限未授予，请先授予权限后再试", null)
            return
        }

        val bluetoothEnabled = isBluetoothEnabled()
        android.util.Log.d("MainActivity", "Bluetooth enabled: $bluetoothEnabled")

        if (!bluetoothEnabled) {
            android.util.Log.w("MainActivity", "⚠️ Bluetooth is not enabled")
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null)
            return
        }

        android.util.Log.d("MainActivity", "✅ All checks passed, calling startBleScan with result")
        startBleScan(result)
    }

    private fun startBleScan(result: MethodChannel.Result? = null) {
        android.util.Log.d("MainActivity", "startBleScan called, isScanning: $isScanning")

        if (isScanning) {
            android.util.Log.w("MainActivity", "Scan already in progress, returning")
            result?.error("ALREADY_SCANNING", "Scan is already in progress", null)
            return
        }

        isScanning = true
        android.util.Log.d("MainActivity", "Setting isScanning = true")

        mainHandler.removeCallbacksAndMessages(null)

        try {
            val scanSetting = LeScanSetting.Builder()
                .setTimeout(10000)
                .addScanType(ScanType.SINGLE)
                .build()

            android.util.Log.d("MainActivity", "Starting BLE scan with ThingHomeSdk...")

            val bleOperator = ThingHomeSdk.getBleOperator()
            android.util.Log.d("MainActivity", "BleOperator obtained: ${bleOperator != null}")

            bleOperator.startLeScan(scanSetting, object : BleScanResponse {
                override fun onResult(bean: ScanDeviceBean) {
                    android.util.Log.d(
                        "MainActivity",
                        "🔍 Device found: id=${bean.id}, name=${bean.name}, rssi=${bean.rssi}, uuid=${bean.uuid}"
                    )

                    // 保存设备信息
                    bean.uuid?.let { uuid ->
                        scannedDevices[uuid] = bean
                    }

                    mainHandler.post {
                        try {
                            val deviceInfo = JSONObject().apply {
                                put("id", bean.id ?: "")
                                put("name", bean.name ?: "")
                                put("uuid", bean.uuid ?: "")
                                put("devId", "")
                                put("providerName", bean.providerName ?: "")
                                put("rssi", bean.rssi)
                                // 尝试获取 isActive 属性
                                val isActive = try {
                                    val isActiveField = bean.javaClass.getDeclaredField("isActive")
                                    isActiveField.isAccessible = true
                                    isActiveField.getBoolean(bean)
                                } catch (e: Exception) {
                                    false
                                }
                                put("isActive", isActive)
                                // 尝试获取 isProuductKey 属性
                                val isProuductKey = try {
                                    val isProuductKeyField =
                                        bean.javaClass.getDeclaredField("isProuductKey")
                                    isProuductKeyField.isAccessible = true
                                    isProuductKeyField.getBoolean(bean)
                                } catch (e: Exception) {
                                    false
                                }
                                put("isProuductKey", isProuductKey)
                                put(
                                    "isOnline",
                                    ThingHomeSdk.getBleManager().isBleLocalOnline(bean.id ?: "")
                                )
                            }
                            android.util.Log.d(
                                "MainActivity",
                                "Sending device info to Flutter: ${deviceInfo.toString()}"
                            )
                            eventSink?.success(deviceInfo.toString())
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error sending device info", e)
                        }
                    }
                }
            })

            android.util.Log.d("MainActivity", "✅ startLeScan() called, waiting for results...")

            mainHandler.postDelayed({
                if (isScanning) {
                    android.util.Log.d(
                        "MainActivity",
                        "⏰ Scan timeout (10s), resetting isScanning flag"
                    )
                    isScanning = false
                    mainHandler.post {
                        eventSink?.success("SCAN_TIMEOUT")
                    }
                }
            }, 11000)

            android.util.Log.d(
                "MainActivity",
                "✅ BLE scan started successfully, sending result to Flutter"
            )
            result?.success("Scan started")
        } catch (e: Exception) {
            isScanning = false
            android.util.Log.e("MainActivity", "Error starting scan", e)
            result?.error("SCAN_ERROR", "Failed to start scan: ${e.message}", null)
            mainHandler.post {
                eventSink?.error("SCAN_ERROR", "Failed to start scan: ${e.message}", null)
            }
        }
    }

    private fun stopBleScan() {
        if (!isScanning) {
            android.util.Log.d("MainActivity", "stopBleScan called but not scanning")
            return
        }

        android.util.Log.d("MainActivity", "Stopping BLE scan...")
        isScanning = false

        mainHandler.removeCallbacksAndMessages(null)

        try {
            ThingHomeSdk.getBleOperator().stopLeScan()
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error stopping scan", e)
        }

        mainHandler.post {
            eventSink?.success("SCAN_STOPPED")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        when (requestCode) {
            PERMISSION_REQUEST_CODE -> {
                val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                mainHandler.post {
                    if (allGranted) {
                        eventSink?.success("PERMISSIONS_GRANTED")
                    } else {
                        eventSink?.success("PERMISSIONS_DENIED")
                    }
                }
            }

            LOCATION_PERMISSION_REQUEST_CODE -> {
                val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (allGranted) {
                    requestLocation()
                } else {
                    android.util.Log.w("MainActivity", "⚠️ 位置权限被拒绝，使用默认值")
                    countryCode = "1"
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        locationManager?.removeUpdates(this)
    }
}
