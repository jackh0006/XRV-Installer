package app.xrv.client

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Encrypts configuration at rest with a non-exportable Android Keystore key. */
class SecureProfileStore(context: Context) {
    private val prefs = context.getSharedPreferences("xrv.secure", Context.MODE_PRIVATE)
    private val alias = "xrv.profile.v1"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun save(profile: Profile) { val c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.ENCRYPT_MODE, key()); prefs.edit().putString("iv", Base64.encodeToString(c.iv, Base64.NO_WRAP)).putString("data", Base64.encodeToString(c.doFinal(profile.json().toByteArray()), Base64.NO_WRAP)).apply() }
    fun load(): Profile? = try { val iv = prefs.getString("iv", null) ?: return null; val data = prefs.getString("data", null) ?: return null; val c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP))); Profile.fromJson(String(c.doFinal(Base64.decode(data, Base64.NO_WRAP)))) } catch (_: Exception) { null }
    fun clear() { prefs.edit().clear().apply() }
}
