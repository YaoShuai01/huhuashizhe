package com.huhuashizhe.huhuashizhe

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.huhuashizhe/apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    try {
                        val path = call.argument<String>("path") ?: ""
                        if (path.isEmpty()) {
                            result.error("INVALID_PATH", "APK路径为空", null)
                            return@setMethodCallHandler
                        }

                        val file = java.io.File(path)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK文件不存在: $path", null)
                            return@setMethodCallHandler
                        }

                        // Android 7.0+ 需要使用 FileProvider
                        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            // 使用兼容的URI方案（允许从文件安装）
                            androidx.core.content.FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file
                            )
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
                else -> result.notImplemented()
            }
        }
    }
}
