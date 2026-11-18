package app.xrv.client

import android.content.Context
import android.content.Intent

/** Connection mode chosen by the user. */
enum class Mode { TUN, PROXY }

/** Coarse connection state shown by the UI and the notification. */
enum class Phase { STOPPED, STARTING, RUNNING, ERROR }

data class XrvSnapshot(
    val mode: Mode? = null,
    val phase: Phase = Phase.STOPPED,
    val port: Int = 0,
    val message: String? = null,
    val startedAt: Long = 0L,
    val txBytes: Long = 0L,
    val rxBytes: Long = 0L
) {
    val active: Boolean get() = phase == Phase.STARTING || phase == Phase.RUNNING
}

/**
 * Small, non-secret state store shared by the services and the UI. A package
 * scoped broadcast makes the UI react immediately; the activity also polls so
 * elapsed time and statistics stay live.
 */
object XrvState {
    const val ACTION_CHANGED = "app.xrv.client.STATE_CHANGED"

    private const val PREFS = "xrv.state.v1"
    private const val K_MODE = "mode"
    private const val K_PHASE = "phase"
    private const val K_PORT = "port"
    private const val K_MESSAGE = "message"
    private const val K_STARTED = "started"
    private const val K_TX = "tx"
    private const val K_RX = "rx"

    fun read(context: Context): XrvSnapshot {
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return XrvSnapshot(
            mode = p.getString(K_MODE, null)?.let { runCatching { Mode.valueOf(it) }.getOrNull() },
            phase = p.getString(K_PHASE, null)
                ?.let { runCatching { Phase.valueOf(it) }.getOrNull() } ?: Phase.STOPPED,
            port = p.getInt(K_PORT, 0),
            message = p.getString(K_MESSAGE, null),
            startedAt = p.getLong(K_STARTED, 0L),
            txBytes = p.getLong(K_TX, 0L),
            rxBytes = p.getLong(K_RX, 0L)
        )
    }

    fun write(context: Context, snapshot: XrvSnapshot) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(K_MODE, snapshot.mode?.name)
            .putString(K_PHASE, snapshot.phase.name)
            .putInt(K_PORT, snapshot.port)
            .putString(K_MESSAGE, snapshot.message)
            .putLong(K_STARTED, snapshot.startedAt)
            .putLong(K_TX, snapshot.txBytes)
            .putLong(K_RX, snapshot.rxBytes)
            .apply()
        context.applicationContext.sendBroadcast(
            Intent(ACTION_CHANGED).setPackage(context.packageName)
        )
    }

    fun starting(context: Context, mode: Mode) =
        write(context, XrvSnapshot(mode = mode, phase = Phase.STARTING))

    fun running(context: Context, mode: Mode, port: Int, tx: Long = 0, rx: Long = 0) =
        write(
            context,
            XrvSnapshot(
                mode = mode,
                phase = Phase.RUNNING,
                port = port,
                startedAt = System.currentTimeMillis(),
                txBytes = tx,
                rxBytes = rx
            )
        )

    fun failed(context: Context, mode: Mode?, message: String) =
        write(context, XrvSnapshot(mode = mode, phase = Phase.ERROR, message = message))

    fun stopped(context: Context) = write(context, XrvSnapshot())
}
