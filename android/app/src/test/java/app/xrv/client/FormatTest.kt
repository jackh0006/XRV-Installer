package app.xrv.client

import org.junit.Assert.assertEquals
import org.junit.Test

class FormatTest {
    @Test
    fun formatsBytes() {
        assertEquals("0 B", Format.bytes(0))
        assertEquals("1023 B", Format.bytes(1023))
        assertEquals("1.0 KB", Format.bytes(1024))
        assertEquals("1.5 MB", Format.bytes(1024L * 1024L * 3 / 2))
    }

    @Test
    fun formatsDuration() {
        assertEquals("00:00", Format.duration(0))
        assertEquals("01:05", Format.duration(65_000))
        assertEquals("1:01:05", Format.duration(3_665_000))
    }
}
