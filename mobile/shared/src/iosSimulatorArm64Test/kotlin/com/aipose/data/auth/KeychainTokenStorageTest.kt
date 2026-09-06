package com.aipose.data.auth

import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Regression: Keychain queries must use NSDictionary bridging, not Kotlin Map casts. */
class KeychainTokenStorageTest {
    private val storage: SecureTokenStorage = platformSecureTokenStorage()

    @AfterTest
    fun tearDown() {
        storage.clearCredentials()
    }

    @Test
    fun `save load clear roundtrip without cast failure`() {
        val credentials = SessionCredentials("access-roundtrip", "refresh-roundtrip")
        storage.saveCredentials(credentials)
        assertEquals(credentials, storage.loadCredentials())
        storage.clearCredentials()
        assertNull(storage.loadCredentials())
    }
}
