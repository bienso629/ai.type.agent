package ai.type.agent.coder

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val BANK_LISTENER_CHANNEL = "ai_type_agent/bank_listener"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
