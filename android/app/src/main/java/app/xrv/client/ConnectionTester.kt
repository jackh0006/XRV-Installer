package app.xrv.client

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

object EdgeProber {
    private val main = Handler(Looper.getMainLooper())

    fun probeSync(candidates: List<String>): EdgeReport {
        val ips = candidates.filter { IpUtils.isIPv4(it) }.distinct().take(32)
        if (ips.isEmpty()) {
            return EdgeReport(emptyList(), null, 0, "Add at least one valid IPv4 address.")
        }
        val error = NativeBridge.loadError
        if (error != null) {
            return EdgeReport(emptyList(), null, 0, "Native engine unavailable: $error")
        }
        val request = JSONObject().put("ips", JSONArray(ips)).put("timeoutMs", 6_000)
        val raw = runCatching { NativeBridge.probeEdges(request.toString()) }
            .getOrElse { t ->
                return EdgeReport(
                    emptyList(), null, 0,
                    t.message ?: "Google-edge probe failed"
                )
            }
        return NetResults.edges(raw)
    }

    fun run(candidates: List<String>, callback: (EdgeReport) -> Unit) {
        thread(name = "xrv-edge-probe", isDaemon = true) {
            val report = probeSync(candidates)
            main.post { callback(report) }
        }
    }
}

object ConnectionTester {
    data class Result(
        val ok: Boolean,
        val exitIp: String,
        val realIp: String?,
        val ms: Long,
        val error: String?
    )

    private val main = Handler(Looper.getMainLooper())

    fun run(
        context: Context,
        port: Int,
        user: String,
        pass: String,
        callback: (Result) -> Unit
    ) {
        val appContext = context.applicationContext
        thread(name = "xrv-connection-test", isDaemon = true) {
            val loadError = NativeBridge.loadError
            if (loadError != null) {
                main.post { callback(Result(false, "", null, 0, "Native engine unavailable: $loadError")) }
                return@thread
            }
            val request = JSONObject()
                .put("port", port)
                .put("user", user)
                .put("pass", pass)
            val raw = runCatching { NativeBridge.testConnection(request.toString()) }
                .getOrElse { t ->
                    main.post {
                        callback(
                            Result(
                                false, "", null, 0,
                                t.message ?: "Tunnel test failed"
                            )
                        )
                    }
                    return@thread
                }
            val tunnel = NetResults.tunnel(raw)
            val realIp = directIp()
            main.post {
                callback(
                    Result(
                        ok = tunnel.ok,
                        exitIp = tunnel.exitIp,
                        realIp = realIp,
                        ms = tunnel.ms,
                        error = tunnel.error
                    )
                )
            }
        }
    }

    /** Fetches the real IP directly. XRV excludes itself from its own VPN, so
     *  this remains the carrier/phone address rather than the tunnel exit. */
    private fun directIp(): String? = try {
        val connection = URL("https://api.ipify.org").openConnection() as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 8_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", "XRV-Android")
        try {
            if (connection.responseCode == 200) {
                connection.inputStream.bufferedReader().use { it.readText() }
                    .trim()
                    .takeIf { it.isNotEmpty() && it.length <= 64 }
            } else {
                null
            }
        } finally {
            connection.disconnect()
        }
    } catch (_: Exception) {
        null
    }
}
