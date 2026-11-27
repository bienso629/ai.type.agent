package ai.type.agent.coder

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val BANK_LISTENER_CHANNEL = "ai_type_agent/bank_listener"
        private const val MEDIA_SAVER_CHANNEL = "ai_type_agent/media_saver"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SAVER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFileToPublicStorage" -> {
                    val sourcePath = call.argument<String>("sourcePath") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "download.bin"
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val kind = call.argument<String>("kind") ?: "file"
                    val mainHandler = Handler(Looper.getMainLooper())
                    Thread {
                        try {
                            val srcFile = File(sourcePath)
                            if (!srcFile.exists()) {
                                mainHandler.post {
                                    result.success(mapOf("ok" to false, "error" to "Tệp nguồn không tồn tại."))
                                }
                                return@Thread
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val collectionUri: Uri
                                val relativeDir: String
                                when (kind) {
                                    "image" -> {
                                        collectionUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                                        relativeDir = "${Environment.DIRECTORY_PICTURES}/AI Type Agent"
                                    }
                                    "video" -> {
                                        collectionUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                                        relativeDir = "${Environment.DIRECTORY_MOVIES}/AI Type Agent"
                                    }
                                    "audio" -> {
                                        collectionUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                                        relativeDir = "${Environment.DIRECTORY_MUSIC}/AI Type Agent"
                                    }
                                    else -> {
                                        collectionUri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                                        relativeDir = "${Environment.DIRECTORY_DOWNLOADS}/AI Type Agent"
                                    }
                                }
                                val values = ContentValues().apply {
                                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativeDir)
                                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                                val resolver = applicationContext.contentResolver
                                val insertedUri = resolver.insert(collectionUri, values)
                                if (insertedUri == null) {
                                    mainHandler.post {
                                        result.success(mapOf("ok" to false, "error" to "Không tạo được bản ghi MediaStore."))
                                    }
                                    return@Thread
                                }
                                try {
                                    FileInputStream(srcFile).use { input ->
                                        resolver.openOutputStream(insertedUri)?.use { output ->
                                            input.copyTo(output, 64 * 1024)
                                            output.flush()
                                        } ?: throw IllegalStateException("Không mở được luồng ghi MediaStore.")
                                    }
                                    val doneValues = ContentValues().apply {
                                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                                    }
                                    resolver.update(insertedUri, doneValues, null, null)
                                    mainHandler.post {
                                        result.success(
                                            mapOf(
                                                "ok" to true,
                                                "uri" to insertedUri.toString(),
                                                "displayPath" to "$relativeDir/$fileName",
                                            )
                                        )
                                    }
                                } catch (e: Exception) {
                                    try {
                                        resolver.delete(insertedUri, null, null)
                                    } catch (_: Exception) {}
                                    mainHandler.post {
                                        result.success(mapOf("ok" to false, "error" to (e.message ?: "Lỗi ghi tệp.")))
                                    }
                                }
                            } else {
                                @Suppress("DEPRECATION")
                                val pubDir = File(
                                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                                    "AI Type Agent"
                                )
                                if (!pubDir.exists()) pubDir.mkdirs()
                                val destFile = File(pubDir, fileName)
                                FileInputStream(srcFile).use { input ->
                                    FileOutputStream(destFile).use { output ->
                                        input.copyTo(output, 64 * 1024)
                                        output.flush()
                                    }
                                }
                                MediaScannerConnection.scanFile(
                                    applicationContext,
                                    arrayOf(destFile.absolutePath),
                                    arrayOf(mimeType),
                                    null
                                )
                                mainHandler.post {
                                    result.success(
                                        mapOf(
                                            "ok" to true,
                                            "uri" to destFile.absolutePath,
                                            "displayPath" to destFile.absolutePath,
                                        )
                                    )
                                }
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.success(mapOf("ok" to false, "error" to (e.message ?: "Lỗi lưu tệp.")))
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BANK_LISTENER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> {
                    result.success(BankNotificationListenerService.getStatusMap(this))
                }

                "openNotificationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_SETTINGS_ERR", e.message, null)
                    }
                }

                "openAppDetailsSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_APP_DETAILS_ERR", e.message, null)
                    }
                }

                "saveConfig" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val webhookUrl = call.argument<String>("webhookUrl")
                        ?: BankNotificationListenerService.DEFAULT_WEBHOOK_URL
                    val webhookSecret = call.argument<String>("webhookSecret")
                    val allowedSenders = call.argument<String>("allowedSenders")
                        ?: BankNotificationListenerService.DEFAULT_ALLOWED_SENDERS
                    val listenSmsApps = call.argument<Boolean>("listenSmsApps") ?: true

                    BankNotificationListenerService.saveConfig(
                        context = this,
                        enabled = enabled,
                        webhookUrl = webhookUrl,
                        webhookSecret = webhookSecret,
                        allowedSenders = allowedSenders,
                        listenSmsApps = listenSmsApps,
                    )
                    result.success(BankNotificationListenerService.getStatusMap(this))
                }

                "clearLogs" -> {
                    BankNotificationListenerService.clearLogs(this)
                    result.success(true)
                }

                "sendTestForward" -> {
                    val sender = call.argument<String>("sender") ?: "VCB Digibank"
                    val message = call.argument<String>("message") ?: ""
                    if (message.isBlank()) {
                        result.error("EMPTY_MSG", "Nội dung kiểm thử không được để trống.", null)
                        return@setMethodCallHandler
                    }
                    val mainHandler = Handler(Looper.getMainLooper())
                    BankNotificationListenerService.forwardToServerAsync(
                        context = this,
                        pkg = "com.VCB",
                        sender = sender,
                        message = message,
                    ) { resMap ->
                        mainHandler.post {
                            result.success(resMap)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
