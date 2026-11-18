package app.xrv.client

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.content.ContextCompat
import kotlin.concurrent.thread

/**
 * Proxy-only mode: a foreground service that exposes the encrypted relay as a
 * SOCKS5 listener on 127.0.0.1. It never creates a VPN interface, so it can
 * coexist with another VPN app that is already active.
 */
class TunnelService : Service() {
    companion object {
        const val ACTION_START = "app.xrv.client.action.START_PROXY"
        const val ACTION_STOP = "app.xrv.client.action.STOP_PROXY"
        const val NOTIFICATION_ID = 41
        private const val OWNER = "proxy"

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, TunnelService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            runCatching {
                context.startService(
                    Intent(context, TunnelService::class.java).setAction(ACTION_STOP)
                )
            }
        }
    }

    private var worker: Thread? = null
    private val statsHandler = Handler(Looper.getMainLooper())
    private var activePort = 0

    private val statsTick = object : Runnable {
        override fun run() {
            if (!isRunning) return
            val stats = NetResults.traffic(
                runCatching { NativeBridge.stats() }.getOrNull()
            )
            if (stats != null) {
                val current = XrvState.read(this@TunnelService)
                XrvState.write(
                    this@TunnelService,
                    current.copy(txBytes = stats.up, rxBytes = stats.down)
                )
                updateNotification(activePort, stats)
            } else {
                updateNotification(activePort, null)
            }
            statsHandler.postDelayed(this, 2_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        XrvNotifications.ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutdown()
            return START_NOT_STICKY
        }
        if (isRunning) return START_STICKY

        if (!startInForeground(getString(R.string.notification_starting_proxy))) {
            return START_NOT_STICKY
        }
        XrvState.starting(this, Mode.PROXY)

        val profile = SecureProfileStore(this).load()
        if (profile == null) {
            fail(getString(R.string.error_no_profile))
            return START_NOT_STICKY
        }

        worker = thread(name = "xrv-proxy", isDaemon = true) {
            if (!isRunning) return@thread
            val options = EngineOptions(
                googleIp = XrvSettings.selectedGoogleIp(this),
                coalesceMs = XrvSettings.coalesceMs(this),
                idleSlots = XrvSettings.idleSlots(this, profile.deployments.size)
            )
            Engine.start(profile, OWNER, options)
                .onSuccess { port ->
                    if (!isRunning) {
                        Engine.stop(OWNER)
                        return@onSuccess
                    }
                    activePort = port
                    updateNotification(port, null)
                    XrvState.running(this, Mode.PROXY, port)
                    XrvLog.add("proxy", "listening on 127.0.0.1:$port")
                    statsHandler.removeCallbacks(statsTick)
                    statsHandler.postDelayed(statsTick, 1_000)
                }
                .onFailure { fail(it.message ?: getString(R.string.error_start_failed)) }
        }
        return START_STICKY
    }

    private fun startInForeground(text: String): Boolean {
        val notification = XrvNotifications.build(
            this,
            getString(R.string.notification_proxy_title),
            text,
            TunnelService::class.java,
            ACTION_STOP
        )
        return try {
            Foreground.start(this, NOTIFICATION_ID, notification)
            isRunning = true
            true
        } catch (t: Throwable) {
            isRunning = false
            XrvState.failed(this, Mode.PROXY, t.message ?: getString(R.string.error_start_failed))
            stopSelf()
            false
        }
    }

    private fun updateNotification(port: Int, stats: Traffic?) {
        val text = if (stats != null && (stats.up > 0 || stats.down > 0)) {
            getString(
                R.string.notification_proxy_stats,
                getString(R.string.notification_proxy_text, port),
                Format.bytes(stats.up),
                Format.bytes(stats.down)
            )
        } else {
            getString(R.string.notification_proxy_text, port)
        }
        val notification = XrvNotifications.build(
            this,
            getString(R.string.notification_proxy_title),
            text,
            TunnelService::class.java,
            ACTION_STOP
        )
        runCatching {
            getSystemService(android.app.NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification)
        }
    }

    private fun fail(message: String) {
        XrvLog.add("proxy", "failed: $message")
        isRunning = false
        statsHandler.removeCallbacks(statsTick)
        Engine.stop(OWNER)
        XrvState.failed(this, Mode.PROXY, message)
        Foreground.stop(this)
        stopSelf()
    }

    private fun shutdown() {
        XrvLog.add("proxy", "shutdown requested")
        val wasRunning = isRunning || worker != null
        isRunning = false
        statsHandler.removeCallbacks(statsTick)
        worker = null
        Engine.stop(OWNER)
        if (wasRunning || XrvState.read(this).mode == Mode.PROXY) {
            XrvState.stopped(this)
        }
        Foreground.stop(this)
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        statsHandler.removeCallbacks(statsTick)
        Engine.stop(OWNER)
        val current = XrvState.read(this)
        if (current.mode == Mode.PROXY && current.phase != Phase.ERROR) {
            XrvState.stopped(this)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
