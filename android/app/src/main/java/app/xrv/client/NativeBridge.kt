package app.xrv.client

/**
 * JNI boundary for the self-contained native engine
 * (libxrvbridge.so: Go relay engine + JNI entry points).
 *
 * Loading is lazy and never allowed to terminate the process: if the library
 * cannot be loaded, [loadError] is reported in the UI instead.
 */
object NativeBridge {
    val loadError: String? by lazy {
        try {
            System.loadLibrary("xrvbridge")
            null
        } catch (t: Throwable) {
            t.message ?: t.javaClass.simpleName
        }
    }

    fun isAvailable(): Boolean = loadError == null

    external fun start(configJson: String): String
    external fun stop()
}
