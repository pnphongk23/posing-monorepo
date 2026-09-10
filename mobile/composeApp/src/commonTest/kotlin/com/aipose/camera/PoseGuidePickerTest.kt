package com.aipose.camera

import com.aipose.auth.GoogleSignInResult
import com.aipose.auth.InterruptedIntentStore
import com.aipose.auth.SignInIntent
import com.aipose.auth.SignInPromptController
import com.aipose.data.PoseImageVerification
import com.aipose.data.PreparedPoseReference
import com.aipose.data.remote.CommunityPose
import com.aipose.ui.theme.AiPoseColors
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PoseGuidePickerTest {
    private val pngBytes = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
    )

    @Test
    fun prepareCommunityPoseReference_buildsVerifiedDataUri() = runTest {
        val pose = CommunityPose(
            poseId = "pose-1",
            name = "Standing",
            skeletonUrl = "https://example.com/skeleton.png",
        )
        val prepared = prepareCommunityPoseReference(pose) { _ -> pngBytes }

        assertEquals("pose-1", prepared.poseId)
        assertEquals("Standing", prepared.poseName)
        assertTrue(prepared.skeletonPath.startsWith("data:image/png;base64,"))
        val decoded = PoseImageVerification.decodeDataUriPayload(prepared.skeletonPath)
        assertTrue(decoded != null && PoseImageVerification.isValidImage(decoded))
    }

    @Test
    fun prepareCommunityPoseReference_rejectsInvalidMime() = runTest {
        val pose = CommunityPose(
            poseId = "pose-2",
            name = "Broken",
            skeletonUrl = "https://example.com/skeleton.bin",
        )
        assertFailsWith<IllegalStateException> {
            prepareCommunityPoseReference(pose) { _ -> byteArrayOf(0x00, 0x01, 0x02) }
        }
    }

    @Test
    fun prepareCommunityPoseReference_rejectsBlankSkeletonUrl() = runTest {
        val pose = CommunityPose(poseId = "pose-3", name = "Empty", skeletonUrl = "")
        assertFailsWith<IllegalStateException> {
            prepareCommunityPoseReference(pose) { _ -> pngBytes }
        }
    }

    @Test
    fun guideCardAccentColor_cyclesPrototypePalette() {
        assertEquals(AiPoseColors.Warning, guideCardAccentColor(0))
        assertEquals(AiPoseColors.Primary, guideCardAccentColor(1))
        assertEquals(AiPoseColors.AccentBlue, guideCardAccentColor(2))
        assertEquals(AiPoseColors.Success, guideCardAccentColor(3))
        assertEquals(AiPoseColors.Warning, guideCardAccentColor(4))
    }

    @Test
    fun withVerifiedPoseReference_preservesCameraSettings() {
        val settings = CameraUiState(
            cameraFacing = CameraFacing.FRONT,
            flashMode = FlashMode.ON,
            isGridVisible = true,
            overlayOpacity = 0.7f,
            poseLineColor = PoseLineColor.White,
        )
        val reference = PreparedPoseReference(
            poseId = "guide-1",
            poseName = "Jumping",
            skeletonPath = "data:image/png;base64,iVBORw0KGgo=",
        )
        val updated = settings.withVerifiedPoseReference(reference)

        assertEquals(CameraFacing.FRONT, updated.cameraFacing)
        assertEquals(FlashMode.ON, updated.flashMode)
        assertEquals(true, updated.isGridVisible)
        assertEquals(0.7f, updated.overlayOpacity)
        assertEquals(PoseLineColor.White, updated.poseLineColor)
        assertEquals(OverlaySourceState.PoseImage("guide-1", reference.skeletonPath), updated.overlaySource)
        assertTrue(updated.isOverlayVisible)
    }

    @Test
    fun resumeGuestTryPosePreparation_dismissesSignInBeforeResuming() {
        var dismissed = false
        val pose = CommunityPose(poseId = "guest-1", name = "Guest Pose", skeletonUrl = "https://example.com/s.png")
        val retained = resumeGuestTryPosePreparation(pose) { dismissed = true }
        assertTrue(dismissed)
        assertEquals(pose, retained)
    }

    @Test
    fun tryPoseSignInSuccess_resumesRetainedSelectionOnce() {
        val store = InterruptedIntentStore()
        val launcher = object : com.aipose.auth.GoogleSignInLauncher {
            override fun start(onResult: (GoogleSignInResult) -> Unit) {
                onResult(GoogleSignInResult.Success)
            }
        }
        var dismissed = false
        var resumedPoseId: String? = null
        val pose = CommunityPose(poseId = "guest-2", name = "Retry", skeletonUrl = "https://example.com/r.png")
        val controller = SignInPromptController(launcher, store) { intent ->
            if (intent == SignInIntent.TRY_POSE) {
                val retained = resumeGuestTryPosePreparation(pose) { dismissed = true }
                resumedPoseId = retained?.poseId
            }
        }
        controller.show(SignInIntent.TRY_POSE)
        controller.continueWithGoogle()
        assertTrue(dismissed)
        assertEquals("guest-2", resumedPoseId)
        assertNull(store.pending.value)
    }

    @Test
    fun prepareSelectedPose_failureRetainsSelectionForRetry() = runTest {
        val pose = CommunityPose(poseId = "fail-1", name = "Fail", skeletonUrl = "https://example.com/bad")
        var emitted: PreparedPoseReference? = null
        var lastState: PoseGuidePickerActionState = PoseGuidePickerActionState.Idle
        prepareSelectedPose(
            pose = pose,
            downloadBytes = { _ -> byteArrayOf(0x00) },
            onSuccess = { emitted = it },
            onActionState = { lastState = it },
        )
        assertNull(emitted)
        assertTrue(lastState is PoseGuidePickerActionState.Error)
        assertEquals("fail-1", pose.poseId)
    }

    @Test
    fun planGuidePickerExit_commitsThenGuardsPreviewRestart() {
        val reference = PreparedPoseReference(
            poseId = "exit-1",
            poseName = "Exit",
            skeletonPath = "data:image/png;base64,iVBORw0KGgo=",
        )
        val withCommit = planGuidePickerExit(reference, CameraPermissionState.AUTHORIZED, isAppForeground = true)
        assertEquals(reference, withCommit.committedReference)
        assertTrue(withCommit.shouldStartPreview)

        val backOnly = planGuidePickerExit(null, CameraPermissionState.AUTHORIZED, isAppForeground = true)
        assertNull(backOnly.committedReference)
        assertTrue(backOnly.shouldStartPreview)

        val backgroundBlock = planGuidePickerExit(reference, CameraPermissionState.AUTHORIZED, isAppForeground = false)
        assertEquals(reference, backgroundBlock.committedReference)
        assertFalse(backgroundBlock.shouldStartPreview)

        val denied = planGuidePickerExit(null, CameraPermissionState.DENIED, isAppForeground = true)
        assertFalse(denied.shouldStartPreview)
    }

    @Test
    fun applyVerifiedPickerSelection_updatesOverlayWithoutChangingSettings() {
        val settings = CameraUiState(
            cameraFacing = CameraFacing.FRONT,
            flashMode = FlashMode.AUTO,
            isGridVisible = true,
            overlayOpacity = 0.6f,
        )
        val reference = PreparedPoseReference(
            poseId = "atomic-1",
            poseName = "Atomic",
            skeletonPath = "data:image/png;base64,iVBORw0KGgo=",
        )
        val updated = applyVerifiedPickerSelection(settings, reference)
        assertEquals(settings.cameraFacing, updated.cameraFacing)
        assertEquals(settings.flashMode, updated.flashMode)
        assertEquals(settings.isGridVisible, updated.isGridVisible)
        assertEquals(settings.overlayOpacity, updated.overlayOpacity)
        assertEquals(OverlaySourceState.PoseImage("atomic-1", reference.skeletonPath), updated.overlaySource)
    }
}
