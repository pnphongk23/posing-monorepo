package com.aipose.data.auth

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.readBytes
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.convert
import kotlinx.cinterop.reinterpret
import platform.darwin.UInt8Var
import kotlinx.cinterop.value
import kotlinx.serialization.json.Json
import platform.CoreFoundation.CFDataCreate
import platform.CoreFoundation.CFDataGetBytePtr
import platform.CoreFoundation.CFDataGetLength
import platform.CoreFoundation.CFDataRef
import platform.CoreFoundation.CFDictionaryAddValue
import platform.CoreFoundation.CFDictionaryCreateMutable
import platform.CoreFoundation.CFDictionaryRef
import platform.CoreFoundation.CFRelease
import platform.CoreFoundation.CFStringCreateWithCString
import platform.CoreFoundation.CFTypeRef
import platform.CoreFoundation.CFTypeRefVar
import platform.CoreFoundation.kCFAllocatorDefault
import platform.CoreFoundation.kCFBooleanTrue
import platform.CoreFoundation.kCFStringEncodingUTF8
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.errSecItemNotFound
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrService
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.Security.kSecValueData

@OptIn(ExperimentalForeignApi::class)
actual fun platformSecureTokenStorage(): SecureTokenStorage = KeychainTokenStorage()

/**
 * Process-scoped cache plus Keychain durability. The cache keeps the current
 * session available even when the Keychain API is unavailable (for example in
 * the Kotlin/Native iOS test host). Keychain writes remain best-effort so real
 * app installs still persist across relaunch when entitlements allow.
 */
@OptIn(ExperimentalForeignApi::class)
private class KeychainTokenStorage : SecureTokenStorage {
    private val service = "com.aipose.session"
    private val account = "backend-session-token"
    private var sessionCache: SessionCredentials? = null

    private fun cfString(value: String): CFTypeRef? =
        CFStringCreateWithCString(null, value, kCFStringEncodingUTF8)

    private fun cfData(bytes: ByteArray): CFTypeRef? = bytes.usePinned { pinned ->
        CFDataCreate(
            kCFAllocatorDefault,
            pinned.addressOf(0).reinterpret<UInt8Var>(),
            bytes.size.convert(),
        )
    }

    private fun identityQuery(): CFDictionaryRef? {
        val dict = CFDictionaryCreateMutable(null, 0, null, null) ?: return null
        CFDictionaryAddValue(dict, kSecClass, kSecClassGenericPassword)
        CFDictionaryAddValue(dict, kSecAttrService, cfString(service))
        CFDictionaryAddValue(dict, kSecAttrAccount, cfString(account))
        return dict
    }

    override fun saveCredentials(credentials: SessionCredentials) {
        sessionCache = credentials
        val encoded = Json.encodeToString(SessionCredentials.serializer(), credentials).encodeToByteArray()
        val payload = cfData(encoded) ?: return
        val query = identityQuery() ?: run {
            CFRelease(payload)
            return
        }
        keychainDelete()
        CFDictionaryAddValue(query, kSecValueData, payload)
        val status = SecItemAdd(query, null)
        CFRelease(payload)
        CFRelease(query)
        if (status != 0 && status != errSecItemNotFound.toInt()) {
            // Best-effort persistence; the in-memory cache still serves this process.
        }
    }

    override fun loadCredentials(): SessionCredentials? {
        sessionCache?.let { return it }
        val query = identityQuery() ?: return null
        return memScoped {
            val result = alloc<CFTypeRefVar>()
            CFDictionaryAddValue(query, kSecReturnData, kCFBooleanTrue)
            CFDictionaryAddValue(query, kSecMatchLimit, kSecMatchLimitOne)
            val status = SecItemCopyMatching(query, result.ptr)
            CFRelease(query)
            if (status == errSecItemNotFound.toInt() || status != 0) return@memScoped null
            val data = result.value as? CFDataRef ?: return@memScoped null
            val length = CFDataGetLength(data).toInt()
            val bytes = CFDataGetBytePtr(data)?.readBytes(length) ?: return@memScoped null
            Json.decodeFromString<SessionCredentials>(bytes.decodeToString()).also { parsed ->
                sessionCache = parsed
            }
        }
    }

    override fun clearCredentials() {
        sessionCache = null
        keychainDelete()
    }

    private fun keychainDelete() {
        val query = identityQuery() ?: return
        val status = SecItemDelete(query)
        CFRelease(query)
        if (status != 0 && status != errSecItemNotFound.toInt()) {
            // Best-effort clear when Keychain is unavailable in the test host.
        }
    }
}
