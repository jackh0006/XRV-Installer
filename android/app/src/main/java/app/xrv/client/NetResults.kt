package app.xrv.client

import org.json.JSONArray
import org.json.JSONObject

data class Traffic(val up: Long, val down: Long, val sessions: Long)

data class EdgeResult(
    val ip: String,
    val ok: Boolean,
    val ms: Long,
    val status: Int,
    val error: String?
)

data class EdgeReport(
    val results: List<EdgeResult>,
    val best: String?,
    val bestMs: Long,
    val error: String?
)

data class TunnelTest(
    val ok: Boolean,
    val exitIp: String,
    val ms: Long,
    val error: String?
)

object NetResults {
    fun traffic(raw: String?): Traffic? = try {
        val o = JSONObject(raw.orEmpty())
        Traffic(
            up = o.optLong("up", 0),
            down = o.optLong("down", 0),
            sessions = o.optLong("sessions", 0)
        )
    } catch (_: Exception) {
        null
    }

    fun edges(raw: String?): EdgeReport = try {
        val o = JSONObject(raw.orEmpty())
        val array = o.optJSONArray("results") ?: JSONArray()
        val results = ArrayList<EdgeResult>(array.length())
        for (i in 0 until array.length()) {
            val r = array.optJSONObject(i) ?: continue
            results += EdgeResult(
                ip = r.optString("ip"),
                ok = r.optBoolean("ok", false),
                ms = r.optLong("ms", 0),
                status = r.optInt("status", 0),
                error = r.optString("error").takeIf { it.isNotEmpty() }
            )
        }
        EdgeReport(
            results = results,
            best = o.optString("best").takeIf { it.isNotEmpty() },
            bestMs = o.optLong("bestMs", 0),
            error = o.optString("error").takeIf { it.isNotEmpty() }
        )
    } catch (t: Exception) {
        EdgeReport(emptyList(), null, 0, t.message ?: "invalid probe result")
    }

    fun tunnel(raw: String?): TunnelTest = try {
        val o = JSONObject(raw.orEmpty())
        TunnelTest(
            ok = o.optBoolean("ok", false),
            exitIp = o.optString("exitIp"),
            ms = o.optLong("ms", 0),
            error = o.optString("error").takeIf { it.isNotEmpty() }
        )
    } catch (t: Exception) {
        TunnelTest(false, "", 0, t.message ?: "invalid test result")
    }
}
