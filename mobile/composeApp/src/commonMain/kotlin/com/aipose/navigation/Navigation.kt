package com.aipose.navigation

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
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
import com.aipose.Photo
import com.aipose.auth.SignInIntent
import com.aipose.auth.SignInPrompt
import com.aipose.auth.SignInPromptController
import com.aipose.auth.hasValidStoredSession
import com.aipose.auth.platformGoogleSignInLauncher
import com.aipose.camera.CameraScreen
import com.aipose.camera.CameraSnapshotPersistence
import com.aipose.camera.toPersistedPoseIdentity
import com.aipose.data.resolveImagePath
import com.aipose.data.PreparedPoseReference
import com.aipose.data.PoseServiceLocator
import com.aipose.platform.shareImage
import com.aipose.purchases.PaywallScreen
import com.aipose.purchases.PurchaseGatewayProvider
import com.aipose.settings.SettingsDestinationResult
import com.aipose.ui.screens.gallery.GalleryScreen
import com.aipose.ui.screens.gallery.GalleryViewModel
import com.aipose.ui.screens.gallery.GalleryPhotoDetailScreen
import com.aipose.ui.screens.gallery.mapGalleryDeletePhotoResult
import com.aipose.ui.screens.poses.PoseDetailScreen
import com.aipose.ui.screens.poses.PoseDetailViewModel
import com.aipose.ui.screens.poses.PosePreview
import com.aipose.ui.screens.poses.PosesScreen
import com.aipose.ui.screens.poses.PosesViewModel
import com.aipose.ui.screens.poses.SavedScreen
import com.aipose.ui.screens.poses.SavedViewModel
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.screens.poses.SearchScreen

/** Space reserved above the floating [MainDock] so scrollable content is not obscured. */
val MainDockContentInset = 72.dp

val LocalMainDockVisible = compositionLocalOf { true }
/** Approved App-root seam for returning Camera to the tab active before entry. */
val LocalCameraDismiss = compositionLocalOf<() -> Unit> { {} }

/** E-DOCK: stable test tags for the floating dock (overlaid by App.kt on non-Camera tabs). */
internal const val MAIN_DOCK_TEST_TAG = "main-dock"
internal const val MAIN_DOCK_POSES_TEST_TAG = "main-dock-poses"
internal const val MAIN_DOCK_GALLERY_TEST_TAG = "main-dock-gallery"
internal const val MAIN_DOCK_CAMERA_TEST_TAG = "main-dock-camera"

// ── Pop-first persistent list state ───────────────────────────────────────────
//
// Each list's data owner (ViewModel) + scroll/viewport state are hoisted ABOVE the
// nested per-tab [Navigator]. The tab owner composes the holder with `remember` once;
// when a detail screen is pushed and then popped, the list [Screen] re-enters
// composition with the SAME holder — so the ViewModel and exact first-visible index
// + pixel offset survive. List screens re-collect their data when they re-enter.
// One mechanism for Pose and Gallery. The Poses holder is Community-only (the My
// Poses tab was removed).

/**
 * Community initial-load guard: auto-load only when the feed has never loaded
 * (no items). Community is the only Poses pane (the tab bar was removed), so
 * there is no selected-tab check anymore. After ordinary Back the hoisted state
 * keeps items, so this returns false and no duplicate initial load happens.
 */
internal fun shouldAutoLoadCommunity(hasItems: Boolean): Boolean = !hasItems

/** Hoisted Poses-tab list state (survives detail push/pop). */
class PosesListStateHolder(
    val viewModel: PosesViewModel,
    val communityGridState: LazyStaggeredGridState,
) {
    companion object {
        fun create(
            viewModel: PosesViewModel = PosesViewModel(),
            communityGridState: LazyStaggeredGridState = LazyStaggeredGridState(),
        ): PosesListStateHolder =
            PosesListStateHolder(viewModel, communityGridState)
    }
}

/** Hoisted Saved-list state (survives detail push/pop without reloading). */
class SavedListStateHolder(
    val viewModel: SavedViewModel,
    val gridState: LazyStaggeredGridState,
) {
    companion object {
        fun create(
            viewModel: SavedViewModel = SavedViewModel(),
            gridState: LazyStaggeredGridState = LazyStaggeredGridState(),
        ): SavedListStateHolder =
            SavedListStateHolder(viewModel, gridState)
    }
}

