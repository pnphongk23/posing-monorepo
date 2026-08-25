package com.aipose.navigation

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlin.math.max

/**
 * One coherent shared image transition mechanism for Pose + Gallery hands-off.
 *
 * A tapped thumbnail captures a [MatchedImageSource] (its window bounds, its
 * resolved image model, and its corner radius). The destination detail hero reports its
 * window bounds through [MatchedImageDestination]. [MatchedImageOverlay] — placed
 * at the app root above the whole navigator — draws a single flying image in
 * window coordinates. It interpolates the container bounds continuously
 * (offset / width / height / corner radius / clip) while the image content
 * inside is re-rendered with the same [ContentScale] each frame, so the crop /
 * scale / alignment is continuous and never snaps at the endpoint hand-off.
 *
 * Forward: thumbnail -> detail hero. Reverse (Back): hero -> original card.
 * During an active flight the source card and destination hero are hidden so
 * only the flyer renders (no double image / flash / bleed).
 */
data class MatchedImageSource(
    val key: String,
    val bounds: Rect,
    val imageModel: Any? = null,
    val cornerRadius: Dp = 12.dp,
    val contentScale: ContentScale = ContentScale.Crop,
)

enum class SharedTransitionPhase {
    IDLE,
    FORWARD,
    COMPLETED_FORWARD,
    REVERSE
}

/**
 * Typed result of initiating a reverse (Back) request, so callers can tell
 * apart "I started the flight" from "a flight is already reversing" and from
 * "there was never a flight at all" — the three cases a Back handler must
 * treat differently (own+pop, skip, pop immediately).
 */
enum class ReverseDecision {
    /** This caller started the reverse; it performs the single pop now (root cleans up). */
    STARTED,
    /** A reverse flight is already in progress; another handler owns pop/clear. */
    ALREADY_RUNNING,
    /** No source/flight exists; pop immediately once (no await). */
    NO_FLIGHT
}

/**
 * Navigation outcome for one Back press (pure, unit-tested). Subscribes to the
 * POP-FIRST reverse contract: the detail screen atomically requests the reverse
 * and performs its single navigator.pop() immediately; the root overlay owns the
 * reverse flight's completion + cleanup. The detail never awaits reverse.
 */
enum class BackDecision {
    /**
     * A reverse flight was started: perform the exactly-one pop NOW. The root
     * [MatchedImageOverlay] completes the flight and clears state (pop-first).
     */
    REVERSE_POP,
    /** No source/flight exists: perform the exactly-one pop NOW, nothing to animate. */
    POP,
    /** Do nothing — a prior Back already owns this flight, or it's not ours. */
    NONE
}

/**
 * Bounded failure-cleanup window for a forward flight whose destination bounds
 * never arrive. This is the only forward-side timeout and it is strictly a
 * failure cleanup — never a navigation/first-frame UI gate: see
 * [forwardNoTargetCleanupDue] and [MatchedImageOverlay].
 */
internal const val FORWARD_BOUNDS_CLEANUP_MS = 450L

/**
 * Pure: completes the forward no-target flight as bounded failure cleanup once
 * the cleanup window elapses and destination bounds are STILL absent. Normal
 * flights report bounds on the destination's first layout frame and cancel this
 * before it can fire (the overlay effect re-keys on [targetBounds], cancelling
 * the pending delay).
 */
internal fun forwardNoTargetCleanupDue(
    phase: SharedTransitionPhase,
    targetBounds: Rect?,
    cleanupElapsedMs: Long,
): Boolean = phase == SharedTransitionPhase.FORWARD && targetBounds == null && cleanupElapsedMs >= FORWARD_BOUNDS_CLEANUP_MS

/**
 * Pure navigation decision for a single Back press given whether this screen
 * already owns a pending Back ([owned]) and the state's [ReverseDecision].
 * Returns exactly one pop-carrying action per screen; duplicates yield [NONE].
 *
 * Pop-first: [ReverseDecision.STARTED] maps to [BackDecision.REVERSE_POP] (the
 * caller pops immediately; the root overlay finishes + clears the flight), and
 * [ReverseDecision.NO_FLIGHT] maps to [BackDecision.POP] (pop immediately, no
 * flight). The detail never awaits reverse completion.
 */
internal fun resolveBackAction(owned: Boolean, decision: ReverseDecision): BackDecision =
    when {
        owned -> BackDecision.NONE
        decision == ReverseDecision.STARTED -> BackDecision.REVERSE_POP
        decision == ReverseDecision.NO_FLIGHT -> BackDecision.POP
        else -> BackDecision.NONE
    }

