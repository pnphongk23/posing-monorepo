package com.aipose.camera

import com.aipose.data.AiPoseDatabase
import com.aipose.data.PreparedPoseReference
import com.aipose.data.remote.sharedJson
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import androidx.compose.ui.geometry.Offset

private const val CAMERA_SNAPSHOT_VERSION = 1L

@Serializable
data class PersistedCameraSettings(
    val facing: String = CameraFacing.BACK.name,
    val flash: String = FlashMode.OFF.name,
    val grid: Boolean = false,
    val guideVisible: Boolean = true,
    val opacity: Float = 0.5f,
    val lineColor: String = PoseLineColor.Black.name,
    val overlayX: Float = 0f,
    val overlayY: Float = 0f,
    val overlayScale: Float = 1f,
    val zoom: Float = 1f,
)

@Serializable
data class PersistedPoseIdentity(
    val poseId: String,
    val poseName: String,
    val skeletonPath: String,
)

data class RestoredCameraSnapshot(
    val settings: PersistedCameraSettings,
    val pose: PersistedPoseIdentity?,
)

fun PersistedCameraSettings.toCameraUiState(
    permission: CameraPermissionState,
    pose: PreparedPoseReference?,
): CameraUiState = CameraUiState(
    permissionState = permission,
    cameraFacing = runCatching { CameraFacing.valueOf(facing) }.getOrDefault(CameraFacing.BACK),
    flashMode = runCatching { FlashMode.valueOf(flash) }.getOrDefault(FlashMode.OFF),
    isGridVisible = grid,
    isOverlayVisible = guideVisible,
    overlayOpacity = opacity,
    poseLineColor = runCatching { PoseLineColor.valueOf(lineColor) }.getOrDefault(PoseLineColor.Black),
    overlayOffset = Offset(overlayX, overlayY),
    overlayScale = overlayScale,
    overlaySource = pose?.let { OverlaySourceState.PoseImage(it.poseId, it.skeletonPath) }
        ?: OverlaySourceState.None,
)

fun CameraUiState.toPersistedCameraSettings(zoom: Float): PersistedCameraSettings = PersistedCameraSettings(
    facing = cameraFacing.name,
    flash = flashMode.name,
    grid = isGridVisible,
    guideVisible = isOverlayVisible,
    opacity = overlayOpacity,
    lineColor = poseLineColor.name,
    overlayX = overlayOffset.x,
    overlayY = overlayOffset.y,
    overlayScale = overlayScale,
    zoom = zoom,
)

fun PersistedPoseIdentity.toPreparedPoseReferenceIfVerified(): PreparedPoseReference? =
    if (cameraGuideAsset(skeletonPath) is CameraGuideAsset.Invalid) null
    else PreparedPoseReference(poseId, poseName, skeletonPath)

fun PreparedPoseReference.toPersistedPoseIdentity(): PersistedPoseIdentity =
    PersistedPoseIdentity(poseId, poseName, skeletonPath)

/** Durable FEAT-012 snapshot boundary; it never stores CameraUiState itself. */
class CameraSnapshotRepository(
    private val database: AiPoseDatabase,
    private val json: Json = sharedJson,
) {
    private val queries = database.cameraSnapshotQueries

    fun load(): RestoredCameraSnapshot {
        val row = queries.getSnapshot().executeAsOneOrNull() ?: return RestoredCameraSnapshot(
            settings = PersistedCameraSettings(),
            pose = null,
        )
        if (row.schemaVersion != CAMERA_SNAPSHOT_VERSION) {
            return RestoredCameraSnapshot(PersistedCameraSettings(), null)
        }

        val settings = decodeSettings(row.settings_json) ?: PersistedCameraSettings()
        val pose = decodePose(row.pose_json)
        return RestoredCameraSnapshot(settings = settings, pose = pose)
    }

    fun save(settings: PersistedCameraSettings, pose: PersistedPoseIdentity?) {
        queries.upsertSnapshot(
            schemaVersion = CAMERA_SNAPSHOT_VERSION,
            settings_json = json.encodeToString(PersistedCameraSettings.serializer(), settings),
            pose_json = pose?.let { json.encodeToString(PersistedPoseIdentity.serializer(), it) },
        )
    }

    /** Replaces only pose data; existing settings remain untouched. */
    fun replacePose(pose: PersistedPoseIdentity) {
        val encoded = json.encodeToString(PersistedPoseIdentity.serializer(), pose)
        if (queries.getSnapshot().executeAsOneOrNull() == null) {
            save(PersistedCameraSettings(), pose)
        } else {
            queries.updatePose(encoded)
        }
    }

    /** Removes only pose data; it never deletes or publishes a source Pose. */
    fun clearPose() {
        queries.clearPose()
    }

    private fun decodeSettings(raw: String): PersistedCameraSettings? = try {
        json.decodeFromString(PersistedCameraSettings.serializer(), raw).validated()
    } catch (_: SerializationException) {
        null
    } catch (_: IllegalArgumentException) {
        null
    }

    private fun decodePose(raw: String?): PersistedPoseIdentity? = raw?.let {
        try {
            json.decodeFromString(PersistedPoseIdentity.serializer(), it)
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun PersistedCameraSettings.validated(): PersistedCameraSettings? {
        val validFacing = runCatching { CameraFacing.valueOf(facing) }.getOrNull() != null
        val validFlash = runCatching { FlashMode.valueOf(flash) }.getOrNull() != null
        val validColor = runCatching { PoseLineColor.valueOf(lineColor) }.getOrNull() != null
        if (!validFacing || !validFlash || !validColor) return null
        if (!opacity.isFinite() || opacity !in 0f..1f) return null
        if (!overlayX.isFinite() || !overlayY.isFinite() || !overlayScale.isFinite() || overlayScale <= 0f) return null
        if (!zoom.isFinite() || zoom !in 1f..3f) return null
        return this
    }
}
