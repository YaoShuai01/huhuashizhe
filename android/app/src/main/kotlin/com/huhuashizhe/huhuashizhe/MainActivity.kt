package com.huhuashizhe.huhuashizhe

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val INSTALLER_CHANNEL = "com.huhuashizhe/apk_installer"
    private val LOCATION_CHANNEL = "com.huhuashizhe/location"
    private var locationResult: MethodChannel.Result? = null
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // APK安装通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> installApk(call.argument("path") ?: "", result)
                else -> result.notImplemented()
            }
        }

        // GPS定位通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocation" -> getCurrentLocation(result)
                else -> result.notImplemented()
            }
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
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
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
            // 权限未授予，返回null让Flutter端处理
            result.success(null)
            return
        }

        // 先尝试获取最后一次已知位置
        val lastLocation = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            ?: locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)

        if (lastLocation != null && (System.currentTimeMillis() - lastLocation.time) < 5 * 60 * 1000) {
            // 5分钟内的缓存位置可用
            val map = mapOf(
                "lat" to lastLocation.latitude,
                "lng" to lastLocation.longitude
            )
            result.success(map)
            return
        }

        // 请求单次位置更新
        locationResult = result
        locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                locationResult?.success(mapOf("lat" to location.latitude, "lng" to location.longitude))
                cleanupLocation()
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                locationResult?.success(null)
                cleanupLocation()
            }
        }

        try {
            locationManager?.requestSingleUpdate(
                LocationManager.GPS_PROVIDER, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            // GPS不可用，尝试网络定位
            try {
                locationManager?.requestSingleUpdate(
                    LocationManager.NETWORK_PROVIDER, locationListener!!, Looper.getMainLooper()
                )
            } catch (e2: Exception) {
                result.success(null)
                cleanupLocation()
            }
        }
    }

    private fun cleanupLocation() {
        locationListener?.let { locationManager?.removeUpdates(it) }
        locationListener = null
        locationResult = null
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
    }
}