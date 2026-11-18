package app.xrv.client

import java.security.SecureRandom

/** Small pure helpers shared by settings, probing and tests. */
object IpUtils {
    private val ipv4 = Regex("^\\d{1,3}(\\.\\d{1,3}){3}$")
    private val split = Regex("[,\\s]+")

    fun isIPv4(value: String): Boolean {
        val text = value.trim()
        if (!ipv4.matches(text)) return false
        return text.split('.').all { part ->
            val n = part.toIntOrNull() ?: return false
            n in 0..255
        }
    }

    fun parseCandidates(raw: String, limit: Int = 32): List<String> {
        val out = LinkedHashSet<String>()
        for (part in raw.split(split)) {
            if (out.size >= limit) break
            val value = part.trim()
            if (isIPv4(value)) out += normalize(value)
        }
        return out.toList()
    }

    private fun normalize(value: String): String =
        value.split('.').joinToString(".") { it.toInt().toString() }
}

object Token {
    private val random = SecureRandom()

    fun hex(bytes: Int): String {
        val data = ByteArray(bytes)
        random.nextBytes(data)
        val digits = "0123456789abcdef"
        val out = CharArray(data.size * 2)
        for (i in data.indices) {
            val value = data[i].toInt() and 0xff
            out[i * 2] = digits[value ushr 4]
            out[i * 2 + 1] = digits[value and 0x0f]
        }
        return String(out)
    }
}