/**
 * Pure: a reverse flight that never measured destination bounds completes
 * without animation (bounded deterministic cleanup). The root overlay owns this
 * AFTER the single pop; the detail never awaits it.
 */
internal fun reverseCompletesImmediately(targetBounds: Rect?): Boolean = targetBounds == null

object MatchedImageTransitionState {
    var source by mutableStateOf<MatchedImageSource?>(null)
        private set
    var targetBounds by mutableStateOf<Rect?>(null)
        private set
    var targetCornerRadius by mutableStateOf(16.dp)
        private set
    var transitionPhase by mutableStateOf(SharedTransitionPhase.IDLE)
        internal set
    var reverseRequested by mutableStateOf(false)
        private set
    var progress by mutableStateOf(0f)
        internal set
    var reducedMotion by mutableStateOf(false)

    private var reverseCompleted = CompletableDeferred<Unit>()

    /** True while a flight (forward or reverse) is active for the given source key. */
    fun isFlying(key: String): Boolean {
        val s = source ?: return false
        if (s.key != key) return false
        return transitionPhase == SharedTransitionPhase.FORWARD ||
            transitionPhase == SharedTransitionPhase.REVERSE
    }

    fun capture(
        key: String,
        bounds: Rect,
        imageModel: Any? = null,
        cornerRadius: Dp = 12.dp,
        contentScale: ContentScale = ContentScale.Crop,
    ) {
        source = MatchedImageSource(key, bounds, imageModel, cornerRadius, contentScale)
        targetBounds = null
        reverseRequested = false
        transitionPhase = SharedTransitionPhase.FORWARD
        progress = 0f
        reverseCompleted = CompletableDeferred()
    }

    fun setTarget(bounds: Rect, cornerRadius: Dp = 16.dp) {
        targetBounds = bounds
        targetCornerRadius = cornerRadius
    }

    /**
     * Initiates the reverse (Back) flight idempotently. Pop-first: the caller
     * performs its single navigator.pop() immediately; the root overlay owns the
     * flight's completion + cleanup.
     *
     * Returns a [ReverseDecision]:
     *  - [ReverseDecision.STARTED]: this caller started the reverse and must pop
     *    immediately (exactly once); the root overlay completes + clears the flight.
     *  - [ReverseDecision.ALREADY_RUNNING]: a reverse is already in progress;
     *    another handler already popped, so this caller must NOT pop.
     *  - [ReverseDecision.NO_FLIGHT]: no active source (blank/Icon cards, error
     *    /loading detail, search->detail with no captured transition, gallery
     *    missing bounds, delete/dismiss); pop immediately once (nothing to animate).
     *
     * No-source and duplicate are therefore distinguishable by the caller via
     * the typed result (backed by [resolveBackAction]).
     */
    fun requestReverse(): ReverseDecision {
        val s = source
        return when {
            transitionPhase == SharedTransitionPhase.REVERSE || reverseRequested ->
                ReverseDecision.ALREADY_RUNNING
            s == null || transitionPhase == SharedTransitionPhase.IDLE -> {
                completeReverse()
                ReverseDecision.NO_FLIGHT
            }
            else -> {
                reverseRequested = true
                transitionPhase = SharedTransitionPhase.REVERSE
                ReverseDecision.STARTED
            }
        }
    }

    /**
     * Signals the reverse flight finished (or was aborted) so a caller awaiting
     * completion can pop navigation and reveal the source in the same frame.
     */
    internal fun completeReverse() {
        if (!reverseCompleted.isCompleted) {
            reverseCompleted.complete(Unit)
        }
    }

    /** Suspends until the reverse flight completes (used by Back handling). */
    suspend fun awaitReverseCompletion() {
        reverseCompleted.await()
    }

    fun clear() {
        completeReverse()
        source = null
        targetBounds = null
        reverseRequested = false
        transitionPhase = SharedTransitionPhase.IDLE
        progress = 0f
    }

    // ── Pure geometry helpers (unit-tested) ────────────────────────────────

    fun lerp(source: Rect, target: Rect, progress: Float): Rect {
        fun line(a: Float, b: Float) = a + (b - a) * progress
        return Rect(
            line(source.left, target.left),
            line(source.top, target.top),
            line(source.right, target.right),
            line(source.bottom, target.bottom)
        )
    }

    fun lerpDp(source: Dp, target: Dp, progress: Float): Dp {
        return source + (target - source) * progress
    }

