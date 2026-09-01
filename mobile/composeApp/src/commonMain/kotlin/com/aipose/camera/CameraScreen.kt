package com.aipose.camera

import com.aipose.ui.components.NeoBrutalismContainer
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_refresh_cw
import ai_pose.composeapp.generated.resources.ic_more_horizontal
import ai_pose.composeapp.generated.resources.ic_zap
import ai_pose.composeapp.generated.resources.ic_grid
import ai_pose.composeapp.generated.resources.ic_users

import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import cafe.adriel.voyager.navigator.tab.LocalTabNavigator
import coil3.compose.AsyncImage
import com.aipose.data.PoseServiceLocator
import com.aipose.data.resolveImagePath
import com.aipose.data.DatabaseDriverFactory
import com.aipose.data.DatabaseProvider
import com.aipose.data.ImageStorage
import com.aipose.data.PhotoRepository
import com.aipose.navigation.GalleryTab
import com.aipose.navigation.PosesTab
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import com.aipose.purchases.PaywallScreen
import com.aipose.purchases.PurchaseGateway
import com.aipose.purchases.PurchaseGatewayProvider
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Composable
fun CameraScreen(
    modifier: Modifier = Modifier,
    purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
    onDismiss: () -> Unit = {},
) {
    val tabNavigator = LocalTabNavigator.current
    val purchaseSnapshot by purchaseGateway.snapshot.collectAsState()

    if (!purchaseSnapshot.hasConfirmedPremium) {
        PaywallScreen(
            gateway = purchaseGateway,
            onDismiss = onDismiss,
            modifier = modifier,
        )
        return
    }

    // Native/DB dependencies are assembled here once; the coordinator owns all
    // capture/persistence behavior behind explicit ports (WI-02).
    val cameraController = remember { CameraController() }
    val database = remember { DatabaseProvider.getOrCreate(DatabaseDriverFactory()) }
    val photoRepository = remember { PhotoRepository(database) }
    val imageStorage = remember { ImageStorage() }

    val coordinator = remember {
        CameraCoordinator(
            controller = CameraControllerAdapter(cameraController),
            imageStorage = ImageStorageWriterAdapter(imageStorage),
            photoMetadata = PhotoMetadataAdapter(photoRepository),
            clock = SystemClock(),
            idGenerator = TimestampCounterIdGenerator(SystemClock()),
        )
    }
    val coordState by coordinator.state.collectAsState()

    val preparedReference = PoseServiceLocator.preparedReference
    var uiState by remember(preparedReference) {
        mutableStateOf(
            CameraUiState(
                permissionState = coordState.permission,
                overlaySource = preparedReference?.let {
                    OverlaySourceState.PoseImage(it.poseId, it.skeletonPath)
                } ?: OverlaySourceState.None,
            )
        )
    }
    var zoomUiState by remember {
        mutableStateOf(CameraZoomUiState())
    }
    var flashVisible by remember { mutableStateOf(false) }

    val poseOverlay = uiState.overlaySource as? OverlaySourceState.PoseImage
    val guideAsset = poseOverlay?.let { guide ->
        remember(guide.skeletonPath) { cameraGuideAsset(guide.skeletonPath) }
    }
    val hasOverlay = poseOverlay != null && uiState.isOverlayVisible && guideAsset !is CameraGuideAsset.Invalid

    // Derived render state from the coordinator (WI-02): the composable never
    // performs persistence itself.
    val permissionState = coordState.permission
    val isCaptureInFlight = coordState.isCaptureInFlight
    val cameraControlsEnabled = !isCaptureInFlight && permissionState == CameraPermissionState.AUTHORIZED
    val captureStatus = coordState.statusText()
    val thumbnailState = coordState.thumbnailState()

    fun updateFlashMode(mode: FlashMode) {
        cameraController.setFlashMode(mode)
        uiState = uiState.copy(flashMode = mode)
    }

    fun toggleMoreMenu() {
        uiState = uiState.copy(isMoreMenuVisible = !uiState.isMoreMenuVisible)
    }

    fun toggleGrid() {
        val nextValue = !uiState.isGridVisible
        cameraController.setGridVisible(nextValue)
        uiState = uiState.copy(isGridVisible = nextValue)
    }

    // WI-04 frame-ratio scope: no Maintainer approval was found to expose a
    // user-facing ratio control, so this stays DEVELOPER-ONLY (no UI entry
    // point; not wired to the native AVCaptureSession preset). If a future
    // decision grants user control, wire to Mijick .setResolution().
    fun selectFrameRatio(ratio: CameraFrameRatio) {
        uiState = uiState.copy(frameRatio = ratio, isMoreMenuVisible = false)
    }

    fun flipCamera() {
        cameraController.switchCamera()
        uiState = uiState.copy(
            cameraFacing = if (uiState.cameraFacing == CameraFacing.BACK) CameraFacing.FRONT else CameraFacing.BACK,
        )
    }

    LaunchedEffect(Unit) {
        coordinator.onLaunch()
        coordinator.refreshLatestThumbnail()
        cameraController.setFlashMode(FlashMode.OFF)
    }

    // Start the native preview after permission is authorized, including the
    // initial authorized-entry and the completion of a permission request.
    LaunchedEffect(permissionState) {
        if (permissionState == CameraPermissionState.AUTHORIZED) {
            cameraController.startPreview()
        } else {
            cameraController.stopPreview()
        }
    }

    // WI-04: app background/foreground → cancel in-flight capture, stop/restart
    // the native preview session; the coordinator restores controls on re-entry.
    DisposableEffect(coordinator) {
        val cancel = observeAppLifecycle(
            onBackground = {
                coordinator.onBackground()
                cameraController.stopPreview()
            },
            onForeground = {
                coordinator.onForeground()
                cameraController.startPreview()
            },
        )
        onDispose { cancel() }
    }

    // Capture timeout: invalidate the in-flight capture after the coordinator
    // timeout window; late native callbacks are then ignored by the coordinator.
    LaunchedEffect(coordState.phase) {
        val phase = coordState.phase
        if (phase is CameraPhase.Capturing) {
            delay(coordinator.captureTimeoutMillis)
            coordinator.onCaptureTimeoutTick()
        } else if (phase is CameraPhase.CaptureSucceeded || phase is CameraPhase.CaptureError) {
            delay(600)
            coordinator.dismissResult()
        }
    }

    LaunchedEffect(flashVisible) {
        if (flashVisible) {
            // WI-03: align capture-flash duration to the prototype's ~250ms
            // white overlay (prototype reference app.js:300-312).
            delay(250)
            flashVisible = false
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(AiPoseColors.SurfaceVariant),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(14.dp))
                .border(2.dp, AiPoseColors.Foreground, RoundedCornerShape(14.dp))
        ) {
            CameraPreview(
                modifier = Modifier.fillMaxSize(),
                controller = cameraController,
            )

            // Overlays — explicit UI states (WI-03).
            // Static face guide mirrors the prototype and is replaced by the
            // verified selected skeleton when a PreparedPoseReference exists.
            if (poseOverlay == null) {
                CenterCrosshair()
            }

            // Grid overlay — rule-of-thirds; default OFF, enabled via
            // more/settings popup (grid default OFF production correction).
            if (uiState.isGridVisible) {
                CameraGridOverlay()
            }

            // The prepared reference is session-scoped and already verified by
            // Try Pose. Render it above the preview without intercepting camera
            // gestures or changing capture semantics.
            if (poseOverlay != null && guideAsset is CameraGuideAsset.Invalid) {
                CameraGuideUnavailable(message = guideAsset.message)
            }

            if (hasOverlay && guideAsset != null) {
                AsyncImage(
                    model = when (guideAsset) {
                        is CameraGuideAsset.Bytes -> guideAsset.value
                        is CameraGuideAsset.LocalFile -> guideAsset.path
                        is CameraGuideAsset.Invalid -> null
                    },
                    contentDescription = "Pose guide: ${preparedReference?.poseName ?: "selected pose"}",
                    contentScale = ContentScale.Fit,
                    colorFilter = uiState.poseLineColor.toColorFilter(),
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp)
                        .offset {
                            IntOffset(
                                uiState.overlayOffset.x.roundToInt(),
                                uiState.overlayOffset.y.roundToInt(),
                            )
                        }
                        .pointerInput(poseOverlay.poseId) {
                            detectTransformGestures { _, pan, zoom, _ ->
                                uiState = uiState.copy(
                                    overlayOffset = uiState.overlayOffset + pan,
                                    overlayScale = (uiState.overlayScale * zoom).coerceIn(0.4f, 2.5f),
                                )
                            }
                        }
                        .graphicsLayer {
                            alpha = uiState.overlayOpacity
                            scaleX = uiState.overlayScale
                            scaleY = uiState.overlayScale
                        },
                )
            }

            // Top Left — close returns to the Poses tab without changing the
            // current-session prepared reference.
            CameraCloseButton(
                modifier = Modifier.align(Alignment.TopStart).statusBarsPadding().padding(16.dp),
                onClick = onDismiss,
            )

            // Top Right — More/settings; behind the status bar/notch.
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .statusBarsPadding()
                    .padding(top = 8.dp, end = 12.dp)
            ) {
                CameraMoreButton(
                    enabled = cameraControlsEnabled,
                    onClick = { uiState = uiState.copy(isMoreMenuVisible = !uiState.isMoreMenuVisible) }
                )
            }

            if (uiState.isMoreMenuVisible) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .statusBarsPadding()
                        .padding(top = 60.dp, end = 12.dp)
                ) {
                    Popup(
                        alignment = Alignment.TopEnd,
                        onDismissRequest = { uiState = uiState.copy(isMoreMenuVisible = false) },
                        properties = PopupProperties(focusable = true)
                    ) {
                        CameraMorePopup(
                            modifier = Modifier.width(220.dp),
                            uiState = uiState,
                            hasPoseGuide = poseOverlay != null,
                            onFlashSelected = { mode: FlashMode ->
                                updateFlashMode(mode)
                                uiState = uiState.copy(isMoreMenuVisible = false)
                            },
                            onToggleGrid = {
                                toggleGrid()
                                uiState = uiState.copy(isMoreMenuVisible = false)
                            },
                            onTogglePoseGuide = { uiState = uiState.copy(isOverlayVisible = !uiState.isOverlayVisible) },
                            onOpacityChanged = { uiState = uiState.copy(overlayOpacity = it) },
                            poseLineColor = uiState.poseLineColor,
                            onColorChanged = { uiState = uiState.copy(poseLineColor = it) },
                            onFrameRatioSelected = { ratio: CameraFrameRatio -> selectFrameRatio(ratio) }
                        )
                    }
                }
            }

            // Bottom Right
            CameraUsersButton(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 12.dp, bottom = 12.dp),
                onClick = if (cameraControlsEnabled) onDismiss else null
            )

            // Bottom Center
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 12.dp)
            ) {
                CameraZoomIndicator(
                    value = zoomUiState.zoomValue,
                    enabled = cameraControlsEnabled,
                    onClick = { zoomUiState = toggleCameraZoomSlider(zoomUiState) }
                )
            }

            if (zoomUiState.isZoomSliderVisible) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 60.dp)
                ) {
                    Popup(
                        alignment = Alignment.BottomCenter,
                        onDismissRequest = { zoomUiState = zoomUiState.copy(isZoomSliderVisible = false) },
                        properties = PopupProperties(focusable = true)
                    ) {
                        CameraZoomSlider(
                            value = zoomUiState.zoomValue,
                            onValueChange = {
                                zoomUiState = setCameraZoomValue(zoomUiState, it)
                                cameraController.setZoomFactor(zoomUiState.zoomValue)
                            }
                        )
                    }
                }
            }

            if (flashVisible) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(AiPoseColors.Surface.copy(alpha = 0.25f)),
                )
            }
        }

        // Shutter bar: gallery thumbnail 48dp | capture 64dp | flip 48dp
        // (prototype layout reference). Home-indicator safe area via
        // navigationBarsPadding (WI-03).
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(110.dp)
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GalleryThumbnailButton(
                thumbnailState = thumbnailState,
                onClick = if (cameraControlsEnabled) { { tabNavigator.current = GalleryTab } } else null,
            )

            CaptureButton(
                enabled = !isCaptureInFlight && permissionState == CameraPermissionState.AUTHORIZED,
                onClick = {
                    val accepted = coordinator.onCaptureRequested()
                    if (accepted) {
                        flashVisible = true
                    }
                },
            )

            FlipShortcutButton(enabled = cameraControlsEnabled, onClick = ::flipCamera)
        }

        // Status text comes last in composition order → VoiceOver traversal
        // follows preview → controls → shutter bar → status (WI-03).
        if (captureStatus != null) {
            Text(
                text = captureStatus,
                color = AiPoseColors.Foreground,
                style = AiPoseTypography.Caption,
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp, bottom = 8.dp),
            )
        }

        if (permissionState == CameraPermissionState.DENIED || permissionState == CameraPermissionState.RESTRICTED) {
            PermissionDeniedOverlay(controller = cameraController)
        }
    }
}
@Composable
private fun CameraGridOverlay() {
    Canvas(
        modifier = Modifier.fillMaxSize().semantics {
            contentDescription = "Camera grid, 3 by 3 rule of thirds"
        },
    ) {
        val lineColor = AiPoseColors.Surface.copy(alpha = 0.3f)
        drawLine(lineColor, androidx.compose.ui.geometry.Offset(size.width / 3f, 0f), androidx.compose.ui.geometry.Offset(size.width / 3f, size.height), 1.dp.toPx())
        drawLine(lineColor, androidx.compose.ui.geometry.Offset(size.width * 2f / 3f, 0f), androidx.compose.ui.geometry.Offset(size.width * 2f / 3f, size.height), 1.dp.toPx())
        drawLine(lineColor, androidx.compose.ui.geometry.Offset(0f, size.height / 3f), androidx.compose.ui.geometry.Offset(size.width, size.height / 3f), 1.dp.toPx())
        drawLine(lineColor, androidx.compose.ui.geometry.Offset(0f, size.height * 2f / 3f), androidx.compose.ui.geometry.Offset(size.width, size.height * 2f / 3f), 1.dp.toPx())
    }
}

