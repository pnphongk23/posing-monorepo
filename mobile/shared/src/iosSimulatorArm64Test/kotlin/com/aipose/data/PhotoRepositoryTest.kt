package com.aipose.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PhotoRepositoryTest {
    @Test
    fun insertCapturedPhoto_doesNotCrash_whenMultipleRowsExist() {
        val driver = DatabaseDriverFactory().createDriver()
        try {
            val database = AiPoseDatabase(driver)
            val repository = PhotoRepository(database)

            val firstId = repository.insertCapturedPhoto("/tmp/first.jpg")
            val secondId = repository.insertCapturedPhoto("/tmp/second.jpg")

            assertTrue(secondId > firstId)
            assertEquals("/tmp/second.jpg", repository.getLatestPhotoPath())
            assertEquals("/tmp/first.jpg", database.photoQueries.getPhotoById(firstId).executeAsOne().imagePath)
            assertEquals("/tmp/second.jpg", database.photoQueries.getPhotoById(secondId).executeAsOne().imagePath)
        } finally {
            driver.close()
        }
    }
}
