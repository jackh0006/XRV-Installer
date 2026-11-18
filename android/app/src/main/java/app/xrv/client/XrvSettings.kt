package app.xrv.client

import android.content.Context

/** Non-secret preferences: chosen mode and UI flags. */
object XrvSettings {
    private const val PREFS = "xrv.settings.v1"
    private const val K_MODE = "mode"
    private const val K_VPN_EXPLAINED = "vpn_explained"

    fun mode(context: Context): Mode {
        val raw = prefs(context).getString(K_MODE, null)
        return raw?.let { runCatching { Mode.valueOf(it) }.getOrNull() } ?: Mode.TUN
    }

    fun setMode(context: Context, mode: Mode) {
        prefs(context).edit().putString(K_MODE, mode.name).apply()
    }

    fun vpnExplained(context: Context): Boolean =
        prefs(context).getBoolean(K_VPN_EXPLAINED, false)

    fun setVpnExplained(context: Context) {
        prefs(context).edit().putBoolean(K_VPN_EXPLAINED, true).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
