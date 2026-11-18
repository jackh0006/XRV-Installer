package app.xrv.client

import org.json.JSONArray
import org.json.JSONObject

/**
 * Non-secret connection settings are kept in [XrvSettings]; this object only
 * carries what the engine needs and is encrypted at rest.
 */
data class Profile(
    val deployments: List<String>,
    val tunnelKey: String,
    val socksPort: Int = DEFAULT_PORT,
    val socksUser: String = "",
    val socksPass: String = ""
) {
    fun normalized(): Profile = copy(
        deployments = deployments.map { normalizeDeployment(it) }.filter { it.isNotEmpty() },
        tunnelKey = normalizeKey(tunnelKey),
        socksPort = socksPort,
        socksUser = socksUser.trim(),
        socksPass = socksPass.trim()
    )

    /** The loopback proxy requires RFC 1929 auth so other apps cannot use it. */
    fun ensureCredentials(): Profile {
        if (socksUser.isNotEmpty() && socksPass.isNotEmpty()) return this
        return copy(
            socksUser = "xrv" + Token.hex(6),
            socksPass = Token.hex(16)
        )
    }

    fun json(): String = JSONObject().apply {
        put("deployments", JSONArray(deployments))
        put("tunnelKey", tunnelKey)
        put("socksPort", socksPort)
        put("socksUser", socksUser)
        put("socksPass", socksPass)
    }.toString()

    companion object {
        const val DEFAULT_PORT = 1080
        const val MIN_PORT = 1024
        const val MAX_PORT = 65535
        const val MAX_DEPLOYMENTS = 4

        private val deploymentPattern = Regex("^AKfycb[A-Za-z0-9_-]{44,}$")
        private val keyPattern = Regex("^[0-9a-fA-F]{64}$")

        /** Accepts a bare deployment ID or a pasted Apps Script /exec URL. */
        fun normalizeDeployment(raw: String): String {
            val value = raw.trim().trim('"', '\'').trim()
            val marker = "/macros/s/"
            val index = value.indexOf(marker)
            if (index < 0) return value
            return value.substring(index + marker.length)
                .substringBefore('/')
                .substringBefore('?')
                .trim()
        }

        fun isDeploymentId(value: String): Boolean =
            deploymentPattern.matches(normalizeDeployment(value))

        /** Removes pasted spaces/newlines and normalizes hex case. */
        fun normalizeKey(raw: String): String =
            raw.trim().replace(Regex("\\s+"), "").lowercase()

        fun fromJson(raw: String): Profile {
            val o = JSONObject(raw)
            val ids = o.getJSONArray("deployments")
            return Profile(
                deployments = List(ids.length()) { ids.getString(it) },
                tunnelKey = o.getString("tunnelKey"),
                socksPort = o.optInt("socksPort", DEFAULT_PORT),
                socksUser = o.optString("socksUser", ""),
                socksPass = o.optString("socksPass", "")
            )
        }



        /** Returns a user-facing error, or null when the profile is valid. */
        fun validate(ids: List<String>, key: String, port: Int): String? {
            val deployments = ids.map { normalizeDeployment(it) }.filter { it.isNotEmpty() }
            val normalizedKey = normalizeKey(key)
            return when {
                deployments.isEmpty() -> "Enter at least one deployment ID."
                deployments.size > MAX_DEPLOYMENTS -> "Use at most four deployment IDs."
                deployments.any { !isDeploymentId(it) } ->
                    "A deployment ID must start with AKfycb and be at least 50 characters long."
                deployments.distinct().size != deployments.size ->
                    "Deployment IDs must be unique."
                !keyPattern.matches(normalizedKey) ->
                    "The tunnel key must be exactly 64 hexadecimal characters."
                port !in MIN_PORT..MAX_PORT ->
                    "The local proxy port must be between $MIN_PORT and $MAX_PORT."
                else -> null
            }
        }
    }
}
