package app.xrv.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IpUtilsTest {
    @Test
    fun validatesIPv4() {
        assertTrue(IpUtils.isIPv4("216.239.38.120"))
        assertTrue(IpUtils.isIPv4("0.0.0.0"))
        assertTrue(IpUtils.isIPv4("255.255.255.255"))
        assertFalse(IpUtils.isIPv4("256.1.1.1"))
        assertFalse(IpUtils.isIPv4("1.2.3"))
        assertFalse(IpUtils.isIPv4("example.com"))
        assertFalse(IpUtils.isIPv4("1.2.3.4/24"))
        assertFalse(IpUtils.isIPv4(""))
    }

    @Test
    fun parsesAndNormalizesCandidates() {
        val raw = "216.239.32.120, 216.239.34.120\n216.239.38.120\n216.239.32.120\nbad"
        assertEquals(
            listOf("216.239.32.120", "216.239.34.120", "216.239.38.120"),
            IpUtils.parseCandidates(raw)
        )
        assertEquals(listOf("1.2.3.4"), IpUtils.parseCandidates("001.002.003.004"))
        assertTrue(IpUtils.parseCandidates("bad, still bad").isEmpty())
    }

    @Test
    fun tokenHasRequestedLengthAndVaries() {
        val a = Token.hex(16)
        val b = Token.hex(16)
        assertEquals(32, a.length)
        assertEquals(32, b.length)
        assertTrue(a.matches(Regex("[0-9a-f]{32}")))
        assertTrue(a != b)
    }
}
