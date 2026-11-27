package ai.type.agent.coder

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Dịch vụ lắng nghe trực tiếp thông báo của VCB Digibank (và tin nhắn SMS Vietcombank)
 * ngay bên trong Agent Coder Android, chuyển thẳng về webhook /v1/payment/bank-sms
 * mà không cần cài thêm MacroDroid hay bất kỳ app bên thứ 3 nào.
 */
class BankNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "BankNotifListener"
        const val PREFS_NAME = "aitype_bank_listener_prefs"
        const val KEY_ENABLED = "enabled"
        const val KEY_WEBHOOK_URL = "webhook_url"
        const val KEY_WEBHOOK_SECRET = "webhook_secret"
        const val KEY_ALLOWED_SENDERS = "allowed_senders"
        const val KEY_LISTEN_SMS_APPS = "listen_sms_apps"
        const val KEY_LOGS = "forward_logs"
        const val DEFAULT_WEBHOOK_URL = "https://apiv3.type.vn/v1/payment/bank-sms"
        const val DEFAULT_ALLOWED_SENDERS = "Vietcombank,VCB,VCB Digibank"

        private val VCB_PACKAGES = setOf(
            "com.vcb",
            "com.vcb.digibank",
            "com.vietcombank.digibank",
        )

        private val SMS_PACKAGES = setOf(
            "com.google.android.apps.messaging",
            "com.samsung.android.messaging",
            "com.android.mms",
            "com.miui.mms",
            "com.oneplus.mms",
            "com.oppo.mms",
            "com.vivo.message",
            "com.huawei.message",
            "com.sonyericsson.conversations",
            "com.asus.message",
        )

        private val executor = Executors.newSingleThreadExecutor()
        private val recentHashes = ConcurrentHashMap<String, Long>()
        private const val DEDUP_WINDOW_MS = 60_000L

        fun isPermissionGranted(context: Context): Boolean {
            val enabledListeners = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            val expectedComponent = ComponentName(
                context,
                BankNotificationListenerService::class.java
            ).flattenToString()
            return enabledListeners.split(":").any { item ->
                val trimmed = item.trim()
                trimmed.equals(expectedComponent, ignoreCase = true) ||
                    trimmed.contains(context.packageName, ignoreCase = true) &&
                    trimmed.contains("BankNotificationListenerService", ignoreCase = true)
            }
        }

        fun requestServiceRebind(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isPermissionGranted(context)) {
                try {
                    val cn = ComponentName(context, BankNotificationListenerService::class.java)
                    requestRebind(cn)
                } catch (e: Exception) {
                    Log.w(TAG, "requestRebind failed: ${e.message}")
                }
            }
        }

        fun getStatusMap(context: Context): Map<String, Any> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val logsJson = prefs.getString(KEY_LOGS, "[]") ?: "[]"
            val logsList = mutableListOf<Map<String, Any>>()
            try {
                val arr = JSONArray(logsJson)
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    logsList.add(
                        mapOf(
                            "time" to obj.optString("time", ""),
                            "pkg" to obj.optString("pkg", ""),
                            "sender" to obj.optString("sender", ""),
                            "message" to obj.optString("message", ""),
                            "httpCode" to obj.optInt("httpCode", 0),
                            "ok" to obj.optBoolean("ok", false),
                            "response" to obj.optString("response", ""),
                        )
                    )
                }
            } catch (_: Exception) {}

            val secret = prefs.getString(KEY_WEBHOOK_SECRET, "") ?: ""
            return mapOf(
                "isAndroid" to true,
                "permissionGranted" to isPermissionGranted(context),
                "enabled" to prefs.getBoolean(KEY_ENABLED, false),
                "webhookUrl" to (prefs.getString(KEY_WEBHOOK_URL, DEFAULT_WEBHOOK_URL) ?: DEFAULT_WEBHOOK_URL),
                "hasSecret" to secret.isNotBlank(),
                "allowedSenders" to (prefs.getString(KEY_ALLOWED_SENDERS, DEFAULT_ALLOWED_SENDERS) ?: DEFAULT_ALLOWED_SENDERS),
                "listenSmsApps" to prefs.getBoolean(KEY_LISTEN_SMS_APPS, true),
                "sdkInt" to Build.VERSION.SDK_INT,
                "logs" to logsList,
            )
        }

        fun saveConfig(
            context: Context,
            enabled: Boolean,
            webhookUrl: String,
            webhookSecret: String?,
            allowedSenders: String,
            listenSmsApps: Boolean,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putBoolean(KEY_ENABLED, enabled)
                .putString(KEY_WEBHOOK_URL, webhookUrl.trim().ifEmpty { DEFAULT_WEBHOOK_URL })
                .putString(KEY_ALLOWED_SENDERS, allowedSenders.trim().ifEmpty { DEFAULT_ALLOWED_SENDERS })
                .putBoolean(KEY_LISTEN_SMS_APPS, listenSmsApps)

            if (webhookSecret != null && webhookSecret.trim().isNotEmpty()) {
                editor.putString(KEY_WEBHOOK_SECRET, webhookSecret.trim())
            }
            editor.apply()

            if (enabled) {
                requestServiceRebind(context)
            }
        }

        fun clearLogs(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_LOGS, "[]")
                .apply()
        }

        private fun appendLog(
            context: Context,
            pkg: String,
            sender: String,
            message: String,
            httpCode: Int,
            ok: Boolean,
            response: String,
        ) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val existing = JSONArray(prefs.getString(KEY_LOGS, "[]") ?: "[]")
                val next = JSONArray()
                val nowStr = SimpleDateFormat("dd/MM HH:mm:ss", Locale.getDefault()).format(Date())

                val entry = JSONObject().apply {
                    put("time", nowStr)
                    put("pkg", pkg)
                    put("sender", sender.take(80))
                    put("message", message.take(400))
                    put("httpCode", httpCode)
                    put("ok", ok)
                    put("response", response.take(260))
                }
                next.put(entry)

                val maxKeep = 29
                for (i in 0 until minOf(existing.length(), maxKeep)) {
                    next.put(existing.get(i))
                }
                prefs.edit().putString(KEY_LOGS, next.toString()).apply()
            } catch (e: Exception) {
                Log.e(TAG, "appendLog error: ${e.message}")
            }
        }

        fun forwardToServerAsync(
            context: Context,
            pkg: String,
            sender: String,
            message: String,
            onDone: ((Map<String, Any>) -> Unit)? = null,
        ) {
            val appCtx = context.applicationContext
            executor.execute {
                val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val webhookUrl = (prefs.getString(KEY_WEBHOOK_URL, DEFAULT_WEBHOOK_URL) ?: DEFAULT_WEBHOOK_URL).trim()
                val secret = (prefs.getString(KEY_WEBHOOK_SECRET, "") ?: "").trim()

                if (secret.isEmpty()) {
                    val err = "Chưa có khóa X-Bank-Webhook-Secret trong bộ nhớ ứng dụng."
                    appendLog(appCtx, pkg, sender, message, 0, false, err)
                    onDone?.invoke(mapOf("ok" to false, "httpCode" to 0, "response" to err))
                    return@execute
                }

                var httpCode = 0
                var responseBody = ""
                var ok = false
                try {
                    val conn = (URL(webhookUrl).openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        connectTimeout = 15_000
                        readTimeout = 15_000
                        doOutput = true
                        setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                        setRequestProperty("Accept", "application/json")
                        setRequestProperty("X-Bank-Webhook-Secret", secret)
                    }

                    val body = JSONObject().apply {
                        put("sender", sender)
                        put("message", message)
                    }.toString()

                    OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                        writer.write(body)
                        writer.flush()
                    }

                    httpCode = conn.responseCode
                    val stream = if (httpCode in 200..299) conn.inputStream else conn.errorStream
                    if (stream != null) {
                        BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { br ->
                            responseBody = br.readText()
                        }
                    }
                    conn.disconnect()
                    ok = httpCode in 200..299
                } catch (e: Exception) {
                    responseBody = e.message ?: e.toString()
                    Log.e(TAG, "Forward error: $responseBody")
                }

                appendLog(appCtx, pkg, sender, message, httpCode, ok, responseBody)
                onDone?.invoke(
                    mapOf(
                        "ok" to ok,
                        "httpCode" to httpCode,
                        "response" to responseBody,
                    )
                )
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "BankNotificationListenerService connected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return
        val secret = (prefs.getString(KEY_WEBHOOK_SECRET, "") ?: "").trim()
        if (secret.isEmpty()) return

        val notification = sbn.notification ?: return
        // Bỏ qua thông báo gom nhóm (group summary) để tránh trùng lặp
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim().orEmpty()
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.mapNotNull { it?.toString()?.trim() }
            ?.filter { it.isNotEmpty() }
            ?.joinToString(" ")
            .orEmpty()

        val bodyText = when {
            bigText.isNotEmpty() -> bigText
            lines.isNotEmpty() -> lines
            text.isNotEmpty() -> text
            else -> subText
        }
        if (bodyText.length < 8) return

        val pkgLower = pkg.lowercase(Locale.ROOT)
        val isVcbApp = VCB_PACKAGES.contains(pkgLower) ||
            pkgLower == "com.vcb" ||
            pkgLower.contains("vietcombank") ||
            pkgLower.startsWith("com.vcb.")

        val listenSmsApps = prefs.getBoolean(KEY_LISTEN_SMS_APPS, true)
        val isSmsApp = listenSmsApps && (
            SMS_PACKAGES.contains(pkgLower) ||
                pkgLower.contains("messaging") ||
                pkgLower.endsWith(".mms")
        )

        if (!isVcbApp && !isSmsApp) return

        val allowedCsv = prefs.getString(KEY_ALLOWED_SENDERS, DEFAULT_ALLOWED_SENDERS) ?: DEFAULT_ALLOWED_SENDERS
        val allowedKeywords = allowedCsv.split(",")
            .map { it.trim().lowercase(Locale.ROOT) }
            .filter { it.isNotEmpty() }

        val fullMessage = if (title.isNotEmpty() && !bodyText.contains(title, ignoreCase = true)) {
            "$title: $bodyText"
        } else {
            bodyText
        }

        val sender: String = if (isVcbApp) {
            "VCB Digibank"
        } else {
            val titleLower = title.lowercase(Locale.ROOT)
            val msgLower = fullMessage.lowercase(Locale.ROOT)
            val matchedAllowed = allowedKeywords.isEmpty() || allowedKeywords.any { kw ->
                titleLower.contains(kw) || msgLower.contains(kw)
            }
            if (!matchedAllowed) return
            title.ifBlank { "Vietcombank" }
        }

        // Chỉ chuyển tiếp thông báo liên quan đến biến động số dư / cộng tiền / mã AITYP
        val looksLikeBalanceAlert = fullMessage.contains("+") ||
            fullMessage.contains("AITYP", ignoreCase = true) ||
            fullMessage.contains("VND", ignoreCase = true) ||
            fullMessage.contains("VNĐ", ignoreCase = true) ||
            fullMessage.contains("SD TK", ignoreCase = true)
        if (!looksLikeBalanceAlert) return

        // Chống gửi trùng trong 60 giây
        val hash = sha256("$pkgLower|$sender|$fullMessage")
        val now = System.currentTimeMillis()
        recentHashes.entries.removeIf { now - it.value > DEDUP_WINDOW_MS }
        val prevTs = recentHashes.putIfAbsent(hash, now)
        if (prevTs != null && (now - prevTs) <= DEDUP_WINDOW_MS) {
            return
        }

        Log.i(TAG, "Forwarding Vietcombank alert from $pkg ($sender)")
        forwardToServerAsync(this, pkg, sender, fullMessage)
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
