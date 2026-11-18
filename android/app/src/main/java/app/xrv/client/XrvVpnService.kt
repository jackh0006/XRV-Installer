package app.xrv.client

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import hev.htproxy.TProxyService
import java.io.File
import kotlin.concurrent.thread

/**
 * System-wide TUN mode.
 *
 * The Go engine listens on loopback; hev-socks5-tunnel turns the Android TUN
 * file descriptor into SOCKS5 sessions. XRV's own process is excluded from the
 * VPN so the engine's outbound HTTPS long-poll can never loop through the
 * tunnel it just created. DNS is handled by mapdns: names are resolved by the
 * exit, never by the phone's local resolver.
 */
class XrvVpnService : VpnService() {
    companion object {
        const val ACTION_START = "app.xrv.client.action.START_VPN"
        const val ACTION_STOP = "app.xrv.client.action.STOP_VPN"
        const val NOTIFICATION_ID = 42
        private const val OWNER = "vpn"
        private const val TUN_ADDRESS = "198.18.0.1"
        private const val TUN_DNS = "198.18.0.2"
        private const val TUN_IPV6 = "fc00::1"
        private const val TUN_MTU = 1500

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: android.content.Context) {
            val intent = Intent(context, XrvVpnService::class.java).setAction(ACTION_START)
            androidx.core.content.ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: android.content.Context) {
            runCatching {
                context.startService(
                    Intent(context, XrvVpnService::class.java).setAction(ACTION_STOP)
                )
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var tun: ParcelFileDescriptor? = null
    private var hevStarted = false

    @Volatile
    private var shuttingDown = false
    private var worker: Thread? = null

    private val watchdog = object : Runnable {
        override fun run() {
            if (!isRunning || shuttingDown) return
            if (!TProxyService.TProxyIsRunning()) {
                fail(getString(R.string.error_tunnel_stopped))
                return
            }
            val stats = NetResults.traffic(
                runCatching { NativeBridge.stats() }.getOrNull()
            )
            val current = XrvState.read(this@XrvVpnService)
            if (stats != null) {
                XrvState.write(
                    this@XrvVpnService,
                    current.copy(txBytes = stats.up, rxBytes = stats.down)
                )
            }
            updateNotification(stats)
            handler.postDelayed(this, 2_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        XrvNotifications.ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                shutdown(writeStopped = true)
                return START_NOT_STICKY
            }
        }
        if (isRunning) return START_STICKY
        shuttingDown = false

        if (!startInForeground(getString(R.string.notification_starting_vpn))) {
            return START_NOT_STICKY
        }
        XrvState.starting(this, Mode.TUN)

        val profile = SecureProfileStore(this).load()
        if (profile == null) {
            fail(getString(R.string.error_no_profile))
            return START_NOT_STICKY
        }

        // Switching from proxy-only mode must never leave a second listener.
        runCatching { stopService(Intent(this, TunnelService::class.java)) }

        worker = thread(name = "xrv-vpn", isDaemon = true) {
            try {
                if (shuttingDown) return@thread
                var edge = XrvSettings.selectedGoogleIp(this)
                if (edge.isEmpty()) {
                    val report = EdgeProber.probeSync(XrvSettings.googleCandidates(this))
                    if (report.best != null) {
                        edge = report.best
                        XrvSettings.setSelectedGoogleIp(this, edge)
                        XrvLog.add("edge", "auto-selected $edge (${report.bestMs} ms)")
                    } else {
                        XrvLog.add("edge", "auto-probe failed: ${report.error ?: "no edge"}")
                    }
                }
                if (shuttingDown) return@thread
                val options = EngineOptions(
                    googleIp = edge,
                    coalesceMs = XrvSettings.coalesceMs(this),
                    idleSlots = XrvSettings.idleSlots(this, profile.deployments.size)
                )
                val port = Engine.start(profile, OWNER, options).getOrThrow()
                if (shuttingDown) {
                    Engine.stop(OWNER)
                    return@thread
                }
                val fd = establishTunnel()
                if (shuttingDown) {
                    runCatching { fd.close() }
                    Engine.stop(OWNER)
                    return@thread
                }
                tun = fd
                val config = writeHevConfig(port, profile)
                if (!TProxyService.TProxyStartService(config.absolutePath, fd.fd)) {
                    throw IllegalStateException(getString(R.string.error_tunnel_engine))
                }
                hevStarted = true
                if (shuttingDown) {
                    runCatching { TProxyService.TProxyStopService() }
                    hevStarted = false
                    runCatching { fd.close() }
                    tun = null
                    Engine.stop(OWNER)
                    return@thread
                }
                isRunning = true
                XrvState.running(this, Mode.TUN, port)
                XrvLog.add(
                    "vpn",
                    "established port=$port edge=${XrvSettings.selectedGoogleIp(this).ifEmpty { "default" }} per-app=${XrvSettings.perAppMode(this).name}/${XrvSettings.perAppPackages(this).size}"
                )
                updateNotification(null)
                handler.postDelayed(watchdog, 2_000)
            } catch (t: Throwable) {
                fail(t.message ?: getString(R.string.error_start_failed))
            }
        }
        return START_STICKY
    }

    private fun startInForeground(text: String): Boolean {
        val notification = XrvNotifications.build(
            this,
            getString(R.string.notification_vpn_title),
            text,
            XrvVpnService::class.java,
            ACTION_STOP
        )
        return try {
            Foreground.start(this, NOTIFICATION_ID, notification)
            true
        } catch (t: Throwable) {
            XrvState.failed(this, Mode.TUN, t.message ?: getString(R.string.error_start_failed))
            stopSelf()
            false
        }
    }

    private fun establishTunnel(): ParcelFileDescriptor {
        val configure = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = Builder()
            .setSession(getString(R.string.app_name))
            .setMtu(TUN_MTU)
            .setConfigureIntent(configure)
            .setBlocking(false)
            .addAddress(TUN_ADDRESS, 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(TUN_DNS)
            .addAddress(TUN_IPV6, 128)
            .addRoute("::", 0)

        // Keep XRV's own relay traffic out of its tunnel (except in include
        // mode, where the allow-list already excludes it).
        applyPerAppRules(builder)

        return builder.establish() ?: throw IllegalStateException(
            getString(R.string.error_vpn_denied)
        )
    }

    private fun applyPerAppRules(builder: Builder) {
        val mode = XrvSettings.perAppMode(this)
        if (mode != PerAppMode.INCLUDE) {
            builder.addDisallowedApplication(packageName)
        }
        if (mode == PerAppMode.ALL) return
        val selected = XrvSettings.perAppPackages(this)
        if (mode == PerAppMode.INCLUDE && selected.isEmpty()) {
            throw IllegalStateException(getString(R.string.error_no_per_app))
        }
        var added = 0
        for (pkg in selected) {
            if (pkg == packageName) continue
            try {
                if (mode == PerAppMode.INCLUDE) {
                    builder.addAllowedApplication(pkg)
                } else {
                    builder.addDisallowedApplication(pkg)
                }
                added++
            } catch (_: PackageManager.NameNotFoundException) {
                // The app was uninstalled after it was selected.
            }
        }
        if (mode == PerAppMode.INCLUDE && added == 0) {
            throw IllegalStateException(getString(R.string.error_no_per_app))
        }
    }

    private fun writeHevConfig(port: Int, profile: Profile): File {
        val file = File(filesDir, "xrv-tun.yml")
        file.writeText(
            buildString {
                appendLine("tunnel:")
                appendLine("  name: tun0")
                appendLine("  mtu: $TUN_MTU")
                appendLine("  multi-queue: false")
                appendLine("  ipv4: $TUN_ADDRESS")
                appendLine("  ipv6: '$TUN_IPV6'")
                appendLine("  icmp: 'off'")
                appendLine("socks5:")
                appendLine("  port: $port")
                appendLine("  address: 127.0.0.1")
                appendLine("  udp: 'udp'")
                if (profile.socksUser.isNotEmpty() && profile.socksPass.isNotEmpty()) {
                    appendLine("  username: '${profile.socksUser}'")
                    appendLine("  password: '${profile.socksPass}'")
                }
                appendLine("mapdns:")
                appendLine("  address: $TUN_DNS")
                appendLine("  port: 53")
                appendLine("  network: 100.64.0.0")
                appendLine("  netmask: 255.192.0.0")
                appendLine("  cache-size: 10000")
                appendLine("misc:")
                appendLine("  log-level: error")
                appendLine("  connect-timeout: 12000")
                appendLine("  tcp-read-write-timeout: 300000")
                appendLine("  udp-read-write-timeout: 60000")
                appendLine("  max-session-count: 256")
            }
        )
        return file
    }

    private fun updateNotification(stats: Traffic?) {
        val text = if (stats != null && (stats.up > 0 || stats.down > 0)) {
            getString(R.string.notification_vpn_stats, Format.bytes(stats.up), Format.bytes(stats.down))
        } else {
            getString(R.string.notification_vpn_text)
        }
        val notification = XrvNotifications.build(
            this,
            getString(R.string.notification_vpn_title),
            text,
            XrvVpnService::class.java,
            ACTION_STOP
        )
        runCatching {
            getSystemService(android.app.NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification)
        }
    }

    private fun fail(message: String) {
        XrvLog.add("vpn", "failed: $message")
        isRunning = false
        XrvState.failed(this, Mode.TUN, message)
        shutdown(writeStopped = false)
    }

    @Synchronized
    private fun shutdown(writeStopped: Boolean) {
        if (shuttingDown) return
        shuttingDown = true
        XrvLog.add("vpn", "shutting down")
        handler.removeCallbacksAndMessages(null)
        isRunning = false
        if (hevStarted) {
            runCatching { TProxyService.TProxyStopService() }
            hevStarted = false
        }
        runCatching { tun?.close() }
        tun = null
        Engine.stop(OWNER)
        val current = XrvState.read(this)
        if (writeStopped && current.mode == Mode.TUN && current.phase != Phase.ERROR) {
            XrvState.stopped(this)
        }
        Foreground.stop(this)
        stopSelf()
    }

    override fun onRevoke() {
        shutdown(writeStopped = true)
        super.onRevoke()
    }

    override fun onDestroy() {
        shutdown(writeStopped = true)
        super.onDestroy()
    }
}
