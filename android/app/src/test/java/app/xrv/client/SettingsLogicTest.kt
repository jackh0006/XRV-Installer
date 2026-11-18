package app.xrv.client

import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsLogicTest {
    @Test
    fun idleSlotsScaleWithDeploymentCount() {
        assertEquals(1, XrvSettings.defaultIdleFor(1))
        assertEquals(2, XrvSettings.defaultIdleFor(2))
        assertEquals(3, XrvSettings.defaultIdleFor(3))
        assertEquals(3, XrvSettings.defaultIdleFor(4))
    }

    @Test
    fun defaultEdgeMatchesTheLinuxClient() {
        assertEquals("216.239.38.120", XrvSettings.defaultGoogleIp)
        assertEquals(4, XrvSettings.defaultGoogleIps.size)
        assertEquals(25, XrvSettings.defaultCoalesceMs)
        assertEquals(1, XrvSettings.defaultIdleSlots)
    }
}
