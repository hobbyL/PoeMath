package com.poemath.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "com.poemath.app/app_update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAppVersion" -> getAppVersion(result)
            "inspectApk" -> inspectApk(call, result)
            "canRequestPackageInstalls" -> canRequestPackageInstalls(result)
            "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
            "installApk" -> installApk(call, result)
            else -> result.notImplemented()
        }
    }

    // ---------- getAppVersion ----------

    private fun getAppVersion(result: MethodChannel.Result) {
        try {
            val pm = packageManager
            val info = pm.getPackageInfo(packageName, 0)
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            result.success(
                mapOf(
                    "packageName" to packageName,
                    "versionName" to (info.versionName ?: ""),
                    "versionCode" to versionCode,
                ),
            )
        } catch (e: Exception) {
            result.error("GET_VERSION_ERROR", e.message, null)
        }
    }

    // ---------- inspectApk ----------

    private fun inspectApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "path is required", null)
            return
        }
        try {
            val pm = packageManager
            val info = pm.getPackageArchiveInfo(path, 0)
            if (info == null) {
                result.success(null)
                return
            }
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            result.success(
                mapOf(
                    "packageName" to (info.packageName ?: ""),
                    "versionName" to (info.versionName ?: ""),
                    "versionCode" to versionCode,
                ),
            )
        } catch (e: Exception) {
            result.error("INSPECT_APK_ERROR", e.message, null)
        }
    }

    // ---------- canRequestPackageInstalls ----------

    private fun canRequestPackageInstalls(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            result.success(packageManager.canRequestPackageInstalls())
        } else {
            // Android 7 及以下不需要此权限
            result.success(true)
        }
    }

    // ---------- openInstallPermissionSettings ----------

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
                startActivity(intent)
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("PERMISSION_SETTINGS_ERROR", e.message, null)
        }
    }

    // ---------- installApk ----------

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "path is required", null)
            return
        }
        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "安装包文件不存在: $path", null)
                return
            }

            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("INSTALL_ERROR", e.message, null)
        }
    }
}
