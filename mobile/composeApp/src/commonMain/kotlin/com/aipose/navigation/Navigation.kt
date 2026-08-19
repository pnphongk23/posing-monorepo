package com.aipose.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import org.jetbrains.compose.resources.painterResource
import ai_pose.composeapp.generated.resources.Res
import ai_pose.composeapp.generated.resources.ic_grid
import ai_pose.composeapp.generated.resources.ic_layout_grid
import cafe.adriel.voyager.core.screen.Screen
import cafe.adriel.voyager.navigator.LocalNavigator
import cafe.adriel.voyager.navigator.Navigator
import cafe.adriel.voyager.navigator.currentOrThrow
import cafe.adriel.voyager.navigator.tab.LocalTabNavigator
import cafe.adriel.voyager.navigator.tab.Tab
import cafe.adriel.voyager.navigator.tab.TabOptions
import com.aipose.Pose
import com.aipose.camera.CameraScreen
import com.aipose.data.PreparedPoseReference
import com.aipose.data.PoseServiceLocator
import com.aipose.ui.screens.gallery.GalleryScreen
import com.aipose.ui.screens.gallery.GalleryViewModel
import com.aipose.ui.screens.poses.PoseDetailScreen
import com.aipose.ui.screens.poses.PoseDetailViewModel
import com.aipose.ui.screens.poses.PosesScreen
import com.aipose.ui.screens.poses.PosesViewModel
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import com.aipose.data.PoseReferenceKey
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.screens.poses.SearchScreen

/** Space reserved above the floating [MainDock] so scrollable content is not obscured. */
val MainDockContentInset = 72.dp

val LocalMainDockVisible = compositionLocalOf { true }

/** E-DOCK: stable test tags for the floating dock (overlaid by App.kt on non-Camera tabs). */
internal const val MAIN_DOCK_TEST_TAG = "main-dock"
internal const val MAIN_DOCK_POSES_TEST_TAG = "main-dock-poses"
internal const val MAIN_DOCK_GALLERY_TEST_TAG = "main-dock-gallery"
internal const val MAIN_DOCK_CAMERA_TEST_TAG = "main-dock-camera"

object CameraTab : Tab {
    override val options: TabOptions
        @Composable
        get() {
            val icon = rememberVectorPainter(Icons.Default.CameraAlt)
            return remember {
                TabOptions(
                    index = 0u,
                    title = "Camera",
                    icon = icon
                )
            }
        }

    @Composable
    override fun Content() {
        CameraScreen()
    }
}

object PosesTab : Tab {
    override val options: TabOptions
        @Composable
        get() {
            val icon = rememberVectorPainter(Icons.Default.Person)
            return remember {
                TabOptions(
                    index = 1u,
                    title = "Poses",
                    icon = icon
                )
            }
        }

    @Composable
    override fun Content() {
        Navigator(PosesListScreen())
    }
}

object GalleryTab : Tab {
    override val options: TabOptions
        @Composable
        get() {
            val icon = rememberVectorPainter(Icons.Default.PhotoLibrary)
            return remember {
                TabOptions(
                    index = 2u,
                    title = "Gallery",
                    icon = icon
                )
            }
        }

    @Composable
    override fun Content() {
        Navigator(GalleryListScreen())
    }
}

class GalleryListScreen : Screen {
    @Composable
    override fun Content() {
        val tabNavigator = LocalTabNavigator.current
        GalleryScreen(
            viewModel = remember { GalleryViewModel() },
            onOpenCamera = { tabNavigator.current = CameraTab },
        )
    }
}

/** E-CAM-ENTRY (AD-1): Create Pose (+) / empty-state CTA switches to CameraTab; no extractPose. */
internal fun createPoseCameraEntryAction(setCurrentTab: (Tab) -> Unit): () -> Unit = {
    setCurrentTab(CameraTab)
}

/** E-SEARCH-WIRED: poses-list search icon pushes SearchScreen (Plan 2112 owns search behavior). */
internal fun createSearchNavigationAction(
    pushScreen: (Screen) -> Unit,
    popBack: () -> Unit,
): () -> Unit = {
    pushScreen(
        SearchScreen(
            onPersonalPoseClick = { poseId ->
                pushScreen(PoseDetailVoyagerScreen(PoseReferenceKey.Personal(poseId)))
            },
            onCommunityPoseClick = { communityPose ->
                pushScreen(PoseDetailVoyagerScreen(PoseReferenceKey.Community(communityPose.id)))
            },
            onBack = popBack,
        ),
    )
}

/**
 * E-TRY-EMIT: Try Pose success stores [PreparedPoseReference] and switches to CameraTab.
 * E-2241-BOUNDARY: Camera overlay (`CameraScreen.kt:173` stays `if (false)`) and durable
 * persistence are owned by Plan 260809-2241; WI-04 only emits the typed handoff contract.
 */
