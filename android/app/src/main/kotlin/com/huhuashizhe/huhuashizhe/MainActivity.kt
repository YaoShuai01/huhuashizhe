package com.huhuashizhe.huhuashizhe

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Geocoder
import android.location.GnssStatus
import android.location.GpsSatellite
import android.location.GpsStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val INSTALLER_CHANNEL = "com.huhuashizhe/apk_installer"
    private val GALLERY_CHANNEL = "com.huhuashizhe/gallery"
    private val LOCATION_CHANNEL = "com.huhuashizhe/location"
    private val BLUETOOTH_CHANNEL = "com.huhuashizhe/bluetooth"
    private val BLUETOOTH_EVENT_CHANNEL = "com.huhuashizhe/bluetooth_events"
    private val WIFI_CHANNEL = "com.huhuashizhe/wifi"
    private val WIFI_EVENT_CHANNEL = "com.huhuashizhe/wifi_events"
    private val GNSS_EVENT_CHANNEL = "com.huhuashizhe/gnss_events"
    private val COMPASS_EVENT_CHANNEL = "com.huhuashizhe/compass_events"
    private val VOICE_CHANNEL = "com.huhuashizhe/voice_input"
    private var voiceChannel: MethodChannel? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var locationResult: MethodChannel.Result? = null
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null
    private var bestLocation: Location? = null
    private var locationTimeoutHandler: Handler? = null
    private var locationTimeoutRunnable: Runnable? = null

    // GNSS卫星状态追踪（北斗+GPS+GLONASS+Galileo）
    private var gnssStatusCallback: GnssStatus.Callback? = null
    private var satelliteInfo: Map<String, Int> =
        mapOf("gps" to 0, "beidou" to 0, "glonass" to 0, "galileo" to 0, "total" to 0, "used" to 0)
    private var gnssEventSink: EventChannel.EventSink? = null
    private var gnssSatellites: List<Map<String, Any>> = emptyList()
    private var gnssKeepAliveListener: LocationListener? = null

    // 罗盘方向传感器
    private var compassEventSink: EventChannel.EventSink? = null
    private var sensorManager: SensorManager? = null
    private var compassSensor: Sensor? = null
    private var compassListener: SensorEventListener? = null

    // 蓝牙相关
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothEventSink: EventChannel.EventSink? = null
    private var isScanning = false
    private var scanTimeoutHandler: Handler? = null
    private var scanTimeoutRunnable: Runnable? = null
    private val discoveredDevices = mutableSetOf<String>()

    // WiFi 相关
    private var wifiEventSink: EventChannel.EventSink? = null
    private var isWifiScanning = false
    private var wifiScanTimeoutHandler: Handler? = null
    private var wifiScanTimeoutRunnable: Runnable? = null
    private var wifiReceiverRegistered = false
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 相册导出通道（生长检测图片保存到系统相册）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GALLERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> saveImageToGallery(call.argument("path") ?: "", call.argument("displayName") ?: "", result)
                else -> result.notImplemented()
            }
        }

        // APK安装通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> installApk(call.argument("path") ?: "", result)
                "getDownloadDir" -> getDownloadDir(result)
                else -> result.notImplemented()
            }
        }

        // GPS定位通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocation" -> getCurrentLocation(result)
                "getSatelliteInfo" -> getSatelliteInfo(result)
                "reverseGeocode" -> {
                    val lat = call.argument<Double>("lat") ?: 0.0
                    val lng = call.argument<Double>("lng") ?: 0.0
                    reverseGeocode(lat, lng, result)
                }
                else -> result.notImplemented()
            }
        }

        // 蓝牙事件通道（持续发送扫描结果）
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bluetoothEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    bluetoothEventSink = null
                }
            }
        )

        // 蓝牙控制通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScan" -> startBluetoothScan(result)
                "stopScan" -> stopBluetoothScan(result)
                "getBondedDevices" -> getBondedDevices(result)
                "isBluetoothEnabled" -> isBluetoothEnabled(result)
                else -> result.notImplemented()
            }
        }

        // WiFi 扫描事件通道
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    wifiEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    wifiEventSink = null
                }
            }
        )

        // WiFi 控制通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWifiEnabled" -> result.success(wifiManager()?.isWifiEnabled == true)
                "getCurrentSsid" -> result.success(currentWifiSsid())
                "startScan" -> startWifiScan(result)
                "stopScan" -> stopWifiScan(result)
                "openWifiSettings" -> openWifiSettings(result)
                "acquireWifiLock" -> result.success(acquireWifiLock())
                "releaseWifiLock" -> {
                    releaseWifiLock()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // GNSS 逐星状态事件通道（实时卫星方位/仰角/信噪比）
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, GNSS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    gnssEventSink = events
                    locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
                    if (ContextCompat.checkSelfPermission(
                            this@MainActivity,
                            Manifest.permission.ACCESS_FINE_LOCATION
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        events?.error("permission", "需要定位权限才能搜星", null)
                        return
                    }
                    startGnssMonitoring()
                    startGnssKeepAlive()
                    sendGnssSnapshot()
                }

                override fun onCancel(arguments: Any?) {
                    gnssEventSink = null
                    stopGnssKeepAlive()
                    if (locationResult == null) stopGnssMonitoring()
                }
            }
        )

        // 罗盘方向事件通道（手机朝向，供卫星罗盘指北）
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    compassEventSink = events
                    startCompass()
                }

                override fun onCancel(arguments: Any?) {
                    compassEventSink = null
                    stopCompass()
                }
            }
        )

        // 语音输入通道（论坛发帖/评论）
        val voice = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
        voiceChannel = voice
        voice.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startVoiceRecognition(result)
                "stop" -> {
                    stopVoiceRecognition()
                    result.success(true)
                }
                "isAvailable" -> result.success(SpeechRecognizer.isRecognitionAvailable(this))
                else -> result.notImplemented()
            }
        }
    }

    private fun getDownloadDir(result: MethodChannel.Result) {
        // 返回外部存储的应用专属文件目录，系统安装器可访问
        val externalFilesDir = getExternalFilesDir(null)?.absolutePath
        if (externalFilesDir != null) {
            result.success(externalFilesDir)
        } else {
            // 回退到外部存储的下载目录
            result.success(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath)
        }
    }

    /// 将图片文件保存到系统相册（MediaStore），返回保存后的URI字符串
    private fun saveImageToGallery(path: String, displayName: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "图片文件不存在: $path", null)
                return
            }
            val name = if (displayName.isNotBlank()) displayName else file.name

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/护花使者")
                    put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val uri = resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore插入失败")
                resolver.openOutputStream(uri)?.use { out ->
                    file.inputStream().use { it.copyTo(out) }
                } ?: throw IllegalStateException("无法写入MediaStore")
                values.clear()
                values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                result.success(uri.toString())
            } else {
                // Android 9及以下：直接写入公共Pictures目录
                val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES + "/护花使者")
                if (!picturesDir.exists()) picturesDir.mkdirs()
                val dest = File(picturesDir, name)
                file.copyTo(dest, overwrite = true)
                // 通知相册扫描
                val scanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                scanIntent.data = Uri.fromFile(dest)
                sendBroadcast(scanIntent)
                result.success(Uri.fromFile(dest).toString())
            }
        } catch (e: Exception) {
            result.error("SAVE_FAILED", "保存到相册失败: ${e.message}", null)
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            if (path.isEmpty()) {
                result.error("INVALID_PATH", "APK路径为空", null)
                return
            }
            val file = File(path)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK文件不存在: $path", null)
                return
            }
            file.setReadable(true, false)

            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            } else {
                Uri.fromFile(file)
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", "安装失败: ${e.message}", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun getCurrentLocation(result: MethodChannel.Result) {
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager

        // 检查权限
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                1001
            )
            result.success(null)
            return
        }

        // 启动GNSS卫星状态监听
        startGnssMonitoring()

        // 缓存仅用于超时兜底，不再直接返回缓存位置
        val cachedGps = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        val cachedNetwork = locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)

        // 总是启动实时定位，等待新数据
        locationResult = result
        bestLocation = null

        locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                // 记录最佳精度位置
                if (bestLocation == null || location.accuracy < bestLocation!!.accuracy) {
                    bestLocation = location
                }
                // GPS精度足够（< 30米）或网络定位（< 50米）即返回
                val isGoodEnough = (location.provider == LocationManager.GPS_PROVIDER && location.accuracy < 30f)
                    || (location.provider == LocationManager.NETWORK_PROVIDER && location.accuracy < 50f)
                if (isGoodEnough && locationResult != null) {
                    returnLocation(location)
                }
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }

        // 8秒超时：返回最佳可用位置（即使精度不够）
        locationTimeoutHandler = Handler(Looper.getMainLooper())
        locationTimeoutRunnable = Runnable {
            if (locationResult != null) {
                if (bestLocation != null) {
                    returnLocation(bestLocation!!)
                } else {
                    // 8秒内完全没定位：返回过期缓存作为兜底
                    val anyCached = cachedGps ?: cachedNetwork
                        ?: locationManager?.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
                    if (anyCached != null) {
                        returnLocation(anyCached)
                    } else {
                        locationResult?.success(null)
                        locationResult = null
                        cleanupLocation()
                    }
                }
            }
        }
        locationTimeoutHandler?.postDelayed(locationTimeoutRunnable!!, 8000)

        // 同时请求GPS和网络定位
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {}
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {}
    }

    private fun returnLocation(location: Location) {
        locationResult?.success(mapOf(
            "lat" to location.latitude,
            "lng" to location.longitude,
            "accuracy" to location.accuracy,
            "provider" to location.provider,
            "timestamp" to location.time,
            "satellites" to satelliteInfo
        ))
        locationResult = null
        cleanupLocation()
    }

    /// 后台静默更新GPS缓存，不阻塞调用方
    @SuppressLint("MissingPermission")
    private fun silentlyUpdateLocation() {
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 0L, 0f,
                object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        locationManager?.removeUpdates(this)
                    }
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                },
                Looper.getMainLooper()
            )
        } catch (e: Exception) {}
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER, 0L, 0f,
                object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        locationManager?.removeUpdates(this)
                    }
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                },
                Looper.getMainLooper()
            )
        } catch (e: Exception) {}
    }

    private fun cleanupLocation() {
        locationTimeoutHandler?.removeCallbacks(locationTimeoutRunnable ?: return)
        locationTimeoutRunnable = null
        locationListener?.let { locationManager?.removeUpdates(it) }
        locationListener = null
        locationResult = null
        bestLocation = null
    }

    // ==================== GNSS卫星状态监控（北斗+GPS+GLONASS+Galileo） ====================

    @SuppressLint("MissingPermission")
    private fun startGnssMonitoring() {
        if (gnssStatusCallback != null) return // 已在监听
        locationManager = locationManager ?: getSystemService(LOCATION_SERVICE) as LocationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            gnssStatusCallback = object : GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: GnssStatus) {
                    var gps = 0; var beidou = 0; var glonass = 0; var galileo = 0; var used = 0
                    val sats = mutableListOf<Map<String, Any>>()
                    for (i in 0 until status.satelliteCount) {
                        val constellation = status.getConstellationType(i)
                        val system = when (constellation) {
                            GnssStatus.CONSTELLATION_GPS -> "gps"
                            GnssStatus.CONSTELLATION_BEIDOU -> "beidou"
                            GnssStatus.CONSTELLATION_GLONASS -> "glonass"
                            GnssStatus.CONSTELLATION_GALILEO -> "galileo"
                            else -> "unknown"
                        }
                        val isUsed = status.usedInFix(i)
                        if (isUsed) used++
                        when (system) {
                            "gps" -> gps++
                            "beidou" -> beidou++
                            "glonass" -> glonass++
                            "galileo" -> galileo++
                        }
                        sats.add(mapOf(
                            "system" to system,
                            "constellation" to constellation,
                            "svid" to status.getSvid(i),
                            "azimuth" to status.getAzimuthDegrees(i).toDouble(),
                            "elevation" to status.getElevationDegrees(i).toDouble(),
                            "snr" to status.getCn0DbHz(i).toDouble(),
                            "used" to isUsed
                        ))
                    }
                    satelliteInfo = mapOf(
                        "gps" to gps, "beidou" to beidou,
                        "glonass" to glonass, "galileo" to galileo,
                        "total" to status.satelliteCount, "used" to used
                    )
                    gnssSatellites = sats
                    sendGnssSnapshot()
                }
            }
            locationManager?.registerGnssStatusCallback(gnssStatusCallback!!)
        } else {
            // Android 6 及以下使用 GpsStatus.Listener
            locationManager?.addGpsStatusListener(gpsStatusListener)
        }
    }

    private val gpsStatusListener = @SuppressLint("MissingPermission") object : GpsStatus.Listener {
        override fun onGpsStatusChanged(event: Int) {
            if (event == GpsStatus.GPS_EVENT_SATELLITE_STATUS) {
                val status = locationManager?.getGpsStatus(null)
                if (status != null) {
                    val sats = mutableListOf<Map<String, Any>>()
                    var used = 0
                    val iter = status.satellites.iterator()
                    while (iter.hasNext()) {
                        val sat = iter.next()
                        if (sat.usedInFix()) used++
                        // Android 6以下无法区分星座，全部归为GPS
                        sats.add(mapOf(
                            "system" to "gps",
                            "constellation" to 1,
                            "svid" to sat.prn,
                            "azimuth" to sat.azimuth.toDouble(),
                            "elevation" to sat.elevation.toDouble(),
                            "snr" to sat.snr.toDouble(),
                            "used" to sat.usedInFix()
                        ))
                    }
                    satelliteInfo = mapOf(
                        "gps" to sats.size, "beidou" to 0,
                        "glonass" to 0, "galileo" to 0,
                        "total" to sats.size, "used" to used
                    )
                    gnssSatellites = sats
                    sendGnssSnapshot()
                }
            }
        }
    }

    /// 搜星页打开期间保持 GPS 引擎工作，保证卫星状态持续上报
    @SuppressLint("MissingPermission")
    private fun startGnssKeepAlive() {
        if (gnssKeepAliveListener != null) return
        locationManager = locationManager ?: getSystemService(LOCATION_SERVICE) as LocationManager
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {}
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        gnssKeepAliveListener = listener
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 1000L, 0f, listener, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            gnssKeepAliveListener = null
        }
    }

    private fun stopGnssKeepAlive() {
        gnssKeepAliveListener?.let {
            try {
                locationManager?.removeUpdates(it)
            } catch (e: Exception) {}
        }
        gnssKeepAliveListener = null
    }

    private fun sendGnssSnapshot() {
        val sink = gnssEventSink ?: return
        val payload = mapOf(
            "timestamp" to System.currentTimeMillis(),
            "total" to (satelliteInfo["total"] ?: 0),
            "used" to (satelliteInfo["used"] ?: 0),
            "counts" to satelliteInfo,
            "satellites" to gnssSatellites
        )
        runOnUiThread { sink.success(payload) }
    }

    private fun stopGnssMonitoring() {
        gnssStatusCallback?.let {
            locationManager?.unregisterGnssStatusCallback(it)
        }
        gnssStatusCallback = null
        try {
            locationManager?.removeGpsStatusListener(gpsStatusListener)
        } catch (e: Exception) {}
    }

    private fun getSatelliteInfo(result: MethodChannel.Result) {
        result.success(satelliteInfo)
    }

    // ==================== 罗盘方向传感器 ====================

    private fun startCompass() {
        if (compassListener != null) return
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        compassSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
        val sensor = compassSensor
        if (sensor == null) {
            compassEventSink?.error("unavailable", "设备没有方向传感器", null)
            return
        }

        val rotationMatrix = FloatArray(9)
        val orientation = FloatArray(3)
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
                SensorManager.getOrientation(rotationMatrix, orientation)
                var degrees = Math.toDegrees(orientation[0].toDouble()).toFloat()
                degrees = (degrees + 360f) % 360f

                // 补偿屏幕方向，让 heading 相对于当前屏幕顶部
                val screenRotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display?.rotation ?: Surface.ROTATION_0
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay.rotation
                }
                when (screenRotation) {
                    Surface.ROTATION_90 -> degrees = (degrees + 90f) % 360f
                    Surface.ROTATION_180 -> degrees = (degrees + 180f) % 360f
                    Surface.ROTATION_270 -> degrees = (degrees + 270f) % 360f
                }

                compassEventSink?.success(mapOf(
                    "heading" to degrees.toDouble(),
                    "accuracy" to event.accuracy
                ))
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        compassListener = listener
        sensorManager?.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    private fun stopCompass() {
        compassListener?.let { sensorManager?.unregisterListener(it) }
        compassListener = null
    }

    private fun reverseGeocode(lat: Double, lng: Double, result: MethodChannel.Result) {
        Thread {
            try {
                val geocoder = Geocoder(this, java.util.Locale.CHINA)
                val addresses = geocoder.getFromLocation(lat, lng, 1)
                if (addresses != null && addresses.isNotEmpty()) {
                    val addr = addresses[0]
                    val parts = mutableListOf<String>()
                    // 省去省份，只保留市·区·镇三级
                    addr.locality?.let { if (it.isNotEmpty()) parts.add(it) }
                    addr.subLocality?.let { if (it.isNotEmpty() && it != parts.lastOrNull()) parts.add(it) }
                    addr.featureName?.let { if (it.isNotEmpty()) parts.add(it) }
                    val name = parts.joinToString(" · ")
                    runOnUiThread { result.success(name) }
                } else {
                    runOnUiThread { result.success(null) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.success(null) }
            }
        }.start()
    }

    // ==================== WiFi 扫描功能 ====================

    private fun wifiManager(): WifiManager? =
        applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    /// 图传专用：申请 WiFi 高性能锁，关闭省电模式。
    /// 默认省电模式下手机每个 DTIM 周期才取一次缓存包，下行吞吐被压到 2Mbps 左右，
    /// 图传会大量丢段、画面出不来。
    private fun acquireWifiLock(): Boolean {
        return try {
            val wm = wifiManager() ?: return false
            if (wifiLock == null) {
                val modes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    intArrayOf(
                        WifiManager.WIFI_MODE_FULL_LOW_LATENCY,
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    )
                } else {
                    intArrayOf(WifiManager.WIFI_MODE_FULL_HIGH_PERF)
                }
                for (mode in modes) {
                    try {
                        wifiLock = wm.createWifiLock(mode, "huhuashizhe:video")
                    } catch (_: Exception) {
                        wifiLock = null
                    }
                    if (wifiLock != null) break
                }
                wifiLock?.setReferenceCounted(false)
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()
            wifiLock?.isHeld == true
        } catch (e: Exception) {
            false
        }
    }

    private fun releaseWifiLock() {
        try {
            val lock = wifiLock ?: return
            if (lock.isHeld) lock.release()
        } catch (e: Exception) {
        }
    }

    /// 当前连接的 WiFi 名称（SSID），未连接返回 null
    private fun currentWifiSsid(): String? {
        return try {
            val wm = wifiManager() ?: return null
            @Suppress("DEPRECATION")
            val info = wm.connectionInfo
            @Suppress("DEPRECATION")
            val raw = info?.ssid ?: return null
            val ssid = raw.trim('"')
            if (ssid.isEmpty() || ssid == "<unknown ssid>") null else ssid
        } catch (e: Exception) {
            null
        }
    }

    private fun hasWifiScanPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestWifiScanPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES, Manifest.permission.ACCESS_FINE_LOCATION),
                1003
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                1003
            )
        }
    }

    private fun startWifiScan(result: MethodChannel.Result?) {
        val wm = wifiManager()
        if (wm == null) {
            result?.error("NO_WIFI", "设备不支持 WiFi", null)
            return
        }
        if (!wm.isWifiEnabled) {
            result?.error("WIFI_DISABLED", "WiFi 未开启", null)
            return
        }
        if (!hasWifiScanPermission()) {
            requestWifiScanPermission()
            result?.error("NO_PERMISSION", "正在请求 WiFi 扫描权限，请稍后重试", null)
            return
        }
        if (isWifiScanning) {
            result?.success(true)
            return
        }

        isWifiScanning = true
        result?.success(true)

        // 注册扫描结果广播（只注册一次）
        if (!wifiReceiverRegistered) {
            try {
                registerReceiver(wifiScanReceiver, IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION))
                wifiReceiverRegistered = true
            } catch (e: Exception) {
            }
        }

        // 先推送系统缓存的扫描结果，避免列表空白
        emitWifiScanResults(wm)

        try {
            @Suppress("DEPRECATION")
            wm.startScan()
        } catch (e: Exception) {
            // 部分机型限制主动扫描，使用缓存结果兜底
        }

        // 8 秒超时，避免一直处于扫描中
        wifiScanTimeoutHandler = Handler(Looper.getMainLooper())
        wifiScanTimeoutRunnable = Runnable { stopWifiScan(null) }
        wifiScanTimeoutHandler?.postDelayed(wifiScanTimeoutRunnable!!, 8000)
    }

    private fun emitWifiScanResults(wm: WifiManager) {
        val currentSsid = currentWifiSsid()
        val results = try {
            wm.scanResults
        } catch (e: Exception) {
            emptyList<android.net.wifi.ScanResult>()
        }
        for (item in results) {
            val ssid = item.SSID ?: continue
            if (ssid.isEmpty()) continue
            val capabilities = item.capabilities ?: ""
            val secured = capabilities.contains("WPA") ||
                capabilities.contains("WEP") ||
                capabilities.contains("SAE") ||
                capabilities.contains("EAP")
            wifiEventSink?.success(
                mapOf(
                    "type" to "network",
                    "ssid" to ssid,
                    "bssid" to (item.BSSID ?: ""),
                    "rssi" to item.level,
                    "secured" to secured,
                    "isCurrent" to (ssid == currentSsid)
                )
            )
        }
    }

    private fun stopWifiScan(result: MethodChannel.Result?) {
        if (!isWifiScanning) {
            result?.success(true)
            return
        }
        isWifiScanning = false

        wifiScanTimeoutRunnable?.let { wifiScanTimeoutHandler?.removeCallbacks(it) }
        wifiScanTimeoutRunnable = null

        try {
            if (wifiReceiverRegistered) {
                unregisterReceiver(wifiScanReceiver)
                wifiReceiverRegistered = false
            }
        } catch (e: Exception) {
        }

        wifiEventSink?.success(mapOf("type" to "scanComplete"))
        result?.success(true)
    }

    private val wifiScanReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) {
                try {
                    wifiManager()?.let { emitWifiScanResults(it) }
                } catch (e: Exception) {
                }
                stopWifiScan(null)
            }
        }
    }

    /// Android 10+ 无法由应用直接连接 WiFi，跳系统设置由用户确认
    private fun openWifiSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", "无法打开 WiFi 设置: ${e.message}", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            // 权限授予后重新获取位置
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                locationResult?.let { getCurrentLocation(it) }
            } else {
                locationResult?.success(null)
            }
        }
        if (requestCode == 1002) {
            // 蓝牙权限授予后重新开始扫描
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startBluetoothScan(null)
            }
        }
        if (requestCode == 1003) {
            // WiFi 扫描权限授予后重新开始扫描
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startWifiScan(null)
            }
        }
    }

    // ==================== 蓝牙功能 ====================

    private fun isBluetoothEnabled(result: MethodChannel.Result) {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            result.success(false)
        } else {
            bluetoothAdapter = adapter
            result.success(adapter.isEnabled)
        }
    }

    @SuppressLint("MissingPermission")
    private fun getBondedDevices(result: MethodChannel.Result) {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            result.error("NO_BT", "设备不支持蓝牙", null)
            return
        }
        bluetoothAdapter = adapter

        if (!hasBluetoothPermissions()) {
            result.error("NO_PERMISSION", "缺少蓝牙权限", null)
            return
        }

        val devices = mutableListOf<Map<String, Any>>()
        for (device in adapter.bondedDevices) {
            devices.add(deviceToMap(device))
        }
        result.success(devices)
    }

    private fun startBluetoothScan(result: MethodChannel.Result?) {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            result?.error("NO_BT", "设备不支持蓝牙", null)
            return
        }
        bluetoothAdapter = adapter

        if (!adapter.isEnabled) {
            result?.error("BT_DISABLED", "蓝牙未开启", null)
            return
        }

        if (!hasBluetoothPermissions()) {
            requestBluetoothPermissions()
            result?.error("NO_PERMISSION", "正在请求蓝牙权限，请稍后再试", null)
            return
        }

        if (isScanning) {
            result?.success(true)
            return
        }

        isScanning = true
        discoveredDevices.clear()
        result?.success(true)

        // 先发送已配对设备
        try {
            for (device in adapter.bondedDevices) {
                val map = deviceToMap(device)
                discoveredDevices.add(device.address)
                bluetoothEventSink?.success(map)
            }
        } catch (e: SecurityException) {}

        // 启动BLE扫描
        bluetoothLeScanner = adapter.bluetoothLeScanner
        if (bluetoothLeScanner != null) {
            try {
                val scanSettings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .setReportDelay(0)
                    .build()
                bluetoothLeScanner?.startScan(null, scanSettings, leScanCallback)
            } catch (e: SecurityException) {
                result?.error("SCAN_FAILED", "BLE扫描启动失败: ${e.message}", null)
                isScanning = false
                return
            }
        }

        // 启动经典蓝牙发现
        try {
            adapter.startDiscovery()
        } catch (e: SecurityException) {}

        // 注册经典蓝牙发现广播接收器
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        registerReceiver(discoveryReceiver, filter)

        // 10秒超时自动停止
        scanTimeoutHandler = Handler(Looper.getMainLooper())
        scanTimeoutRunnable = Runnable {
            stopBluetoothScan(null)
        }
        scanTimeoutHandler?.postDelayed(scanTimeoutRunnable!!, 10000)
    }

    private fun stopBluetoothScan(result: MethodChannel.Result?) {
        if (!isScanning) {
            result?.success(true)
            return
        }

        isScanning = false

        // 停止BLE扫描
        try {
            bluetoothLeScanner?.stopScan(leScanCallback)
        } catch (e: SecurityException) {}
        bluetoothLeScanner = null

        // 停止经典蓝牙发现
        try {
            bluetoothAdapter?.cancelDiscovery()
        } catch (e: SecurityException) {}

        // 取消广播接收器
        try {
            unregisterReceiver(discoveryReceiver)
        } catch (e: IllegalArgumentException) {}

        // 取消超时
        scanTimeoutHandler?.removeCallbacks(scanTimeoutRunnable ?: return)
        scanTimeoutRunnable = null

        // 发送扫描完成事件
        bluetoothEventSink?.success(mapOf("type" to "scanComplete"))

        result?.success(true)
    }

    private val leScanCallback = @SuppressLint("MissingPermission") object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            if (device.address !in discoveredDevices) {
                discoveredDevices.add(device.address)
                val map = mutableMapOf<String, Any>(
                    "name" to (device.name ?: "未知设备"),
                    "address" to device.address,
                    "rssi" to result.rssi,
                    "type" to "BLE",
                    "isBonded" to (device.bondState == BluetoothDevice.BOND_BONDED)
                )
                bluetoothEventSink?.success(map)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            bluetoothEventSink?.success(mapOf("type" to "scanError", "error" to "BLE扫描失败: $errorCode"))
        }
    }

    private val discoveryReceiver = @SuppressLint("MissingPermission") object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    if (device != null && device.address !in discoveredDevices) {
                        discoveredDevices.add(device.address)
                        val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE).toInt()
                        val map = mutableMapOf<String, Any>(
                            "name" to (device.name ?: "未知设备"),
                            "address" to device.address,
                            "rssi" to rssi,
                            "type" to (device.type?.toString() ?: "CLASSIC"),
                            "isBonded" to (device.bondState == BluetoothDevice.BOND_BONDED)
                        )
                        bluetoothEventSink?.success(map)
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    // 经典蓝牙扫描完成，不停止BLE扫描
                }
            }
        }
    }

    private fun deviceToMap(device: BluetoothDevice): Map<String, Any> {
        return mapOf(
            "name" to (device.name ?: "未知设备"),
            "address" to device.address,
            "rssi" to 0,
            "type" to (device.type?.toString() ?: "CLASSIC"),
            "isBonded" to (device.bondState == BluetoothDevice.BOND_BONDED)
        )
    }

    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBluetoothPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT),
                1002
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.BLUETOOTH, Manifest.permission.BLUETOOTH_ADMIN, Manifest.permission.ACCESS_FINE_LOCATION),
                1002
            )
        }
    }

    // ==================== 语音输入 ====================

    private fun startVoiceRecognition(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("NO_PERMISSION", "缺少麦克风权限", null)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("UNAVAILABLE", "设备不支持语音识别，请先安装语音服务", null)
            return
        }
        if (speechRecognizer == null) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).also {
                it.setRecognitionListener(voiceListener)
            }
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            speechRecognizer?.startListening(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("START_FAILED", "语音识别启动失败: ${e.message}", null)
        }
    }

    private fun stopVoiceRecognition() {
        try {
            speechRecognizer?.stopListening()
        } catch (e: Exception) {
        }
        try {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
        } catch (e: Exception) {
        }
        speechRecognizer = null
    }

    private fun emitVoice(state: String, text: String? = null) {
        val payload = mutableMapOf<String, Any>("state" to state)
        if (text != null) payload["text"] = text
        runOnUiThread { voiceChannel?.invokeMethod("onVoiceEvent", payload) }
    }

    private val voiceListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = emitVoice("listening")
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() = emitVoice("processing")
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onError(error: Int) {
            emitVoice("error", voiceErrorMessage(error))
        }

        override fun onResults(results: Bundle?) {
            val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            if (text.isNullOrBlank()) {
                emitVoice("error", "未识别到语音内容")
            } else {
                emitVoice("result", text)
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            if (!text.isNullOrBlank()) emitVoice("partial", text)
        }
    }

    private fun voiceErrorMessage(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "录音出错，请重试"
        SpeechRecognizer.ERROR_CLIENT -> "语音识别已取消"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "缺少麦克风权限"
        SpeechRecognizer.ERROR_NETWORK -> "网络异常，请检查连接后重试"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "网络超时，请重试"
        SpeechRecognizer.ERROR_NO_MATCH -> "未识别到语音内容"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "识别服务忙，请稍后重试"
        SpeechRecognizer.ERROR_SERVER -> "语音识别服务异常"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "没有检测到说话，请重试"
        else -> "语音识别失败，请重试"
    }

    override fun onDestroy() {
        stopBluetoothScan(null)
        stopWifiScan(null)
        releaseWifiLock()
        stopGnssKeepAlive()
        stopGnssMonitoring()
        stopCompass()
        stopVoiceRecognition()
        super.onDestroy()
    }
}