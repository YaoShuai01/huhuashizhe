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
                "getDownloadDir" -> getDownloadDir(result)
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

        // 返回任意缓存位置（不限时间），同时请求新位置
        val cachedLocation = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            ?: locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            ?: locationManager?.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)

        if (cachedLocation != null) {
            result.success(mapOf("lat" to cachedLocation.latitude, "lng" to cachedLocation.longitude))
        }

        // 同时请求更精确的位置更新
        locationResult = if (cachedLocation != null) null else result
        locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                // 如果之前没返回过，现在返回
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

        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            try {
                locationManager?.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
                )
            } catch (e2: Exception) {
                if (cachedLocation == null) {
                    result.success(null)
                }
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