package com.aipose.camera

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlin.coroutines.coroutineContext
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CameraSnapshotWriterTest {
    @Test
    fun opacityBurstWritesOnceWithLatestSnapshot(): Unit = runBlocking {
        val (writer, writes) = harness(coroutineContext)
        repeat(20) { tick -> writer.save(PersistedCameraSettings(opacity = tick / 20f), null) }
        writer.flushNow()
        val write = writes.tryReceive().getOrNull() ?: error("Expected snapshot write")
        assertEquals(0.95f, write.first.opacity)
        assertNull(write.second)
        writer.flushNow()
        assertNull(writes.tryReceive().getOrNull())
        writer.close()
        writes.close()
    }

    @Test
    fun pendingSaveThenClearPreservesLatestSettingsAndRemovesPose(): Unit = runBlocking {
        val (writer, writes) = harness(coroutineContext)
        val latestSettings = PersistedCameraSettings(opacity = 0.91f, zoom = 2.5f)
        writer.save(latestSettings.copy(opacity = 0.2f), pose("old"))
        writer.clearPose(latestSettings)
        writer.flushNow()
        val write = writes.tryReceive().getOrNull() ?: error("Expected snapshot write")
        assertEquals(latestSettings, write.first)
        assertNull(write.second)
        writer.close()
        writes.close()
    }

    @Test
    fun pendingSaveThenNavigationReplaceIsOrderedAndPreservesLatestSettings(): Unit = runBlocking {
        val writes = Channel<Pair<PersistedCameraSettings, PersistedPoseIdentity?>>(Channel.UNLIMITED)
        val replacements = Channel<PersistedPoseIdentity>(Channel.UNLIMITED)
        val writer = CameraSnapshotWriter(
            scope = testScope(coroutineContext),
            persist = { settings, pose -> writes.trySend(settings to pose) },
            replacePose = { replacements.trySend(it) },
            debounceMillis = 50L,
            startWorker = false,
        )
        val latestSettings = PersistedCameraSettings(opacity = 0.91f, zoom = 2.5f)
        val replacement = pose("replacement")
        writer.save(latestSettings, pose("stale"))
        writer.replacePose(replacement)
        writer.flushNow()
        val settingsWrite = writes.tryReceive().getOrNull() ?: error("Expected settings write")
        val replacementWrite = replacements.tryReceive().getOrNull() ?: error("Expected pose replacement")
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
            scope = testScope(coroutineContext),
            persist = { settings, pose -> writes.trySend(settings to pose) },
            replacePose = { replacements.trySend(it) },
            debounceMillis = 50L,
            startWorker = false,
        )
        writer.save(PersistedCameraSettings(opacity = 0.2f), pose("stale"))
        writer.close()
        writer.replacePose(pose("replacement"))
        delay(150)
        assertNull(writes.tryReceive().getOrNull())
        assertNull(replacements.tryReceive().getOrNull())
        writes.close()
        replacements.close()
    }

    private fun testScope(context: kotlin.coroutines.CoroutineContext): CoroutineScope =
        CoroutineScope(SupervisorJob() + context)

    private fun harness(
        context: kotlin.coroutines.CoroutineContext,
    ): Pair<CameraSnapshotWriter, Channel<Pair<PersistedCameraSettings, PersistedPoseIdentity?>>> {
        val writes = Channel<Pair<PersistedCameraSettings, PersistedPoseIdentity?>>(Channel.UNLIMITED)
        val writer = CameraSnapshotWriter(
            scope = testScope(context),
            persist = { settings, pose -> writes.trySend(settings to pose) },
            debounceMillis = 50L,
            startWorker = false,
        )
        return writer to writes
    }

    private fun pose(id: String) = PersistedPoseIdentity(id, id, "$id.png")
}
