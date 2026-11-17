package app.xrv.client

import org.json.JSONArray
import org.json.JSONObject

data class Profile(val deployments: List<String>, val tunnelKey: String, val socksPort: Int = 1080) {
    fun json(): String = JSONObject().apply { put("deployments", JSONArray(deployments)); put("tunnelKey", tunnelKey); put("socksPort", socksPort) }.toString()
    companion object {
        fun fromJson(raw: String): Profile { val o = JSONObject(raw); val ids = o.getJSONArray("deployments"); return Profile(List(ids.length()) { ids.getString(it) }, o.getString("tunnelKey"), o.optInt("socksPort", 1080)) }
        fun validate(ids: List<String>, key: String, port: Int): String? = when {
            ids.isEmpty() || ids.size > 4 -> "Add between one and four deployment IDs."
            ids.any { !Regex("AKfycb[A-Za-z0-9_-]{44,}").matches(it) } -> "Each deployment ID must start with AKfycb."
            ids.distinct().size != ids.size -> "Deployment IDs must be unique."
            !Regex("[0-9a-fA-F]{64}").matches(key) -> "Tunnel key must be exactly 64 hexadecimal characters."
            port !in 1024..65535 -> "SOCKS port must be between 1024 and 65535."
            else -> null
        }
    }
}
