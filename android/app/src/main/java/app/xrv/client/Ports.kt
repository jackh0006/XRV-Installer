package app.xrv.client

import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket

/** Picks a free loopback port so a stale listener can never block Connect. */
object Ports {
    fun isFree(port: Int): Boolean = try {
        ServerSocket().use { socket ->
            socket.reuseAddress = true
            socket.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port))
        }
        true
    } catch (_: Exception) {
        false
    }

    /**
     * Returns [preferred] when it is free, otherwise the next free port in a
     * small window and finally any free unprivileged port.
     */
    fun pick(preferred: Int): Int {
        val start = preferred.coerceIn(Profile.MIN_PORT, Profile.MAX_PORT)
        if (isFree(start)) return start
        for (offset in 1..50) {
            val candidate = start + offset
            if (candidate > Profile.MAX_PORT) break
            if (isFree(candidate)) return candidate
        }
        for (candidate in Profile.MIN_PORT..Profile.MAX_PORT) {
            if (candidate != start && isFree(candidate)) return candidate
        }
        throw IllegalStateException("No free local port is available.")
    }
}