internal fun createTryPoseCameraHandoffAction(
    setPreparedReference: (PreparedPoseReference) -> Unit,
    setCurrentTab: (Tab) -> Unit,
): (PreparedPoseReference) -> Unit = { prepared ->
    setPreparedReference(prepared)
    setCurrentTab(CameraTab)
}

class PosesListScreen : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val tabNavigator = LocalTabNavigator.current
        PosesScreen(
            viewModel = remember { PosesViewModel() },
            onPoseClick = { poseId -> navigator.push(PoseDetailVoyagerScreen(PoseReferenceKey.Personal(poseId))) },
            onCommunityPoseClick = { communityPose -> navigator.push(PoseDetailVoyagerScreen(PoseReferenceKey.Community(communityPose.id))) },
            onExtractPoseClick = createPoseCameraEntryAction { tabNavigator.current = it },
            onSearchClick = createSearchNavigationAction(
                pushScreen = { navigator.push(it) },
                popBack = { navigator.pop() },
            ),
        )
    }
}

class PoseDetailVoyagerScreen(
    private val poseKey: PoseReferenceKey
) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val tabNavigator = LocalTabNavigator.current
        PoseDetailScreen(
            poseKey = poseKey,
            viewModel = remember { PoseDetailViewModel(poseKey) },
            onUseWithCamera = createTryPoseCameraHandoffAction(
                setPreparedReference = { PoseServiceLocator.preparedReference = it },
                setCurrentTab = { tabNavigator.current = it },
            ),
            onBack = { navigator.pop() }
        )
    }
}

/**
 * E-DOCK: floating bottom dock matching `docs/prototype` tab-bar — a white pill
 * (Poses + Gallery) plus a standalone pink camera button. Hidden on [CameraTab]
 * by App.kt via [LocalMainDockVisible].
 */
@Composable
fun MainDock(modifier: Modifier = Modifier) {
    val tabNavigator = LocalTabNavigator.current

    Row(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = Spacing.lg, vertical = Spacing.sm)
            .testTag(MAIN_DOCK_TEST_TAG),
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Pill: Poses + Gallery (prototype `.nb-dock__pill`).
        NeoBrutalismContainer(
            modifier = Modifier
                .weight(1f)
                .height(48.dp),
            shape = RoundedCornerShape(24.dp),
            backgroundColor = AiPoseColors.Surface,
            shadowOffset = 2.dp,
            borderWidth = 2.dp
        ) {
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(2.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                DockItem(
                    title = "Poses",
                    icon = painterResource(Res.drawable.ic_grid),
                    isSelected = tabNavigator.current == PosesTab,
                    onClick = { tabNavigator.current = PosesTab },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .testTag(MAIN_DOCK_POSES_TEST_TAG)
                )
                DockItem(
                    title = "Gallery",
                    icon = painterResource(Res.drawable.ic_layout_grid),
                    isSelected = tabNavigator.current == GalleryTab,
                    onClick = { tabNavigator.current = GalleryTab },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .testTag(MAIN_DOCK_GALLERY_TEST_TAG)
                )
            }
        }

        // Standalone camera button (prototype `.nb-dock__camera-btn`).
        NeoBrutalismContainer(
            modifier = Modifier
                .size(48.dp)
                .testTag(MAIN_DOCK_CAMERA_TEST_TAG),
            shape = CircleShape,
            backgroundColor = AiPoseColors.Primary,
            shadowOffset = 2.dp,
            borderWidth = 2.dp,
            onClick = { tabNavigator.current = CameraTab }
        ) {
            Icon(
                imageVector = Icons.Default.CameraAlt,
                contentDescription = "Open Camera",
                tint = AiPoseColors.Foreground,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

/**
 * E-DOCK: one pill item — active state mirrors the prototype
 * (accent-blue chip + thin border + dark icon/label vs gray idle).
 */
@Composable
private fun DockItem(
    title: String,
    icon: Painter,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier = modifier
            .clip(shape)
            .background(
                color = if (isSelected) AiPoseColors.AccentBlue else Color.Transparent,
                shape = shape
            )
            .border(
                width = if (isSelected) 1.dp else 0.dp,
                color = AiPoseColors.Foreground,
                shape = shape
            )
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            painter = icon,
            contentDescription = title,
            tint = if (isSelected) AiPoseColors.Foreground else AiPoseColors.Subtext,
            modifier = Modifier.size(18.dp)
        )
        Text(
            text = title.uppercase(),
            fontSize = 8.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.05.em,
            lineHeight = 10.sp,
            color = if (isSelected) AiPoseColors.Foreground else AiPoseColors.Subtext
        )
    }
}

@Composable
private fun PlaceholderScreen(name: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AiPoseColors.Background),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = name,
            style = AiPoseTypography.Heading1,
            color = AiPoseColors.Foreground
        )
    }
}
