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
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
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
    private val LOCATION_CHANNEL = "com.huhuashizhe/location"
    private val BLUETOOTH_CHANNEL = "com.huhuashizhe/bluetooth"
    private val BLUETOOTH_EVENT_CHANNEL = "com.huhuashizhe/bluetooth_events"
    private var locationResult: MethodChannel.Result? = null
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null
    private var bestLocation: Location? = null
    private var locationTimeoutHandler: Handler? = null
    private var locationTimeoutRunnable: Runnable? = null

    // 蓝牙相关
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothEventSink: EventChannel.EventSink? = null
    private var isScanning = false
    private var scanTimeoutHandler: Handler? = null
    private var scanTimeoutRunnable: Runnable? = null
    private val discoveredDevices = mutableSetOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
            // 权限未授予时，尝试返回任意缓存位置作为回退
            val anyLocation = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                ?: locationManager?.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
            if (anyLocation != null) {
                result.success(mapOf("lat" to anyLocation.latitude, "lng" to anyLocation.longitude))
            } else {
                result.success(null)
            }
            return
        }

        // 优化策略：先立即返回缓存位置（快速定位），再后台监听更高精度
        val cached = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            ?: locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            ?: locationManager?.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)

        if (cached != null) {
            // 有缓存位置，立即返回，不阻塞UI
            result.success(mapOf("lat" to cached.latitude, "lng" to cached.longitude))
            // 后台静默更新到更精确位置（下次请求时可用）
            updateCacheInBackground()
            return
        }

        // 无缓存位置：启动监听，尽快返回第一个可用定位
        locationResult = result
        bestLocation = null

        locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (bestLocation == null || location.accuracy < bestLocation!!.accuracy) {
                    bestLocation = location
                }
                // 收到第一个定位（任意精度）立即返回，不再等待高精度
                locationResult?.success(mapOf("lat" to location.latitude, "lng" to location.longitude))
                locationResult = null
                cleanupLocation()
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                locationResult?.success(null)
                locationResult = null
                cleanupLocation()
            }
        }

        // 5秒超时：缩短等待时间
        locationTimeoutHandler = Handler(Looper.getMainLooper())
        locationTimeoutRunnable = Runnable {
            if (locationResult != null) {
                locationResult?.success(null)
                locationResult = null
                cleanupLocation()
            }
        }
        locationTimeoutHandler?.postDelayed(locationTimeoutRunnable!!, 5000)

        // 同时请求GPS和网络定位
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {
        }
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {
        }
    }

    /// 后台静默更新GPS缓存，不阻塞调用方
    private fun updateCacheInBackground() {
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
        } catch (e: Exception) {
        }
    }

    private fun cleanupLocation() {
        locationTimeoutHandler?.removeCallbacks(locationTimeoutRunnable ?: return)
        locationTimeoutRunnable = null
        locationListener?.let { locationManager?.removeUpdates(it) }
        locationListener = null
        locationResult = null
        bestLocation = null
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

    override fun onDestroy() {
        stopBluetoothScan(null)
        super.onDestroy()
    }
}