/** Hoisted Gallery-tab list state (survives detail push/pop). */
class GalleryListStateHolder(
    val viewModel: GalleryViewModel,
    val gridState: LazyGridState,
) {
    companion object {
        fun create(
            viewModel: GalleryViewModel = GalleryViewModel(),
            gridState: LazyGridState = LazyGridState(),
        ): GalleryListStateHolder = GalleryListStateHolder(viewModel, gridState)
    }
}

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
        CameraScreen(onDismiss = LocalCameraDismiss.current)
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
        // State hoisted here (above the Navigator): detail push/pop never recreates
        // the list ViewModel, its DB collectors, or the grid viewport. The Saved
        // holder is hoisted the same way so the Signed-in Saved grid also survives
        // detail push/pop without reloading.
        val state = remember { PosesListStateHolder.create() }
        val savedState = remember { SavedListStateHolder.create() }
        Navigator(PosesListScreen(state, savedState))
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
        // State hoisted here (above the Navigator): detail push/pop never recreates
        // the list ViewModel, its DB collectors, or the grid viewport.
        val state = remember { GalleryListStateHolder.create() }
        Navigator(GalleryListScreen(state))
    }
}

class GalleryListScreen(private val state: GalleryListStateHolder) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val tabNavigator = LocalTabNavigator.current
        Box(Modifier.fillMaxSize()) {
            GalleryScreen(
                viewModel = state.viewModel,
                gridState = state.gridState,
                onOpenCamera = { tabNavigator.current = CameraTab },
                onPhotoClick = { photo ->
                    val detailPhotos = state.viewModel.uiState.value.photos
                        .takeIf { candidates -> candidates.any { it.id == photo.id } }
                        ?: listOf(photo)
                    navigator.push(
                        GalleryDetailVoyagerScreen(
                            photos = detailPhotos,
                            initialPhotoId = photo.id,
                            onDeletePhoto = { id -> state.viewModel.deletePhoto(id) },
                        ),
                    )
                },
            )
            MainDock(modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

class GalleryDetailVoyagerScreen(
    private val photos: List<Photo>,
    private val initialPhotoId: Long,
    private val onDeletePhoto: suspend (Long) -> Unit,
) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        var backOwned by remember { mutableStateOf(false) }
        GalleryPhotoDetailScreen(
            photos = photos,
            initialPhotoId = initialPhotoId,
            onBack = {
                // Pop-first: request the reverse and perform the exactly-one pop
                // immediately. The root overlay owns the reverse completion + cleanup;
                // this detail scope never awaits it (pop disposes this screen). A rapid
                // duplicate press during an active reverse (or a no-source immediate
                // pop) resolves to NONE and performs no second navigator.pop().
                val owned = backOwned
                backOwned = true
                when (resolveBackAction(owned, MatchedImageTransitionState.requestReverse())) {
                    BackDecision.REVERSE_POP -> navigator.pop()
                    BackDecision.POP -> navigator.pop()
                    BackDecision.NONE -> backOwned = owned
                }
            },
            onDelete = { id -> mapGalleryDeletePhotoResult(onDeletePhoto, id) },
            onSave = { selected ->
                val path = resolveImagePath(selected.imagePath) ?: selected.imagePath
                com.aipose.platform.saveToPhotos(path, null)
            },
            onShare = { selected ->
                val path = resolveImagePath(selected.imagePath) ?: selected.imagePath
                shareImage(path, null)
            },
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
            onLocalPoseClick = { preview ->
                pushScreen(PoseDetailVoyagerScreen(preview))
            },
            onPublishedPoseClick = { preview ->
                pushScreen(PoseDetailVoyagerScreen(preview))
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

internal fun createPremiumPaywallNavigationAction(
    pushPaywall: () -> Unit,
): () -> SettingsDestinationResult = {
    pushPaywall()
    SettingsDestinationResult.Opened
}

/** Full-screen paid-access owner pushed above Settings on the existing Voyager stack. */
internal class PremiumPaywallVoyagerScreen : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        PaywallScreen(
            gateway = PurchaseGatewayProvider.current,
            onDismiss = { navigator.pop() },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

class PosesListScreen(
    private val state: PosesListStateHolder,
    private val savedState: SavedListStateHolder,
) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val tabNavigator = LocalTabNavigator.current
        val signInController = remember { SignInPromptController(platformGoogleSignInLauncher()) { intent ->
            // Resume the single-use interrupted intent: push the Signed-in Saved list.
            if (intent == SignInIntent.OPEN_SAVED) navigator.push(SavedListVoyagerScreen(savedState))
        } }
        var showSignIn by remember { mutableStateOf(false) }
        val settingsHostActions = SettingsHostActions(
            onSavedClick = {
                navigator.push(SavedListVoyagerScreen(savedState))
                SettingsDestinationResult.Opened
            },
            onPremiumClick = createPremiumPaywallNavigationAction {
                navigator.push(PremiumPaywallVoyagerScreen())
            },
        )
        Box(Modifier.fillMaxSize()) {
        PosesScreen(
            viewModel = state.viewModel,
            communityGridState = state.communityGridState,
            onPublishedPoseClick = { preview -> navigator.push(PoseDetailVoyagerScreen(preview, origin = PoseDetailOrigin.COMMUNITY)) },
            onExtractPoseClick = createPoseCameraEntryAction { tabNavigator.current = it },
            onSearchClick = createSearchNavigationAction(
                pushScreen = { navigator.push(it) },
                popBack = { navigator.pop() },
            ),
            onSavedClick = {
                if (hasValidStoredSession()) {
                    navigator.push(SavedListVoyagerScreen(savedState))
                } else {
                    signInController.show(SignInIntent.OPEN_SAVED)
                    showSignIn = true
                }
            },
            onSettingsClick = { navigator.push(SettingsVoyagerScreen(settingsHostActions)) },
        )
        MainDock(modifier = Modifier.align(Alignment.BottomCenter))
        }
        SignInPrompt(
            controller = signInController,
            visible = showSignIn && signInController.state.value.intent == SignInIntent.OPEN_SAVED,
            onDismiss = { showSignIn = false },
        )
    }
}

/** WI-04: where the detail was opened from, driving unavailable-state back copy. */
enum class PoseDetailOrigin { COMMUNITY, SAVED }

class PoseDetailVoyagerScreen(
    private val previewItem: PosePreview,
    private val origin: PoseDetailOrigin = PoseDetailOrigin.COMMUNITY,
    private val initialSaved: Boolean = false,
    private val savedState: SavedListStateHolder? = null,
) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val tabNavigator = LocalTabNavigator.current
        var backOwned by remember { mutableStateOf(false) }
        val detailViewModel = remember {
            PoseDetailViewModel(
                poseId = previewItem.poseId,
                initialSaved = initialSaved,
                origin = origin,
                initialCommunityPose = previewItem.communityPose,
            )
        }
        val signInController = remember {
            SignInPromptController(platformGoogleSignInLauncher()) { intent ->
                when (intent) {
                    SignInIntent.SAVE_POSE -> {
                        if (detailViewModel.signInRequired.value) {
                            // 401 recovery (no interrupted Save): clear + reload, no auto-mutate.
                            detailViewModel.reloadAfterSignIn()
                        } else {
                            detailViewModel.resumeSignInIntent(onTrySuccess = {})
                        }
                    }
                    SignInIntent.TRY_POSE -> detailViewModel.resumeSignInIntent { prepared ->
                        PoseServiceLocator.preparedReference = prepared
                        CameraSnapshotPersistence.replacePose(prepared.toPersistedPoseIdentity())
                        tabNavigator.current = CameraTab
                    }
                    SignInIntent.OPEN_ACCOUNT -> Unit
                    SignInIntent.OPEN_SAVED -> if (savedState != null) navigator.push(SavedListVoyagerScreen(savedState))
                }
            }
        }
        var showSignIn by remember { mutableStateOf(false) }
        PoseDetailScreen(
            poseId = previewItem.poseId,
            preview = previewItem,
            viewModel = detailViewModel,
            origin = origin,
            onUseWithCamera = createTryPoseCameraHandoffAction(
                setPreparedReference = {
                    PoseServiceLocator.preparedReference = it
                      CameraSnapshotPersistence.replacePose(it.toPersistedPoseIdentity())
                },
                setCurrentTab = { tabNavigator.current = it },
            ),
            onSignInRequired = { intent ->
                signInController.show(intent)
                showSignIn = true
            },
            onConfirmedUnsave = {
                // 204 landed: remove from the hoisted Saved list without reloading the grid.
                if (origin == PoseDetailOrigin.SAVED) savedState?.viewModel?.removeConfirmed(previewItem.poseId)
            },
            onBack = {
                // Pop-first: request the reverse and perform the exactly-one pop
                // immediately. The root overlay owns the reverse completion + cleanup;
                // this detail scope never awaits it (pop disposes this screen). A rapid
                // duplicate press resolves to NONE and never performs a second pop.
                val owned = backOwned
                backOwned = true
                when (resolveBackAction(owned, MatchedImageTransitionState.requestReverse())) {
                    BackDecision.REVERSE_POP -> navigator.pop()
                    BackDecision.POP -> navigator.pop()
                    BackDecision.NONE -> backOwned = owned
                }
            }
        )
        SignInPrompt(
            controller = signInController,
            visible = showSignIn,
            onDismiss = {
                detailViewModel.clearSignInIntent()
                showSignIn = false
            },
        )
    }
}

/** WI-04: pushed Signed-in Saved list. No MainDock is composed here (stack screen). */
class SavedListVoyagerScreen(private val savedState: SavedListStateHolder) : Screen {
    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val tabNavigator = LocalTabNavigator.current
        val signInController = remember {
            SignInPromptController(platformGoogleSignInLauncher()) { intent ->
                if (intent == SignInIntent.OPEN_SAVED) {
                    // Session restored: re-enter the Signed-in Saved list load.
                    savedState.viewModel.loadInitial()
                }
            }
        }
        var showSignIn by remember { mutableStateOf(false) }
        Box(Modifier.fillMaxSize()) {
            SavedScreen(
                viewModel = savedState.viewModel,
                gridState = savedState.gridState,
                onBack = { navigator.pop() },
                onPoseClick = { preview ->
                    navigator.push(PoseDetailVoyagerScreen(preview, origin = PoseDetailOrigin.SAVED, initialSaved = true, savedState = savedState))
                },
                onBrowseCommunity = { navigator.pop() },
                onSignInRequired = {
                    signInController.show(SignInIntent.OPEN_SAVED)
                    showSignIn = true
                },
            )
        }
        SignInPrompt(
            controller = signInController,
            visible = showSignIn,
            onDismiss = { showSignIn = false },
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
            BoxWithConstraints(
                modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(22.dp))
            ) {
                val pillWidth = maxWidth
                // Animate the indicator offset between the two dock slots:
                // 0f = Poses (left), 1f = Gallery (right).
                val indicatorFraction by animateFloatAsState(
                    targetValue = if (tabNavigator.current == GalleryTab) 1f else 0f,
                    animationSpec = spring(
                        dampingRatio = Spring.DampingRatioNoBouncy,
                        stiffness = Spring.StiffnessMedium
                    ),
                    label = "mainDockIndicator"
                )

                // Sliding tab indicator drawn behind the items.
                NeoBrutalismContainer(
                    modifier = Modifier
                        .padding(2.dp)
                        .fillMaxHeight()
                        .width(pillWidth / 2)
                        .offset {
                            IntOffset(
                                x = ((pillWidth / 2) * indicatorFraction).roundToPx(),
                                y = 0
                            )
                        },
                    shape = RoundedCornerShape(20.dp),
                    backgroundColor = AiPoseColors.AccentBlue,
                    borderWidth = 1.5.dp,
                    shadowOffset = 1.5.dp
                ) {
                }

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
 * E-DOCK: one pill item — the selected background/border come from the
 * sliding indicator drawn behind the items in [MainDock]; the item itself
 * only switches its icon/label color between idle and active.
 */
@Composable
private fun DockItem(
    title: String,
    icon: Painter,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val dockInteractionSource = remember { MutableInteractionSource() }
    Column(
        modifier = modifier.clickable(
            interactionSource = dockInteractionSource,
            indication = null,
            onClick = onClick
        ),
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
            style = AiPoseTypography.MetaLabel,
            letterSpacing = 0.04.em,
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
            style = AiPoseTypography.Display,
            color = AiPoseColors.Foreground
        )
    }
}
