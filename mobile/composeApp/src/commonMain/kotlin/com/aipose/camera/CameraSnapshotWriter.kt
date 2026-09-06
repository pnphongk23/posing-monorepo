package com.aipose.camera

import com.aipose.data.PoseServiceLocator
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
    private val persist: (PersistedCameraSettings, PersistedPoseIdentity?) -> Unit,
    private val replacePose: (PersistedPoseIdentity) -> Unit = {},
    private val debounceMillis: Long = 250L,
    startWorker: Boolean = true,
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
    private val worker: Job? = if (startWorker) {
        scope.launch {
            for (ignored in wakeups) {
                delay(debounceMillis)
                process(takePending())
            }
        }
    } else {
        null
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
        worker?.cancel()
    }

    /** Drains the latest coalesced pending command; used by unit tests on hosts without a reliable debounce worker. */
    internal fun flushNow() {
        process(takePending())
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
            Operation.SAVE -> persist(command.settings, command.pose)
            Operation.CLEAR -> persist(command.settings, null)
            Operation.REPLACE -> {
                if (command.replaceMustPreserveSettings) persist(command.settings, null)
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
            persist = { settings, pose -> repository().save(settings, pose) },
            replacePose = { pose -> repository().replacePose(pose) },
        )
    }

    fun save(settings: PersistedCameraSettings, pose: PersistedPoseIdentity?) = writer.save(settings, pose)

    fun clearPose(settings: PersistedCameraSettings) = writer.clearPose(settings)

    fun replacePose(pose: PersistedPoseIdentity) = writer.replacePose(pose)

    private fun repository(): CameraSnapshotRepository = CameraSnapshotRepository(PoseServiceLocator.database)
}
