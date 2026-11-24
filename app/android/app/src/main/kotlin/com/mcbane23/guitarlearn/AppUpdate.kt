package com.mcbane23.guitarlearn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Tells Flutter which build is running and opens the Android installer for
/// a downloaded APK (see lib/update/app_update.dart).
class AppUpdate(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "guitar_learn/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "versionCode" -> result.success(versionCode())
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("no_path", "path is required", null)
                    } else {
                        result.success(install(File(path)))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun versionCode(): Int {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode
    }

    private fun install(apk: File): Boolean {
        if (!apk.isFile) return false
        return try {
            val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                putExtra(Intent.EXTRA_RETURN_RESULT, false)
            }
            if (intent.resolveActivity(context.packageManager) == null) return false
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
