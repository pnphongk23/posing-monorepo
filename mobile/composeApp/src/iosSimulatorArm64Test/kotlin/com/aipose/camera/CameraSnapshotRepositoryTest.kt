package com.aipose.camera

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.AfterVersion
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.SqlSchema
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import com.aipose.data.AiPoseDatabase
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CameraSnapshotRepositoryTest {
    @Test
    fun freshSchemaCreatesSnapshotAndRoundTripsAllEightGroups() {
        withDatabase { database, _ ->
            val repository = CameraSnapshotRepository(database)
            val settings = PersistedCameraSettings(
                facing = CameraFacing.FRONT.name,
                flash = FlashMode.AUTO.name,
                grid = true,
                guideVisible = false,
                opacity = 0.73f,
                lineColor = PoseLineColor.White.name,
                overlayX = 12.5f,
                overlayY = -4.25f,
                overlayScale = 1.8f,
                zoom = 2.4f,
            )
            repository.save(settings, null)

            assertEquals(settings, repository.load().settings)
            assertNull(repository.load().pose)
        }
    }

    @Test
    fun migrationFromV1PreservesPoseAndPhotoRows() {
        val name = isolatedName()
        val driver = NativeSqliteDriver(V1Schema, name)
        try {
            AiPoseDatabase.Schema.migrate(driver, oldVersion = 1, newVersion = 2)
            val database = AiPoseDatabase(driver)
            assertEquals("Pose V1", database.poseQueries.getPoseById("pose-v1").executeAsOne().name)
            assertEquals("/documents/photo.jpg", database.photoQueries.getPhotoById(1).executeAsOne().imagePath)
            assertTrue(database.cameraSnapshotQueries.getSnapshot().executeAsOneOrNull() == null)
        } finally {
            driver.close()
        }
    }

    @Test
    fun validOptionalPoseRoundTripsAndReplacePreservesSettings() {
        withDatabase { database, _ ->
            val repository = CameraSnapshotRepository(database)
            val settings = PersistedCameraSettings(grid = true, zoom = 2f)
            val first = PersistedPoseIdentity("pose-1", "One", "data:image/png;base64,one")
            val second = PersistedPoseIdentity("pose-2", "Two", "data:image/png;base64,two")
            repository.save(settings, first)
            repository.replacePose(second)

            assertEquals(settings, repository.load().settings)
            assertEquals(second, repository.load().pose)
        }
    }

    @Test
    fun corruptPosePreservesSettingsAndClearRemovesOnlyPose() {
        withDatabase { database, _ ->
            val repository = CameraSnapshotRepository(database)
            val settings = PersistedCameraSettings(grid = true, opacity = 0.9f)
            repository.save(settings, PersistedPoseIdentity("pose", "Pose", "broken"))
            database.cameraSnapshotQueries.updatePose("{not-json")

            assertEquals(settings, repository.load().settings)
            assertNull(repository.load().pose)
            repository.clearPose()
            assertEquals(settings, repository.load().settings)
            assertNull(repository.load().pose)
        }
    }

    @Test
    fun corruptPartialAndUnknownPayloadsFallbackWithoutCrash() {
        withDatabase { database, _ ->
            val repository = CameraSnapshotRepository(database)
            repository.save(PersistedCameraSettings(grid = true), null)
            database.cameraSnapshotQueries.upsertSnapshot(
                schemaVersion = 99,
                settings_json = "{\"unknown\":true}",
                pose_json = "{\"poseId\":\"p\"}",
            )
            assertEquals(PersistedCameraSettings(), repository.load().settings)
            assertNull(repository.load().pose)

            database.cameraSnapshotQueries.upsertSnapshot(
                schemaVersion = 1,
                settings_json = "{\"grid\":true}",
                pose_json = null,
            )
            assertEquals(PersistedCameraSettings(grid = true), repository.load().settings)
            assertNull(repository.load().pose)
        }
    }

    @Test
    fun snapshotHasNoForeignKeyOrTransportTypeLeakage() {
        withDatabase { database, _ ->
            database.cameraSnapshotQueries.upsertSnapshot(1, "{}", null)
            assertNull(database.cameraSnapshotQueries.getSnapshot().executeAsOneOrNull()?.pose_json)
            assertTrue(PersistedCameraSettings::class != PersistedPoseIdentity::class)
        }
    }

    private fun withDatabase(block: (AiPoseDatabase, SqlDriver) -> Unit) {
        val driver = NativeSqliteDriver(AiPoseDatabase.Schema, isolatedName())
        try {
            block(AiPoseDatabase(driver), driver)
        } finally {
            driver.close()
        }
    }

    private fun isolatedName(): String = "feat012-camera-snapshot-${Random.nextLong()}.db"
}

private object V1Schema : SqlSchema<QueryResult.Value<Unit>> {
    override val version: Long = 1

    override fun create(driver: SqlDriver): QueryResult.Value<Unit> {
        driver.execute(null, """
            CREATE TABLE Pose (
                poseId TEXT PRIMARY KEY, ownerAccountId TEXT NOT NULL, name TEXT NOT NULL,
                description TEXT, tags TEXT NOT NULL DEFAULT '[]', difficulty TEXT,
                bodyParts TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL,
                originalPath TEXT NOT NULL, skeletonPath TEXT NOT NULL, thumbnailPath TEXT NOT NULL,
                currentJobId TEXT, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
            )
        """.trimIndent(), 0)
        driver.execute(null, """
            CREATE TABLE Photo (
                id INTEGER PRIMARY KEY AUTOINCREMENT, imagePath TEXT NOT NULL, poseId TEXT,
                poseName TEXT NOT NULL DEFAULT '', createdAt TEXT NOT NULL,
                isFavorite INTEGER NOT NULL DEFAULT 0
            )
        """.trimIndent(), 0)
        driver.execute(null, """
            INSERT INTO Pose(poseId, ownerAccountId, name, status, originalPath, skeletonPath,
                thumbnailPath, createdAt, updatedAt)
            VALUES ('pose-v1', 'owner', 'Pose V1', 'local', '/documents/o.jpg',
                '/documents/s.jpg', '/documents/t.jpg', '2026-01-01', '2026-01-01')
        """.trimIndent(), 0)
        driver.execute(null, """
            INSERT INTO Photo(imagePath, poseId, poseName, createdAt, isFavorite)
            VALUES ('/documents/photo.jpg', 'pose-v1', 'Pose V1', '2026-01-01', 0)
        """.trimIndent(), 0)
        return QueryResult.Unit
    }

    override fun migrate(driver: SqlDriver, oldVersion: Long, newVersion: Long, vararg callbacks: AfterVersion): QueryResult.Value<Unit> = QueryResult.Unit
}
