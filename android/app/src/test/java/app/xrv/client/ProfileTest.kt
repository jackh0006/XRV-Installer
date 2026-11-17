package app.xrv.client

import org.junit.Assert.*
import org.junit.Test

class ProfileTest {
    private val id = "AKfycb0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"
    private val key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    @Test fun acceptsValidProfile() { assertNull(Profile.validate(listOf(id), key, 1080)) }
    @Test fun rejectsBadInputs() { assertNotNull(Profile.validate(listOf("wrong"), key, 1080)); assertNotNull(Profile.validate(List(5) { id + it }, key, 1080)); assertNotNull(Profile.validate(listOf(id), "wrong", 1080)); assertNotNull(Profile.validate(listOf(id), key, 80)) }
    @Test fun preservesProfileJson() { val p = Profile(listOf(id), key, 2080); assertEquals(p, Profile.fromJson(p.json())) }
}