@Composable
private fun CenterCrosshair() {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.fillMaxSize().alpha(0.9f),
    ) {
        Box(
            modifier = Modifier
                .size(140.dp)
                .offset(y = (-48).dp),
        ) {
            Box(
                modifier = Modifier
                    .size(70.dp)
                    .align(Alignment.Center)
                    .border(2.dp, AiPoseColors.Surface.copy(alpha = 0.9f), CircleShape)
                    .background(AiPoseColors.Surface.copy(alpha = 0.1f), CircleShape),
            )
            FaceGuideLine(Modifier.align(Alignment.BottomStart).offset(x = 30.dp, y = (-17).dp).graphicsLayer { rotationZ = 35f })
            FaceGuideLine(Modifier.align(Alignment.BottomEnd).offset(x = (-30).dp, y = (-17).dp).graphicsLayer { rotationZ = -35f })
            FaceGuideLine(Modifier.align(Alignment.BottomCenter).offset(y = (-7).dp).height(35.dp))
            FaceGuideLine(Modifier.align(Alignment.BottomStart).offset(x = 42.dp, y = (-20).dp).height(35.dp).graphicsLayer { rotationZ = 15f })
            FaceGuideLine(Modifier.align(Alignment.BottomEnd).offset(x = (-42).dp, y = (-20).dp).height(35.dp).graphicsLayer { rotationZ = -15f })
        }
    }
}