    /**
     * The crop window (in container coordinates) that [ContentScale.Crop]
     * selects for an intrinsic-size image drawn into a container. Interpolating
     * this window across the flight is what makes the in-container content
     * crop/scale/alignment move continuously rather than snap.
     */
    fun contentCropRect(container: Size, intrinsic: Size): Rect {
        if (intrinsic.width <= 0f || intrinsic.height <= 0f) {
            val c = container.minDimension / 2f
            return Rect(c, c, c, c)
        }
        val scale = max(container.width / intrinsic.width, container.height / intrinsic.height)
        val scaledW = intrinsic.width * scale
        val scaledH = intrinsic.height * scale
        val left = (container.width - scaledW) / 2f
        val top = (container.height - scaledH) / 2f
        return Rect(left, top, left + scaledW, top + scaledH)
    }
}

/**
 * Unified destination chrome readiness for Pose + Gallery.
 *
 * The detail hero's border/background/stroke/clip must never render as an empty
 * frame — there is nothing underneath to justify an outline. Chrome is revealed
 * only when one of these holds:
 *
 * Frame ordering (must match [MatchedImageOverlay]):
 *
 *  - `FORWARD` / `REVERSE`: the flyer is actively animating toward/away from
 *    THIS destination, so it is the one visibly covering the hero; the overlay
 *    is still drawing it. Chrome must stay hidden (the hero is hidden too), or
 *    a framed box would render under/behind the flyer.
 *  - `COMPLETED_FORWARD`: the overlay returns (`if (phase == COMPLETED_FORWARD &&
 *    !reverse) return`) and no longer draws the flyer, so chrome is revealed
 *    only once the Coil painter has actually painted the media ([mediaReady]).
 *  - `IDLE` / no flight / a flight covering a different destination: no flyer
 *    covers this hero, so chrome is revealed only on [mediaReady].
 *
 * In every non-mid-flight frame the requirement is identical: the media must be
 * visibly loaded before any border/background/stroke appears. This never shows
 * an empty destination frame. One mechanism for Pose and Gallery.
 *
 * Pure and deterministic so the readiness/border rules are unit-tested without
 * a UI harness.
 */
fun destinationChromeVisible(key: String, mediaReady: Boolean): Boolean {
    val phase = MatchedImageTransitionState.transitionPhase
    // A flyer is actively covering THIS destination only while it is mid-flight
    // (Forward or Reverse) for the matching key; that is the only window where
    // chrome may be withheld even when the media is already loaded.
    val flyerActive = MatchedImageTransitionState.source?.key == key &&
        (phase == SharedTransitionPhase.FORWARD || phase == SharedTransitionPhase.REVERSE)
    // Once no flyer is actively covering (IDLE, COMPLETED_FORWARD, or a flight
    // for another key), chrome is revealed only when the media has loaded.
    return !flyerActive && mediaReady
}

/**
 * Destination wrapper placed inside detail screens around the hero image.
 * Measures the hero image bounds in window coordinates (so the flyer can land
 * on the exact final rect) and hides the hero image while a flight is active so
 * only the flyer renders.
 */
@Composable
fun MatchedImageDestination(
    key: String,
    modifier: Modifier = Modifier,
    imageModel: Any? = null,
    cornerRadius: Dp = 16.dp,
    content: @Composable () -> Unit,
) {
    val source = MatchedImageTransitionState.source?.takeIf { it.key == key }
    val flying = MatchedImageTransitionState.isFlying(key)

    Box(
        modifier = modifier
            .onGloballyPositioned {
                if (source != null) {
                    MatchedImageTransitionState.setTarget(it.boundsInWindow(), cornerRadius)
                }
            }
            .graphicsLayer {
                // Hide the hero only while the flyer is active; show it (immediately
                // or via COMPLETED_FORWARD / after reverse) otherwise.
                alpha = if (source != null && flying) 0f else 1f
            }
    ) {
        content()
    }
}

/**
 * Top-level overlay composable placed at root (App.kt), above the navigator.
 * Draws a single flying image in screen/window coordinates from the source card
 * rect to the destination hero rect (forward), and back (reverse). It also
 * drives the forward/reverse flight lifecycle, reduced-motion fast-path, and
 * reverse-completion signalling.
 */
