package app.xrv.client

import org.json.JSONArray
import org.json.JSONObject

data class EngineOptions(
    val googleIp: String = "",
    val coalesceMs: Int = XrvSettings.defaultCoalesceMs,
    val idleSlots: Int = XrvSettings.defaultIdleSlots
)

/**
 * Process-wide owner of the native engine. Android services and the activity
 * all run in the same process, so a single synchronized entry point prevents
 * duplicate listeners and startup races.
 */
object Engine {
    private const val OWNER_NONE = ""

    @Volatile
    var port: Int = 0
        private set

    @Volatile
    private var owner: String = OWNER_NONE

    @Synchronized
    fun start(
        profile: Profile,
        requestedBy: String,
        options: EngineOptions = EngineOptions()
    ): Result<Int> {
        NativeBridge.loadError?.let {
            return Result.failure(IllegalStateException("Native engine unavailable: $it"))
        }
        // Make start idempotent even after a service crash or a mode switch.
        runCatching { NativeBridge.stop() }
        owner = OWNER_NONE
        port = 0

        val selected = try {
            Ports.pick(profile.socksPort)
        } catch (t: Throwable) {
            return Result.failure(t)
        }
        val config = JSONObject(profile.copy(socksPort = selected).json()).apply {
            put("googleIp", options.googleIp)
            put(
                "sniHosts",
                JSONArray(listOf("www.google.com", "mail.google.com", "accounts.google.com"))
            )
            put("coalesceMs", options.coalesceMs)
            put("idleSlots", options.idleSlots)
        }.toString()
        val error = runCatching {
            NativeBridge.start(config)
        }.getOrElse { t ->
            return Result.failure(
                IllegalStateException(t.message ?: "The native engine could not start.", t)
            )
        }
        if (error.isNotEmpty()) {
            XrvLog.add("engine", "start failed: $error")
            return Result.failure(IllegalStateException(error))
        }
        owner = requestedBy
        port = selected
        XrvLog.add("engine", "started on 127.0.0.1:$selected owner=$requestedBy edge=${options.googleIp.ifEmpty { "default" }}")
        return Result.success(selected)
    }

    /** Stops the engine only when [requestedBy] still owns it. */
    @Synchronized
    fun stop(requestedBy: String) {
        if (owner != requestedBy) return
        stopInternal()
    }

    /** Unconditional stop, used when the user explicitly disconnects. */
    @Synchronized
    fun stop() = stopInternal()

    private fun stopInternal() {
        if (NativeBridge.loadError == null) {
            runCatching { NativeBridge.stop() }
        }
        XrvLog.add("engine", "stopped")
        owner = OWNER_NONE
        port = 0
    }
}
