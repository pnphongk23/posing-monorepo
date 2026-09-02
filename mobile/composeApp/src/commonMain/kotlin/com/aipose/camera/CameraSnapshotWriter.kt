package com.aipose.camera

import com.aipose.data.PoseServiceLocator
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Serializes camera snapshot mutations and coalesces pending settings writes. */
internal class CameraSnapshotWriter(
    scope: CoroutineScope,
    private val save: (PersistedCameraSettings, PersistedPoseIdentity?) -> Unit,
    private val replacePose: (PersistedPoseIdentity) -> Unit = {},
    private val debounceMillis: Long = 250L,
    workerDispatcher: CoroutineDispatcher = Dispatchers.Default,
) {
    private enum class Operation { SAVE, CLEAR, REPLACE }

    private data class Pending(
        val settings: PersistedCameraSettings,
        val pose: PersistedPoseIdentity?,
        val operation: Operation,
        val replaceMustPreserveSettings: Boolean = false,
    )

    private val pending = MutableStateFlow<Pending?>(null)
    private val wakeups = Channel<Unit>(Channel.CONFLATED)
    private val worker: Job = scope.launch(workerDispatcher) {
        for (ignored in wakeups) {
            delay(debounceMillis)
            process(takePending())
        }
    }

    fun save(settings: PersistedCameraSettings, pose: PersistedPoseIdentity?) {
        pending.update { Pending(settings, pose, Operation.SAVE) }
        wakeups.trySend(Unit)
    }

    fun clearPose(settings: PersistedCameraSettings) {
        pending.update { Pending(settings, null, Operation.CLEAR) }
        wakeups.trySend(Unit)
    }

    fun replacePose(pose: PersistedPoseIdentity) {
        pending.update { previous ->
            Pending(
                settings = previous?.settings ?: PersistedCameraSettings(),
                pose = pose,
                operation = Operation.REPLACE,
                replaceMustPreserveSettings = previous != null,
            )
        }
        wakeups.trySend(Unit)
    }

    fun close() {
        wakeups.close()
        worker.cancel()
    }

    private fun takePending(): Pending? {
        while (true) {
            val current = pending.value ?: return null
            if (pending.compareAndSet(current, null)) return current
        }
    }

    private fun process(command: Pending?) {
        when (command?.operation) {
            null -> Unit
            Operation.SAVE -> save(command.settings, command.pose)
            Operation.CLEAR -> save(command.settings, null)
            Operation.REPLACE -> {
                if (command.replaceMustPreserveSettings) save(command.settings, null)
                command.pose?.let(replacePose)
            }
        }
    }
}

/** Process-scoped ordering authority shared by camera and navigation. */
internal object CameraSnapshotPersistence {
    private val scope = CoroutineScope(Dispatchers.Default)
    private val writer by lazy {
        CameraSnapshotWriter(
            scope = scope,
            save = { settings, pose -> repository().save(settings, pose) },
            replacePose = { pose -> repository().replacePose(pose) },
        )
    }

    fun save(settings: PersistedCameraSettings, pose: PersistedPoseIdentity?) = writer.save(settings, pose)

    fun clearPose(settings: PersistedCameraSettings) = writer.clearPose(settings)

    fun replacePose(pose: PersistedPoseIdentity) = writer.replacePose(pose)

    private fun repository(): CameraSnapshotRepository = CameraSnapshotRepository(PoseServiceLocator.database)
}
