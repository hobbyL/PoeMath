package com.poemath.app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

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
            "getApkSignatureSha256" -> getApkSignatureSha256(result)
            "inspectApkSignature" -> inspectApkSignature(call, result)
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
            val file = when (val allowed = resolveUpdateApk(path)) {
                is UpdateApkResolution.Allowed -> allowed.file
                is UpdateApkResolution.NotFound ->
                    run {
                        result.error("FILE_NOT_FOUND", "安装包文件不存在: $path", null)
                        return
                    }
                is UpdateApkResolution.OutOfScope ->
                    run {
                        result.error(
                            "APK_PATH_NOT_ALLOWED",
                            "安装包路径不在允许的下载目录内",
                            null,
                        )
                        return
                    }
            }

            val archive = packageManager.getPackageArchiveInfo(file.absolutePath, 0)
            if (archive == null) {
                result.error("APK_UNREADABLE", "无法读取安装包信息", null)
                return
            }
            if (archive.packageName != packageName) {
                result.error(
                    "APK_PACKAGE_MISMATCH",
                    "安装包包名与应用不一致：${archive.packageName}",
                    null,
                )
                return
            }

            // 信任根是「当前已安装版本」的签名证书，随安装动态获取，
            // 不写入源码常量（密钥轮换无需改代码）。
            val installed = installedSignatures()
            val incoming = apkSignatures(file.absolutePath)
            if (installed.isEmpty() || incoming.isNullOrEmpty()) {
                result.error("APK_SIGNATURE_UNAVAILABLE", "无法读取签名信息，已阻止安装", null)
                return
            }
            // 集合交集而非全等：多签名者或 v1+v2+v3 混合签名时只要存在
            // 至少一个共同的可信证书即认为同源，避免误拒。
            if (incoming.intersect(installed).isEmpty()) {
                result.error(
                    "APK_SIGNATURE_MISMATCH",
                    "安装包签名与当前应用不一致，已阻止安装",
                    null,
                )
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

    // ---------- getApkSignatureSha256 / inspectApkSignature ----------
    //
    // 这两个方法让签名闸门可被独立观察与测试，并让 Dart 侧能在调用
    // installApk 之前给出「签名不一致」这一具体原因。原生 installApk
    // 内部仍会再比对一次（纵深防御：通道可被直接调用）。

    private fun getApkSignatureSha256(result: MethodChannel.Result) {
        try {
            result.success(installedSignatures().toList())
        } catch (e: Exception) {
            result.error("SIGNATURE_QUERY_ERROR", e.message, null)
        }
    }

    private fun inspectApkSignature(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "path is required", null)
            return
        }
        try {
            val signatures = apkSignatures(path)
            // 读不出签名时返回 null（而非空列表），让调用方与「无签名」区分。
            result.success(signatures?.toList())
        } catch (e: Exception) {
            result.error("SIGNATURE_QUERY_ERROR", e.message, null)
        }
    }

    // ---------- APK 路径与签名辅助 ----------

    /** `resolveUpdateApk` 的三态结果：文件不存在与路径越界必须分开报告。 */
    private sealed class UpdateApkResolution {
        data class Allowed(val file: File) : UpdateApkResolution()
        object NotFound : UpdateApkResolution()
        object OutOfScope : UpdateApkResolution()
    }

    /**
     * 只允许安装应用自己下载目录内的文件。
     *
     * 用 `canonicalFile`（等价 `getCanonicalPath()`）而非字符串前缀比较：
     * `../` 与符号链接都能绕过字符串比较，规范化不会。判据是「**直接**父目录
     * 等于允许目录」——下载器本来就只写这一层，没有理由接受子目录。
     */
    private fun resolveUpdateApk(path: String): UpdateApkResolution {
        val file = File(path)
        if (!file.exists() || !file.isFile) return UpdateApkResolution.NotFound
        val allowedDir = File(cacheDir, "poemath_update").canonicalFile
        val canonical = try {
            file.canonicalFile
        } catch (e: Exception) {
            return UpdateApkResolution.OutOfScope
        }
        val parent = canonical.parentFile ?: return UpdateApkResolution.OutOfScope
        return if (parent == allowedDir) {
            UpdateApkResolution.Allowed(canonical)
        } else {
            UpdateApkResolution.OutOfScope
        }
    }

    /**
     * 当前已安装应用的签名证书 SHA-256 集合（小写 hex）。
     *
     * `signingInfo == null`（未签名变体）返回空集，由调用方按「签名不可用」
     * 阻止安装，不静默放行。**不用** `signingCertificateHistory`——它含已轮换的
     * 旧证书，拿它做并集比对会让轮换前的旧签名继续被接受。
     */
    private fun installedSignatures(): Set<String> {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
        }
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            info.signatures
        }
        return signatures.orEmpty().map { sha256Hex(it.toByteArray()) }.toSet()
    }

    /**
     * 待安装 APK 的签名证书 SHA-256 集合；读不出返回 null。
     *
     * 也用于校验路径合法性之外的调用点（`inspectApkSignature`），因此不要求
     * 路径位于下载目录内 —— 「路径边界」由 `installApk` 单独把关。
     */
    private fun apkSignatures(path: String): Set<String>? {
        val info = packageManager.getPackageArchiveInfo(
            path,
            PackageManager.GET_SIGNING_CERTIFICATES,
        ) ?: return null
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            info.signatures
        }
        return signatures.orEmpty().map { sha256Hex(it.toByteArray()) }.toSet()
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }
}
