package app.xrv.client

import android.content.Context

/** How the VPN decides which apps use the tunnel. */
enum class PerAppMode { ALL, INCLUDE, EXCLUDE }

/** Non-secret preferences shared by the activity and the services. */
object XrvSettings {
    private const val PREFS = "xrv.settings.v1"
    private const val K_MODE = "mode"
    private const val K_PORT = "port"
    private const val K_VPN_EXPLAINED = "vpn_explained"
    private const val K_PER_APP_MODE = "per_app_mode"
    private const val K_PER_APP_PACKAGES = "per_app_packages"
    private const val K_GOOGLE_CANDIDATES = "google_candidates"
    private const val K_GOOGLE_IP = "google_ip"
    private const val K_COALESCE_MS = "coalesce_ms"
    private const val K_IDLE_SLOTS = "idle_slots"

    val defaultGoogleIps = listOf(
        "216.239.32.120",
        "216.239.34.120",
        "216.239.36.120",
        "216.239.38.120"
    )
    const val defaultGoogleIp = "216.239.38.120"
    const val defaultCoalesceMs = 25
    const val defaultIdleSlots = 1

    fun defaultIdleFor(deployments: Int): Int = when {
        deployments >= 3 -> 3
        deployments == 2 -> 2
        else -> 1
    }

    fun mode(context: Context): Mode {
        val raw = prefs(context).getString(K_MODE, null)
        return raw?.let { runCatching { Mode.valueOf(it) }.getOrNull() } ?: Mode.TUN
    }

    fun setMode(context: Context, mode: Mode) {
        prefs(context).edit().putString(K_MODE, mode.name).apply()
    }

    fun port(context: Context): Int =
        prefs(context).getInt(K_PORT, Profile.DEFAULT_PORT)
            .coerceIn(Profile.MIN_PORT, Profile.MAX_PORT)

    fun setPort(context: Context, port: Int) {
        prefs(context).edit()
            .putInt(K_PORT, port.coerceIn(Profile.MIN_PORT, Profile.MAX_PORT))
            .apply()
    }

    fun vpnExplained(context: Context): Boolean =
        prefs(context).getBoolean(K_VPN_EXPLAINED, false)

    fun setVpnExplained(context: Context) {
        prefs(context).edit().putBoolean(K_VPN_EXPLAINED, true).apply()
    }

    fun perAppMode(context: Context): PerAppMode {
        val raw = prefs(context).getString(K_PER_APP_MODE, null)
        return raw?.let { runCatching { PerAppMode.valueOf(it) }.getOrNull() }
            ?: PerAppMode.ALL
    }

    fun setPerAppMode(context: Context, mode: PerAppMode) {
        prefs(context).edit().putString(K_PER_APP_MODE, mode.name).apply()
    }

    fun perAppPackages(context: Context): Set<String> =
        prefs(context).getStringSet(K_PER_APP_PACKAGES, emptySet())
            ?.toSet()
            ?: emptySet()

    fun setPerAppPackages(context: Context, packages: Set<String>) {
        prefs(context).edit()
            .putStringSet(K_PER_APP_PACKAGES, HashSet(packages))
            .apply()
    }

    fun googleCandidates(context: Context): List<String> {
        val raw = prefs(context).getString(K_GOOGLE_CANDIDATES, null)
            ?: return defaultGoogleIps
        val parsed = IpUtils.parseCandidates(raw)
        return parsed.ifEmpty { defaultGoogleIps }
    }

    fun setGoogleCandidates(context: Context, ips: List<String>) {
        val clean = ips.filter { IpUtils.isIPv4(it) }.distinct().take(32)
        prefs(context).edit()
            .putString(K_GOOGLE_CANDIDATES, clean.joinToString("\n"))
            .apply()
    }

    /** Empty means "use the built-in default edge". */
    fun selectedGoogleIp(context: Context): String {
        val value = prefs(context).getString(K_GOOGLE_IP, "").orEmpty()
        return if (IpUtils.isIPv4(value)) value else ""
    }

    fun setSelectedGoogleIp(context: Context, ip: String) {
        prefs(context).edit()
            .putString(K_GOOGLE_IP, if (IpUtils.isIPv4(ip)) ip else "")
            .apply()
    }

    fun coalesceMs(context: Context): Int =
        prefs(context).getInt(K_COALESCE_MS, defaultCoalesceMs).coerceIn(0, 1000)

    fun setCoalesceMs(context: Context, value: Int) {
        prefs(context).edit().putInt(K_COALESCE_MS, value.coerceIn(0, 1000)).apply()
    }

    fun idleSlots(context: Context, deployments: Int = 1): Int =
        prefs(context).getInt(K_IDLE_SLOTS, defaultIdleFor(deployments)).coerceIn(1, 3)

    fun setIdleSlots(context: Context, value: Int) {
        prefs(context).edit().putInt(K_IDLE_SLOTS, value.coerceIn(1, 3)).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
