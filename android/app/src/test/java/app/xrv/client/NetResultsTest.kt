package app.xrv.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NetResultsTest {
    @Test
    fun parsesTraffic() {
        val traffic = NetResults.traffic("""{"up":123,"down":456,"sessions":2}""")!!
        assertEquals(123, traffic.up)
        assertEquals(456, traffic.down)
        assertEquals(2, traffic.sessions)
        assertNull(NetResults.traffic("not json"))
    }

    @Test
    fun parsesEdgeReport() {
        val report = NetResults.edges(
            """{"results":[{"ip":"1.2.3.4","ok":true,"ms":42,"status":204},
               {"ip":"5.6.7.8","ok":false,"ms":0,"error":"connect failed"}],
               "best":"1.2.3.4","bestMs":42}"""
        )
        assertEquals(2, report.results.size)
        assertTrue(report.results[0].ok)
        assertEquals(204, report.results[0].status)
        assertEquals("1.2.3.4", report.best)
        assertEquals(42, report.bestMs)
    }

    @Test
    fun parsesTunnelTest() {
        val ok = NetResults.tunnel("""{"ok":true,"exitIp":"9.9.9.9","ms":321}""")
        assertTrue(ok.ok)
        assertEquals("9.9.9.9", ok.exitIp)
        assertEquals(321, ok.ms)
        val bad = NetResults.tunnel("""{"ok":false,"error":"tunnel request failed"}""")
        assertFalse(bad.ok)
        assertEquals("tunnel request failed", bad.error)
    }
}
