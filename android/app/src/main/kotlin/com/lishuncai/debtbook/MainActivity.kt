package com.lishuncai.debtbook

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.lishuncai.debtbook/update"
        ).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("BAD_ARG", "缺少 path 参数", null)
                    return@setMethodCallHandler
                }
                try {
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.updateProvider", File(path)
                    )
                    startActivity(
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                            )
                        }
                    )
                    result.success(true)
                } catch (e: Exception) {
                    result.error(
                        "INSTALL_LAUNCH_FAILED",
                        "${e.javaClass.simpleName}: ${e.message}",
                        null
                    )
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
