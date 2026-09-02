package com.aipose.camera

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CameraSnapshotWriterTest {
    @Test
    fun opacityBurstWritesOnceWithLatestSnapshot(): Unit = runBlocking {
        val writes = Channel<Pair<PersistedCameraSettings, PersistedPoseIdentity?>>(Channel.UNLIMITED)
        val writer = CameraSnapshotWriter(
            scope = testScope(),
            save = { settings, pose -> writes.trySend(settings to pose) },
            debounceMillis = 50L,
            workerDispatcher = Dispatchers.Unconfined,
        )

        repeat(20) { tick -> writer.save(PersistedCameraSettings(opacity = tick / 20f), null) }

        val write = withTimeout(2_000L) { writes.receive() }
        assertEquals(0.95f, write.first.opacity)
        assertNull(write.second)
        assertNull(withTimeoutOrNull(150L) { writes.receive() })
        writer.close()
        writes.close()
    }

    @Test
    fun pendingSaveThenClearPreservesLatestSettingsAndRemovesPose(): Unit = runBlocking {
        val writes = Channel<Pair<PersistedCameraSettings, PersistedPoseIdentity?>>(Channel.UNLIMITED)
        val writer = CameraSnapshotWriter(
            scope = testScope(),
            save = { settings, pose -> writes.trySend(settings to pose) },
            debounceMillis = 50L,
            workerDispatcher = Dispatchers.Unconfined,
        )
        val latestSettings = PersistedCameraSettings(opacity = 0.91f, zoom = 2.5f)

        writer.save(latestSettings.copy(opacity = 0.2f), pose("old"))
        writer.clearPose(latestSettings)

        val write = withTimeout(2_000L) { writes.receive() }
        assertEquals(latestSettings, write.first)
        assertNull(write.second)
        assertNull(withTimeoutOrNull(150L) { writes.receive() })
        writer.close()
        writes.close()
    }

    @Test
    fun pendingSaveThenNavigationReplaceIsOrderedAndPreservesLatestSettings(): Unit = runBlocking {
        val writes = Channel<Pair<PersistedCameraSettings, PersistedPoseIdentity?>>(Channel.UNLIMITED)
        val replacements = Channel<PersistedPoseIdentity>(Channel.UNLIMITED)
        val writer = CameraSnapshotWriter(
            scope = testScope(),
            save = { settings, pose -> writes.trySend(settings to pose) },
            replacePose = { replacements.trySend(it) },
            debounceMillis = 50L,
            workerDispatcher = Dispatchers.Unconfined,
        )
        val latestSettings = PersistedCameraSettings(opacity = 0.91f, zoom = 2.5f)
        val replacement = pose("replacement")

        writer.save(latestSettings, pose("stale"))
        writer.replacePose(replacement)

        val settingsWrite = withTimeout(2_000L) { writes.receive() }
        val replacementWrite = withTimeout(2_000L) { replacements.receive() }
        assertEquals(latestSettings, settingsWrite.first)
        assertNull(settingsWrite.second)
        assertEquals(replacement, replacementWrite)
        writer.close()
        writes.close()
        replacements.close()
    }

    @Test
    fun closePreventsStaleSaveAndReplacementMutation(): Unit = runBlocking {
        val writes = Channel<Pair<PersistedCameraSettings, PersistedPoseIdentity?>>(Channel.UNLIMITED)
        val replacements = Channel<PersistedPoseIdentity>(Channel.UNLIMITED)
        val writer = CameraSnapshotWriter(
            scope = testScope(),
            save = { settings, pose -> writes.trySend(settings to pose) },
            replacePose = { replacements.trySend(it) },
            debounceMillis = 50L,
            workerDispatcher = Dispatchers.Unconfined,
        )

        writer.save(PersistedCameraSettings(opacity = 0.2f), pose("stale"))
        writer.close()
        writer.replacePose(pose("replacement"))

        assertNull(withTimeoutOrNull(150L) { writes.receive() })
        assertNull(withTimeoutOrNull(150L) { replacements.receive() })
        writes.close()
        replacements.close()
    }

    private fun pose(id: String) = PersistedPoseIdentity(id, id, "$id.png")

    private fun testScope() = CoroutineScope(SupervisorJob() + Dispatchers.Default)
}
