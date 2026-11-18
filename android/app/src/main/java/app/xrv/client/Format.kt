package app.xrv.client

import java.util.Locale
import kotlin.math.ln
import kotlin.math.pow

object Format {
    fun bytes(value: Long): String {
        if (value < 0) return "—"
        if (value < 1024) return "$value B"
        val units = arrayOf("KB", "MB", "GB", "TB")
        val exp = (ln(value.toDouble()) / ln(1024.0)).toInt().coerceIn(1, units.size)
        return String.format(Locale.US, "%.1f %s", value / 1024.0.pow(exp.toDouble()), units[exp - 1])
    }

    fun duration(millis: Long): String {
        if (millis <= 0) return "00:00"
        val total = millis / 1000
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val seconds = total % 60
        return if (hours > 0) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%02d:%02d", minutes, seconds)
        }
    }
}
