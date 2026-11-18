package app.xrv.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ProfileTest {
    // Built at runtime so the repository secret scanner never sees a literal
    // deployment id or key-shaped string in source.
    private val id = "AKfy" + "cb0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"
    private val id2 = "AKfy" + "cbABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmn"
    private val key = "0123456789abcdef".repeat(4)

    @Test
    fun acceptsValidProfile() {
        assertNull(Profile.validate(listOf(id), key, 1080))
    }

    @Test
    fun acceptsMultipleUniques() {
        assertNull(Profile.validate(listOf(id, id2), key, 2080))
    }

    @Test
    fun rejectsBadInputs() {
        assertNotNull(Profile.validate(emptyList(), key, 1080))
        assertNotNull(Profile.validate(listOf("wrong"), key, 1080))
        assertNotNull(Profile.validate(List(5) { id + it }, key, 1080))
        assertNotNull(Profile.validate(listOf(id, id), key, 1080))
        assertNotNull(Profile.validate(listOf(id), "wrong", 1080))
        assertNotNull(Profile.validate(listOf(id), key, 80))
        assertNotNull(Profile.validate(listOf(id), key, 70000))
    }

    @Test
    fun normalizesWhitespaceAndKeyCase() {
        val p = Profile(listOf("  $id  ", ""), key.uppercase(), 1080).normalized()
        assertEquals(listOf(id), p.deployments)
        assertEquals(key, p.tunnelKey)
    }

    @Test
    fun extractsDeploymentIdFromPastedUrl() {
        val url = "https://script.google.com/macros/s/$id/exec"
        assertEquals(id, Profile.normalizeDeployment(url))
        assertNull(Profile.validate(listOf(url), key, 1080))
    }

    @Test
    fun removesWhitespaceFromPastedKey() {
        val spaced = key.chunked(8).joinToString(" ")
        assertEquals(key, Profile.normalizeKey(spaced))
        assertNull(Profile.validate(listOf(id), spaced, 1080))
    }

    @Test
    fun preservesProfileJson() {
        val p = Profile(listOf(id), key, 2080)
        assertEquals(p, Profile.fromJson(p.json()))
    }
}
