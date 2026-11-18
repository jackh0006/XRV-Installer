package app.xrv.client

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * In-app event log. Persists to app-private storage so a failure can be read
 * after a restart. Secrets are redacted before anything is stored.
 */
object XrvLog {
    private const val MAX_LINES = 600
    private const val MAX_FILE_BYTES = 512 * 1024
    private val buffer = ArrayDeque<String>()
    private val lock = Any()
    private val writer = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "xrv-log").apply { isDaemon = true }
    }
    private var file: File? = null

    private val keyPattern = Regex("[0-9a-fA-F]{64}")
    private val deploymentPattern = Regex("AKfycb[A-Za-z0-9_.-]*")
    private val proxyPattern = Regex("socks5://[^\\s]+")

    fun init(context: Context) {
        if (file != null) return
        val target = File(context.applicationContext.filesDir, "xrv.log")
        file = target
        if (!target.exists()) return
        val lines = runCatching {
            if (target.length() > MAX_FILE_BYTES) {
                val tail = target.readLines().takeLast(400)
                target.writeText(tail.joinToString("\n", postfix = "\n"))
                tail
            } else {
                target.readLines()
            }
        }.getOrDefault(emptyList())
        synchronized(lock) {
            buffer.clear()
            lines.takeLast(MAX_LINES).forEach { buffer.addLast(it) }
        }
    }

    fun add(tag: String, message: String) {
        val clean = redact(message.replace('\n', ' ').trim())
        if (clean.isEmpty()) return
        val line = "${timestamp()}  [$tag] $clean"
        synchronized(lock) {
            buffer.addLast(line)
            while (buffer.size > MAX_LINES) buffer.removeFirst()
        }
        writer.execute { append(line) }
    }

    fun addSync(tag: String, message: String) {
        val clean = redact(message.replace('\n', ' ').trim())
        if (clean.isEmpty()) return
        val line = "${timestamp()}  [$tag] $clean"
        synchronized(lock) {
            buffer.addLast(line)
            while (buffer.size > MAX_LINES) buffer.removeFirst()
        }
        append(line)
    }

    fun read(): String = synchronized(lock) { buffer.joinToString("\n") }

    fun clear() {
        synchronized(lock) { buffer.clear() }
        writer.execute {
            runCatching { file?.delete() }
        }
    }

    private fun append(line: String) {
        val target = file ?: return
        runCatching {
            if (target.length() > MAX_FILE_BYTES) target.delete()
            target.appendText(line + "\n")
        }
    }

    private fun redact(value: String): String {
        var text = value
        text = keyPattern.replace(text, "[key]")
        text = deploymentPattern.replace(text, "[deployment]")
        text = proxyPattern.replace(text, "socks5://[redacted]")
        return text
    }

    private fun timestamp(): String =
        SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
}
