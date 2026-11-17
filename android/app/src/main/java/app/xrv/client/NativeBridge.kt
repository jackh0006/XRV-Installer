package app.xrv.client

/** JNI boundary for the vendored, protocol-compatible GooseRelayVPN engine. */
object NativeBridge {
    init { System.loadLibrary("xrvjni") }
    external fun start(configJson: String): String
    external fun stop()
}
