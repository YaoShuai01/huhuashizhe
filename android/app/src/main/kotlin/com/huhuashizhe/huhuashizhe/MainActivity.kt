package com.huhuashizhe.huhuashizhe

import android.Manifest
import android.content.Intent
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
    private var bestLocation: Location? = null
    private var locationTimeoutHandler: Handler? = null
    private var locationTimeoutRunnable: Runnable? = null

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

        // 新策略：等待高精度新定位，不再立即返回缓存位置
        locationResult = result
        bestLocation = null

        locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                // 跟踪最优位置（精度最高的）
                if (bestLocation == null || location.accuracy < bestLocation!!.accuracy) {
                    bestLocation = location
                }
                // 精度达到30米以内，立即返回
                if (location.accuracy < 30.0f) {
                    locationResult?.success(mapOf("lat" to location.latitude, "lng" to location.longitude))
                    locationResult = null
                    cleanupLocation()
                }
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                locationResult?.success(null)
                locationResult = null
                cleanupLocation()
            }
        }

        // 10秒超时：返回最优可用位置，或缓存回退
        locationTimeoutHandler = Handler(Looper.getMainLooper())
        locationTimeoutRunnable = Runnable {
            if (locationResult != null) {
                if (bestLocation != null) {
                    locationResult?.success(mapOf("lat" to bestLocation!!.latitude, "lng" to bestLocation!!.longitude))
                } else {
                    val cached = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                        ?: locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                        ?: locationManager?.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
                    if (cached != null) {
                        locationResult?.success(mapOf("lat" to cached.latitude, "lng" to cached.longitude))
                    } else {
                        locationResult?.success(null)
                    }
                }
                locationResult = null
                cleanupLocation()
            }
        }
        locationTimeoutHandler?.postDelayed(locationTimeoutRunnable!!, 10000)

        // 同时请求GPS和网络定位
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            // GPS不可用，尝试网络定位
        }
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER, 0L, 0f, locationListener!!, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            // 网络定位也不可用
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
    }
}