@Composable
private fun FaceGuideLine(modifier: Modifier = Modifier) {
    Box(modifier = modifier.width(2.dp).height(48.dp).background(AiPoseColors.Surface.copy(alpha = 0.9f)))
}

@Composable
private fun CameraGuideUnavailable(message: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Pose guide unavailable\\n$message",
            color = AiPoseColors.Surface,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.semantics {
                contentDescription = "Pose guide unavailable: $message"
            },
        )
    }
}

@Composable
private fun CameraCloseButton(
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    NeoBrutalismContainer(
        modifier = modifier.semantics {
            testTag = "camera-close-btn"
            contentDescription = "Close Camera"
        }.size(44.dp),
        shape = RoundedCornerShape(10.dp),
        backgroundColor = AiPoseColors.Surface,
        shadowColor = AiPoseColors.Foreground,
        shadowOffset = 3.dp,
        onClick = onClick,
    ) {
        Text("×", color = AiPoseColors.Foreground, fontSize = 26.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun CameraMoreButton(
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    NeoBrutalismContainer(
        modifier = modifier.semantics {
            testTag = "overlayAction_More"
            contentDescription = "Camera Settings"
        }.size(44.dp),
        shape = RoundedCornerShape(10.dp),
        backgroundColor = AiPoseColors.Surface,
        shadowColor = AiPoseColors.Foreground,
        shadowOffset = 2.dp,
        onClick = if (enabled) onClick else null
    ) {
        Box(
            modifier = Modifier.fillMaxSize().alpha(if (enabled) 1f else 0.45f),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painter = painterResource(Res.drawable.ic_more_horizontal),
                contentDescription = "More Options",
                tint = AiPoseColors.Foreground,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@Composable
private fun CameraUsersButton(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)?,
) {
    NeoBrutalismContainer(
        modifier = modifier.semantics {
            testTag = "poseButton"
            contentDescription = "Browse poses"
        }.size(48.dp),
        shape = CircleShape,
        backgroundColor = AiPoseColors.AccentBlue,
        shadowColor = AiPoseColors.Foreground,
        shadowOffset = 2.dp,
        onClick = onClick
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painter = painterResource(Res.drawable.ic_users),
                contentDescription = "Browse poses",
                tint = AiPoseColors.Foreground,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@Composable
private fun CameraZoomIndicator(
    modifier: Modifier = Modifier,
    value: Float,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    NeoBrutalismContainer(
        modifier = modifier.semantics { testTag = "zoomButton" }.size(44.dp),
        shape = CircleShape,
        backgroundColor = AiPoseColors.SurfaceVariant,
        shadowColor = AiPoseColors.Foreground,
        shadowOffset = 2.dp,
        onClick = if (enabled) onClick else null
    ) {
        Box(
            modifier = Modifier.fillMaxSize().alpha(if (enabled) 1f else 0.45f),
            contentAlignment = Alignment.Center,
        ) {
            Text(cameraZoomLabel(value), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AiPoseColors.Foreground)
        }
    }
}

@Composable
private fun CameraZoomSlider(
    modifier: Modifier = Modifier,
    value: Float,
    onValueChange: (Float) -> Unit,
) {
    Column(
        modifier = modifier
            .semantics(mergeDescendants = true) {
                testTag = "zoomSlider"
                contentDescription = "zoomSlider"
            }
            .clickable(onClick = {})
            .width(180.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(AiPoseColors.Foreground)
            .border(2.dp, AiPoseColors.Foreground, RoundedCornerShape(18.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(cameraZoomLabel(value), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = AiPoseColors.Surface)
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = 1f..3f,
        )
    }
}

@Composable
private fun OverlayPlaceholder(
    modifier: Modifier,
    scale: Float,
) {
    Box(
        modifier = modifier.size((220f * scale).dp, (300f * scale).dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .border(2.dp, AiPoseColors.Surface.copy(alpha = 0.9f), CircleShape),
            )
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .height(80.dp)
                    .background(AiPoseColors.Surface.copy(alpha = 0.9f)),
            )
        }
    }
}

@Composable
private fun PermissionDeniedOverlay(
    controller: CameraController,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AiPoseColors.Foreground.copy(alpha = 0.7f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Camera permission required", style = AiPoseTypography.Heading2, color = AiPoseColors.Surface)
            Spacer(modifier = Modifier.height(Spacing.md))
            Button(onClick = { controller.openAppSettings() }) {
                Text("Open Settings")
            }
        }
    }
}

@Composable
private fun CaptureButton(
    enabled: Boolean,
    onClick: () -> Unit,
) {
    NeoBrutalismContainer(
        modifier = Modifier
            .size(72.dp)
            .semantics {
                testTag = "camera-capture-btn"
                contentDescription = if (enabled) "Capture photo" else "Capture photo unavailable"
            },
        shape = RoundedCornerShape(18.dp),
        backgroundColor = AiPoseColors.Primary,
        shadowColor = AiPoseColors.Foreground,
        shadowOffset = 5.dp,
        onClick = if (enabled) onClick else null
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(4.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(AiPoseColors.Primary)
                .border(2.dp, AiPoseColors.Foreground, RoundedCornerShape(18.dp))
                .alpha(if (enabled) 1f else 0.35f),
        )
    }
}

@Composable
private fun GalleryThumbnailButton(
    thumbnailState: ThumbnailState,
    onClick: (() -> Unit)?,
) {
    NeoBrutalismContainer(
        modifier = Modifier.size(48.dp).semantics {
            testTag = "camera-gallery-thumbnail"
            contentDescription = if (thumbnailState is ThumbnailState.Available) "Open Gallery, latest photo available" else "Open Gallery, no latest photo"
        },
        shape = RoundedCornerShape(10.dp),
        backgroundColor = AiPoseColors.SurfaceVariant,
        shadowColor = AiPoseColors.Warning,
        shadowOffset = 3.dp,
        onClick = onClick
    ) {
        when (thumbnailState) {
            is ThumbnailState.Available -> {
                var thumbnailFailed by remember(thumbnailState.imagePath) { mutableStateOf(false) }
                if (!thumbnailFailed) {
                    AsyncImage(
                        model = resolveImagePath(thumbnailState.imagePath) ?: thumbnailState.imagePath,
                        contentDescription = "Latest captured photo",
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(RoundedCornerShape(10.dp))
                            .border(2.dp, AiPoseColors.Foreground, RoundedCornerShape(10.dp)),
                        onError = { thumbnailFailed = true }
                    )
                } else {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("!", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = AiPoseColors.Error)
                    }
                }
            }
            ThumbnailState.Empty -> Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text("G", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = AiPoseColors.Foreground)
            }
        }
    }
}

@Composable
private fun FlipShortcutButton(enabled: Boolean = true, onClick: () -> Unit) {
    NeoBrutalismContainer(
        modifier = Modifier.size(48.dp).semantics { testTag = "camera-flip-btn" },
        shape = RoundedCornerShape(10.dp),
        backgroundColor = AiPoseColors.Surface,
        shadowColor = AiPoseColors.Foreground,
        shadowOffset = 3.dp,
        onClick = if (enabled) onClick else null
    ) {
        Icon(
            painter = painterResource(Res.drawable.ic_refresh_cw),
            contentDescription = "Switch camera facing",
            tint = AiPoseColors.Foreground,
            modifier = Modifier.size(22.dp)
        )
    }
}

@Composable
private fun CameraMorePopup(
    modifier: Modifier = Modifier,
    uiState: CameraUiState,
    hasPoseGuide: Boolean,
    onFlashSelected: (FlashMode) -> Unit,
    onToggleGrid: () -> Unit,
    onTogglePoseGuide: () -> Unit,
    onOpacityChanged: (Float) -> Unit,
    poseLineColor: PoseLineColor,
    onColorChanged: (PoseLineColor) -> Unit,
    onFrameRatioSelected: (CameraFrameRatio) -> Unit,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(AiPoseColors.Foreground)
            .border(2.dp, AiPoseColors.Foreground, RoundedCornerShape(14.dp))
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        NeoBrutalismContainer(
            modifier = Modifier.fillMaxWidth().height(44.dp).semantics {
                contentDescription = "Flash ${uiState.flashMode.name.lowercase()}, tap to change"
            },
            shape = RoundedCornerShape(10.dp),
            backgroundColor = AiPoseColors.Surface,
            shadowColor = AiPoseColors.Surface,
            shadowOffset = 2.dp,
            onClick = {
                val nextMode = when (uiState.flashMode) {
                    FlashMode.OFF -> FlashMode.AUTO
                    FlashMode.AUTO -> FlashMode.ON
                    FlashMode.ON -> FlashMode.OFF
                }
                onFlashSelected(nextMode)
            },
        ) {
            Row(
                modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(painter = painterResource(Res.drawable.ic_zap), contentDescription = null, tint = AiPoseColors.Foreground, modifier = Modifier.size(18.dp))
                    Text("Flash", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AiPoseColors.Foreground)
                }
                Text(uiState.flashMode.name, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AiPoseColors.Primary900)
            }
        }

        NeoBrutalismContainer(
            modifier = Modifier.fillMaxWidth().height(44.dp).semantics {
                contentDescription = "Grid ${if (uiState.isGridVisible) "on" else "off"}, tap to toggle"
            },
            shape = RoundedCornerShape(10.dp),
            backgroundColor = AiPoseColors.Surface,
            shadowColor = AiPoseColors.Surface,
            shadowOffset = 2.dp,
            onClick = onToggleGrid,
        ) {
            Row(
                modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(painter = painterResource(Res.drawable.ic_grid), contentDescription = null, tint = AiPoseColors.Foreground, modifier = Modifier.size(18.dp))
                    Text("Grid", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AiPoseColors.Foreground)
                }
                Text(if (uiState.isGridVisible) "ON" else "OFF", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AiPoseColors.Primary900)
            }
        }

        if (hasPoseGuide) {
            Box(modifier = Modifier.fillMaxWidth().height(2.dp).background(AiPoseColors.Surface.copy(alpha = 0.2f)))
            Text("Pose guide", color = AiPoseColors.Surface, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            NeoBrutalismContainer(
                modifier = Modifier.fillMaxWidth().height(44.dp).semantics {
                    contentDescription = if (uiState.isOverlayVisible) "Hide pose guide" else "Show pose guide"
                },
                shape = RoundedCornerShape(10.dp),
                backgroundColor = AiPoseColors.Surface,
                shadowColor = AiPoseColors.Surface,
                shadowOffset = 2.dp,
                onClick = onTogglePoseGuide,
            ) {
                Text(if (uiState.isOverlayVisible) "Hide" else "Show", color = AiPoseColors.Foreground, fontSize = 13.sp)
            }
            Text("Opacity ${(uiState.overlayOpacity * 100).roundToInt()}%", color = AiPoseColors.Surface, fontSize = 12.sp)
            Slider(
                value = uiState.overlayOpacity,
                onValueChange = onOpacityChanged,
                valueRange = 0.1f..1f,
                modifier = Modifier.semantics {
                    contentDescription = "Pose guide opacity ${(uiState.overlayOpacity * 100).roundToInt()} percent"
                },
            )
            Text("Line color", color = AiPoseColors.Surface, fontSize = 12.sp)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                listOf(PoseLineColor.Black, PoseLineColor.White).forEach { colorOption ->
                    val selected = poseLineColor == colorOption
                    NeoBrutalismContainer(
                        modifier = Modifier
                            .weight(1f)
                            .height(44.dp)
                            .semantics {
                                contentDescription = "Line color ${colorOption.name}, ${if (selected) "selected" else "not selected"}"
                            },
                        shape = RoundedCornerShape(10.dp),
                        backgroundColor = if (selected) AiPoseColors.Primary900 else AiPoseColors.Surface,
                        shadowColor = AiPoseColors.Surface,
                        shadowOffset = 2.dp,
                        onClick = { onColorChanged(colorOption) },
                    ) {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = colorOption.name,
                                color = if (selected) AiPoseColors.Surface else AiPoseColors.Foreground,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }
            }
        }
    }
}
