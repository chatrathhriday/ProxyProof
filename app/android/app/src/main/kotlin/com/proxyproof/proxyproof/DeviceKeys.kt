package com.proxyproof.proxyproof

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Two EC P-256 keys in the Android Keystore. Private keys never leave secure hardware.
 *  - DEVICE: no user auth; signs every request -> proves "this exact phone".
 *  - BIO:    needs a strong biometric for *each* use and is permanently invalidated if a
 *            new fingerprint/face is enrolled -> proves "the enrolled owner is holding it".
 */
class DeviceKeys(private val activity: FragmentActivity) {
    private val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ensureKeys" -> result.success(ensureKeys())
                "signDevice" -> result.success(sign(DEVICE, call.argument<String>("payload")!!))
                "signBiometric" -> signBiometric(call.argument("payload")!!, call.argument("reason")!!, result)
                "resetKeys" -> { ks.deleteEntry(DEVICE); ks.deleteEntry(BIO); result.success(null) }
                "model" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                else -> result.notImplemented()
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            result.error("KEY_INVALIDATED", "Biometrics changed on this phone", null)
        } catch (e: IllegalStateException) {
            // Thrown by the Keystore when creating a biometric key with no fingerprint enrolled.
            result.error("NO_BIOMETRICS", "Set up a fingerprint or face unlock first", e.message)
        } catch (e: Exception) {
            result.error("KEY_ERROR", e.toString(), null)
        }
    }

    private fun ensureKeys(): Map<String, String> {
        if (!ks.containsAlias(DEVICE)) generate(DEVICE, biometric = false)
        if (!ks.containsAlias(BIO)) generate(BIO, biometric = true)
        return mapOf("devicePublicKey" to publicKey(DEVICE), "bioPublicKey" to publicKey(BIO))
    }

    private fun generate(alias: String, biometric: Boolean) {
        fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .apply {
                if (strongBox && Build.VERSION.SDK_INT >= 28) setIsStrongBoxBacked(true)
                if (biometric) {
                    setUserAuthenticationRequired(true)
                    setInvalidatedByBiometricEnrollment(true) // new fingerprint => key is dead
                    if (Build.VERSION.SDK_INT >= 30) {
                        setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG) // 0 = every use
                    }
                }
            }
            .build()

        val gen = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        try {
            gen.initialize(spec(strongBox = true)) // dedicated secure chip if the phone has one
            gen.generateKeyPair()
        } catch (e: StrongBoxUnavailableException) {
            gen.initialize(spec(strongBox = false)) // falls back to the TEE
            gen.generateKeyPair()
        }
    }

    private fun publicKey(alias: String): String =
        Base64.encodeToString(ks.getCertificate(alias).publicKey.encoded, Base64.NO_WRAP) // X.509 SPKI

    private fun privateKey(alias: String) = ks.getKey(alias, null) as PrivateKey

    private fun sign(alias: String, payload: String): String {
        val s = Signature.getInstance("SHA256withECDSA").apply { initSign(privateKey(alias)) }
        s.update(payload.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(s.sign(), Base64.NO_WRAP)
    }

    /** Shows the system fingerprint prompt; the key only unlocks for this one signature. */
    private fun signBiometric(payload: String, reason: String, result: MethodChannel.Result) {
        val sig = Signature.getInstance("SHA256withECDSA")
        sig.initSign(privateKey(BIO)) // throws KeyPermanentlyInvalidatedException if biometrics changed

        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                    try {
                        val s = r.cryptoObject!!.signature!!
                        s.update(payload.toByteArray(Charsets.UTF_8))
                        result.success(Base64.encodeToString(s.sign(), Base64.NO_WRAP))
                    } catch (e: Exception) {
                        result.error("KEY_ERROR", e.toString(), null)
                    }
                }

                override fun onAuthenticationError(code: Int, msg: CharSequence) {
                    result.error("BIO_CANCELLED", msg.toString(), code)
                }
                // onAuthenticationFailed (wrong finger) just lets the user retry inside the prompt.
            })

        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle("Confirm it's you")
                .setSubtitle(reason)
                .setNegativeButtonText("Cancel")
                .setAllowedAuthenticators(BIOMETRIC_STRONG) // no PIN fallback: a PIN can be shared
                .build(),
            BiometricPrompt.CryptoObject(sig),
        )
    }

    companion object {
        const val DEVICE = "proxyproof_device"
        const val BIO = "proxyproof_bio"
    }
}
