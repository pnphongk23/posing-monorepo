package com.aipose.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
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
import com.aipose.ui.screens.poses.SearchScreen

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
            onBack = { tabNavigator.current = CameraTab },
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
            onBack = { tabNavigator.current = CameraTab }
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

@Composable
fun BottomNavigation() {
    val tabNavigator = LocalTabNavigator.current

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AiPoseColors.Background)
            .padding(Spacing.lg),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        TabItem(
            title = "Camera",
            icon = Icons.Default.CameraAlt,
            isSelected = tabNavigator.current == CameraTab,
            onClick = { tabNavigator.current = CameraTab }
        )
        TabItem(
            title = "Poses",
            icon = Icons.Default.Person,
            isSelected = tabNavigator.current == PosesTab,
            onClick = { tabNavigator.current = PosesTab }
        )
        TabItem(
            title = "Gallery",
            icon = Icons.Default.PhotoLibrary,
            isSelected = tabNavigator.current == GalleryTab,
            onClick = { tabNavigator.current = GalleryTab }
        )
    }
}

@Composable
private fun TabItem(
    title: String,
    icon: ImageVector,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = icon,
            contentDescription = title,
            tint = if (isSelected) AiPoseColors.Primary else AiPoseColors.Subtext
        )
        Spacer(modifier = Modifier.height(Spacing.xs))
        Text(
            text = title.uppercase(),
            style = AiPoseTypography.Caption,
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
