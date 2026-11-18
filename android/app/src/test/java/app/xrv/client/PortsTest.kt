package app.xrv.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket

class PortsTest {
    @Test
    fun skipsAPortThatIsAlreadyBound() {
        ServerSocket().use { busy ->
            busy.reuseAddress = true
            busy.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0))
            val taken = busy.localPort
            val picked = Ports.pick(taken)
            assertNotEquals(taken, picked)
            assertTrue(Ports.isFree(picked))
        }
    }

    @Test
    fun picksThePreferredPortWhenFree() {
        val free = ServerSocket().use { socket ->
            socket.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0))
            socket.localPort
        }
        assertEquals(free, Ports.pick(free))
    }
}