@Composable
fun MatchedImageOverlay(
    modifier: Modifier = Modifier,
    isReduceMotion: () -> Boolean = { reducedMotionFromPlatform() },
) {
    val source = MatchedImageTransitionState.source ?: return
    val targetBounds = MatchedImageTransitionState.targetBounds
    val phase = MatchedImageTransitionState.transitionPhase
    val reverse = MatchedImageTransitionState.reverseRequested
    val reducedMotion = MatchedImageTransitionState.reducedMotion || remember { isReduceMotion() }

    val animatable = remember(source.key) { Animatable(0f) }

    LaunchedEffect(source.key, targetBounds, reverse, reducedMotion) {
        if (reducedMotion) {
            val targetVal = if (reverse) 0f else 1f
            animatable.snapTo(targetVal)
            MatchedImageTransitionState.progress = targetVal
            if (reverse) {
                // Pop-first: the detail already popped; the root overlay owns the
                // reverse completion AND cleanup for the motion-reduced fast path.
                MatchedImageTransitionState.clear()
            } else {
                MatchedImageTransitionState.transitionPhase = SharedTransitionPhase.COMPLETED_FORWARD
            }
            return@LaunchedEffect
        }

        if (reverse) {
            if (reverseCompletesImmediately(targetBounds)) {
                // No destination was ever measured; pop already happened — bounded
                // deterministic cleanup owned by the root overlay (never the detail).
                MatchedImageTransitionState.clear()
            } else if (phase == SharedTransitionPhase.REVERSE || phase == SharedTransitionPhase.COMPLETED_FORWARD) {
                animatable.animateTo(
                    targetValue = 0f,
                    animationSpec = tween(durationMillis = 260, easing = FastOutSlowInEasing)
                ) {
                    MatchedImageTransitionState.progress = value
                }
                animatable.snapTo(0f)
                MatchedImageTransitionState.progress = 0f
                // Reverse landed on the source below (the list is current/visible
                // under the global flyer). Root owns the cleanup now that the pop
                // already happened.
                MatchedImageTransitionState.clear()
            } else {
                MatchedImageTransitionState.clear()
            }
        } else if (targetBounds != null && phase == SharedTransitionPhase.FORWARD) {
            animatable.animateTo(
                targetValue = 1f,
                animationSpec = tween(durationMillis = 300, easing = FastOutSlowInEasing)
            ) {
                MatchedImageTransitionState.progress = value
            }
            MatchedImageTransitionState.transitionPhase = SharedTransitionPhase.COMPLETED_FORWARD
        } else if (phase == SharedTransitionPhase.FORWARD && targetBounds == null) {
            // Bounded failure cleanup ONLY — never a navigation/first-frame UI gate.
            // Preview-first composition reports hero bounds on the first layout
            // frame, so a normal flight cancels this timeout before it fires: the
            // effect re-keys on targetBounds below, which cancels this delay. It
            // only fires as a fallback when bounds genuinely never arrive (the
            // destination never laid out), deterministically releasing the hidden
            // source card / destination hero instead of stalling forever.
            delay(FORWARD_BOUNDS_CLEANUP_MS)
            if (forwardNoTargetCleanupDue(phase, targetBounds, FORWARD_BOUNDS_CLEANUP_MS)) {
                MatchedImageTransitionState.transitionPhase = SharedTransitionPhase.COMPLETED_FORWARD
            }
        }
    }

    // After forward completes the destination hero is shown; stop drawing.
    if (phase == SharedTransitionPhase.COMPLETED_FORWARD && !reverse) return
    if (phase == SharedTransitionPhase.IDLE) return

    val currentProgress = animatable.value
    val currentRect = MatchedImageTransitionState.lerp(source.bounds, targetBounds ?: source.bounds, currentProgress)
    val currentRadius = MatchedImageTransitionState.lerpDp(
        source.cornerRadius,
        MatchedImageTransitionState.targetCornerRadius,
        currentProgress
    )
    val density = LocalDensity.current

    if (currentRect.width <= 0f || currentRect.height <= 0f) return

    Box(modifier = modifier.fillMaxSize()) {
        val widthDp = with(density) { currentRect.width.toDp() }
        val heightDp = with(density) { currentRect.height.toDp() }
        Box(
            modifier = Modifier
                .graphicsLayer {
                    translationX = currentRect.left
                    translationY = currentRect.top
                }
                .size(widthDp, heightDp)
                .clip(RoundedCornerShape(currentRadius))
                .background(Color.Black.copy(alpha = 0.05f))
        ) {
            // Re-render the flyer from the stable model only — never a decoded
            // bitmap — so the flight stays lightweight and deterministic.
            if (source.imageModel != null) {
                AsyncImage(
                    model = source.imageModel,
                    contentDescription = null,
                    contentScale = source.contentScale,
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
}

/**
 * Reduced-motion preference from the platform accessibility settings. The
 * [MatchedImageOverlay] defaults to reading it once per flight; tests can inject
 * a fixed value. Implemented per platform (iOS) where available.
 */
expect fun reducedMotionFromPlatform(): Boolean