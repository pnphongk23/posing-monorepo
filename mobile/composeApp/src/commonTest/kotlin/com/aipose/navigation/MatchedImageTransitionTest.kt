package com.aipose.navigation

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MatchedImageTransitionTest {

    @Test
    fun interpolationUsesStableSourceKeyAndBounds() {
        val source = Rect(10f, 20f, 110f, 120f)
        val target = Rect(40f, 60f, 240f, 360f)
        MatchedImageTransitionState.capture(
            "pose:42",
            source,
            imageModel = "http://example.com/img.png",
            cornerRadius = 12.dp
        )
        assertEquals("pose:42", MatchedImageTransitionState.source?.key)
        assertEquals("http://example.com/img.png", MatchedImageTransitionState.source?.imageModel)
        assertEquals(SharedTransitionPhase.FORWARD, MatchedImageTransitionState.transitionPhase)

        val midpoint = MatchedImageTransitionState.lerp(source, target, 0.5f)
        assertEquals(Rect(25f, 40f, 175f, 240f), midpoint)

        val midRadius = MatchedImageTransitionState.lerpDp(12.dp, 16.dp, 0.5f)
        assertEquals(14.dp, midRadius)

        MatchedImageTransitionState.setTarget(target, 16.dp)
        assertEquals(target, MatchedImageTransitionState.targetBounds)

        MatchedImageTransitionState.clear()
        assertNull(MatchedImageTransitionState.source)
        assertNull(MatchedImageTransitionState.targetBounds)
        assertEquals(SharedTransitionPhase.IDLE, MatchedImageTransitionState.transitionPhase)
    }

    @Test
    fun contentCropRectIsCenteredCoverCrop() {
        val container = Size(100f, 200f)
        val intrinsic = Size(100f, 100f)
        val crop = MatchedImageTransitionState.contentCropRect(container, intrinsic)
        // scale = max(1, 2) = 2 -> image drawn 200x200, centered horizontally, top-aligned.
        assertEquals(Rect(-50f, 0f, 150f, 200f), crop)
    }

    @Test
    fun contentCropTransformInterpolatesContinuously() {
        val startCrop = MatchedImageTransitionState.contentCropRect(Size(50f, 66f), Size(200f, 200f))
        val endCrop = MatchedImageTransitionState.contentCropRect(Size(300f, 400f), Size(200f, 200f))
        // As the container morphs, the visible crop window must move monotonically.
        val half = MatchedImageTransitionState.lerp(startCrop, endCrop, 0.5f)
        assertTrue(half.width > startCrop.width)
        assertTrue(half.width < endCrop.width)
        // Container grows: the cover-crop window expands and its left/top edges
        // move outward (toward more-negative offsets) monotonically.
        assertTrue(startCrop.left >= half.left)
        assertTrue(half.left >= endCrop.left)
        assertTrue(startCrop.top >= half.top)
        assertTrue(half.top >= endCrop.top)
    }

    @Test
    fun forwardThenReverseStateIsCoordinated() {
        val source = Rect(10f, 20f, 110f, 120f)
        val target = Rect(40f, 60f, 240f, 360f)
        MatchedImageTransitionState.capture("photo:7", source)
        assertTrue(MatchedImageTransitionState.isFlying("photo:7"))
        assertEquals(SharedTransitionPhase.FORWARD, MatchedImageTransitionState.transitionPhase)

        MatchedImageTransitionState.setTarget(target, 16.dp)
        assertEquals(target, MatchedImageTransitionState.targetBounds)

        MatchedImageTransitionState.requestReverse()
        assertTrue(MatchedImageTransitionState.reverseRequested)
        assertEquals(SharedTransitionPhase.REVERSE, MatchedImageTransitionState.transitionPhase)
        // Still a single flight back to source.
        assertTrue(MatchedImageTransitionState.isFlying("photo:7"))
        assertFalse(MatchedImageTransitionState.isFlying("photo:999"))
        MatchedImageTransitionState.clear()
        assertFalse(MatchedImageTransitionState.isFlying("photo:7"))
    }

    @Test
    fun forwardSetTargetResetsReverseFlag() {
        MatchedImageTransitionState.capture("pose:1", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        assertFalse(MatchedImageTransitionState.reverseRequested)
        assertEquals(SharedTransitionPhase.FORWARD, MatchedImageTransitionState.transitionPhase)
        MatchedImageTransitionState.clear()
    }

    @Test
    fun reverseAwaitReleasesOnClear() = runBlocking {
        MatchedImageTransitionState.capture("pose:99", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        MatchedImageTransitionState.requestReverse()

        // A waiter suspends on the reverse completion signal.
        val waiter = async { MatchedImageTransitionState.awaitReverseCompletion() }
        // Cancel/cleanup (navigation interruption, lifecycle, or completed flight)
        // must release the waiter rather than leak the coroutine.
        MatchedImageTransitionState.clear()
        waiter.await()
        assertNull(MatchedImageTransitionState.source)
    }

    @Test
    fun distinctPoseAndPhotoKeysStayStable() {
        MatchedImageTransitionState.capture("pose:11", Rect(0f, 0f, 40f, 40f), cornerRadius = 12.dp)
        assertEquals("pose:11", MatchedImageTransitionState.source?.key)
        assertFalse(MatchedImageTransitionState.isFlying("photo:11"))

        MatchedImageTransitionState.capture("photo:11", Rect(0f, 0f, 40f, 40f), cornerRadius = 6.dp)
        assertEquals("photo:11", MatchedImageTransitionState.source?.key)
        assertEquals(6.dp, MatchedImageTransitionState.source?.cornerRadius)
        assertFalse(MatchedImageTransitionState.isFlying("pose:11"))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun noSourceReverseReturnsNoFlightAndDoesNotHang() = runBlocking {
        // Blank/Icon card, error/loading detail, search->detail with no captured
        // source, delete/dismiss path: source is null so reverse must be a no-op
        // that lets Back pop immediately (never awaits an unresolved signal).
        MatchedImageTransitionState.clear()
        assertEquals(ReverseDecision.NO_FLIGHT, MatchedImageTransitionState.requestReverse())
        // Even if some earlier awaiter existed, it is now released.
        val waiter = async { MatchedImageTransitionState.awaitReverseCompletion() }
        waiter.await()
        assertNull(MatchedImageTransitionState.source)
    }

    @Test
    fun reverseIsIdempotentSinglePopGuard() {
        MatchedImageTransitionState.capture("pose:5", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        // First chevron press starts the reverse flight.
        assertEquals(ReverseDecision.STARTED, MatchedImageTransitionState.requestReverse())
        assertEquals(SharedTransitionPhase.REVERSE, MatchedImageTransitionState.transitionPhase)
        // A rapid second press during the same flight is distinguishable as
        // ALREADY_RUNNING, so the navigation layer will not pop twice.
        assertEquals(ReverseDecision.ALREADY_RUNNING, MatchedImageTransitionState.requestReverse())
        MatchedImageTransitionState.clear()
        // A fresh flight (new capture) yields STARTED again for the next Back.
        MatchedImageTransitionState.capture("pose:5", Rect(0f, 0f, 50f, 50f))
        assertEquals(ReverseDecision.STARTED, MatchedImageTransitionState.requestReverse())
        MatchedImageTransitionState.clear()
    }

    @Test
    fun forwardNoTargetCleanupFiresOnlyAfterBoundedWindow() {
        // Normal preview-first flights report bounds on first layout, so the
        // forward no-target cleanup must NOT fire early; it is a bounded failure
        // cleanup only (never a navigation/first-frame gate).
        assertFalse(forwardNoTargetCleanupDue(SharedTransitionPhase.FORWARD, null, FORWARD_BOUNDS_CLEANUP_MS - 1))
        // Once the bounded window elapses with bounds still absent -> due.
        assertTrue(forwardNoTargetCleanupDue(SharedTransitionPhase.FORWARD, null, FORWARD_BOUNDS_CLEANUP_MS))
        assertTrue(forwardNoTargetCleanupDue(SharedTransitionPhase.FORWARD, null, 10_000L))
        // The moment bounds arrive (or phase advances), it is cancelled / never fires.
        assertFalse(forwardNoTargetCleanupDue(SharedTransitionPhase.FORWARD, Rect(0f, 0f, 100f, 100f), 10_000L))
        assertFalse(forwardNoTargetCleanupDue(SharedTransitionPhase.COMPLETED_FORWARD, null, 10_000L))
        assertFalse(forwardNoTargetCleanupDue(SharedTransitionPhase.IDLE, null, 10_000L))
    }

    @Test
    fun forwardWithoutTargetIsDeterministicAndNeedsNoGate() {
        // Preview-first navigation reports hero bounds on first composition. Until
        // they arrive the forward flight must stay FORWARD (no hidden 450ms timer
        // auto-completing it at the state layer), and become ready the instant a
        // target is set. Reverse-side no-target is the only bounded cleanup.
        MatchedImageTransitionState.capture("pose:77", Rect(0f, 0f, 50f, 50f), imageModel = "https://cdn/t.png")
        assertNull(MatchedImageTransitionState.targetBounds)
        assertEquals(SharedTransitionPhase.FORWARD, MatchedImageTransitionState.transitionPhase)
        assertTrue(MatchedImageTransitionState.isFlying("pose:77"))

        // Bounds arrive deterministically from the destination hero measurement.
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f), 16.dp)
        assertEquals(Rect(0f, 0f, 200f, 200f), MatchedImageTransitionState.targetBounds)
        assertEquals(SharedTransitionPhase.FORWARD, MatchedImageTransitionState.transitionPhase)
        assertTrue(MatchedImageTransitionState.isFlying("pose:77"))

        MatchedImageTransitionState.clear()
        assertEquals(SharedTransitionPhase.IDLE, MatchedImageTransitionState.transitionPhase)
    }

    @Test
    fun reverseWithMissingTargetCompletesAndCleansUp() = runBlocking {
        // Destination never reported bounds (image failure / no hero measured).
        MatchedImageTransitionState.capture("pose:6", Rect(0f, 0f, 50f, 50f))
        assertNull(MatchedImageTransitionState.targetBounds)
        // A real source exists so reverse starts; the overlay's bounded no-target
        // fallback completes it, and clear()/cancel must release too.
        assertEquals(ReverseDecision.STARTED, MatchedImageTransitionState.requestReverse())
        val waiter = async { MatchedImageTransitionState.awaitReverseCompletion() }
        MatchedImageTransitionState.clear()
        waiter.await()
        assertNull(MatchedImageTransitionState.source)
        // After clear, reverse is NO_FLIGHT (won't run another flight/pop).
        assertEquals(ReverseDecision.NO_FLIGHT, MatchedImageTransitionState.requestReverse())
     }

    @Test
    fun resolveBackDuplicateDoesNotPop() {
        // A duplicate press while this screen already owns a Back must never pop.
        assertEquals(BackDecision.NONE, resolveBackAction(owned = true, ReverseDecision.STARTED))
        assertEquals(BackDecision.NONE, resolveBackAction(owned = true, ReverseDecision.NO_FLIGHT))
        assertEquals(BackDecision.NONE, resolveBackAction(owned = true, ReverseDecision.ALREADY_RUNNING))
    }

    @Test
    fun resolveBackOwnerPopsFirstExactlyOnce() {
        // Pop-first: first owner press on a real flight resolves to REVERSE_POP —
        // the caller pops immediately (exactly once) and the root overlay finishes
        // + clears the flight. It never awaits reverse before popping.
        assertEquals(BackDecision.REVERSE_POP, resolveBackAction(owned = false, ReverseDecision.STARTED))
    }

    // ── Pop-first reverse / root-owned cleanup contracts ─────────────────────

    @Test
    fun popFirstReverseThenRootCleanupClearsAndReleasesWaiter() = runBlocking {
        // A Back that starts a reverse resolves to REVERSE_POP (pop now); the root
        // overlay then owns completion: clear() -> IDLE and any awaited completion
        // is released (no leaked coroutine / no double-pop / no hang).
        MatchedImageTransitionState.capture("pose:200", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        assertEquals(
            BackDecision.REVERSE_POP,
            resolveBackAction(owned = false, MatchedImageTransitionState.requestReverse())
        )
        assertEquals(SharedTransitionPhase.REVERSE, MatchedImageTransitionState.transitionPhase)
        // Root-owned reverse completion + cleanup (the overlay's job after pop).
        val rootCleanup = async { MatchedImageTransitionState.awaitReverseCompletion() }
        MatchedImageTransitionState.clear()
        rootCleanup.await()
        assertEquals(SharedTransitionPhase.IDLE, MatchedImageTransitionState.transitionPhase)
        assertNull(MatchedImageTransitionState.source)
        assertFalse(MatchedImageTransitionState.reverseRequested)
    }

    @Test
    fun reverseMissingTargetCompletesImmediately() = runBlocking {
        // A reverse flight with no measured destination bounds is a bounded,
        // immediate cleanup (never a hang). resolveBack still starts the reverse
        // (REVERSE_POP) because a real source exists; the overlay's immediate path
        // (reverseCompletesImmediately) then clears after the pop.
        assertTrue(reverseCompletesImmediately(null))
        assertFalse(reverseCompletesImmediately(Rect(0f, 0f, 10f, 10f)))
        MatchedImageTransitionState.capture("pose:201", Rect(0f, 0f, 50f, 50f))
        assertNull(MatchedImageTransitionState.targetBounds)
        assertEquals(ReverseDecision.STARTED, MatchedImageTransitionState.requestReverse())
        assertEquals(BackDecision.REVERSE_POP, resolveBackAction(owned = false, ReverseDecision.STARTED))
        val waiter = async { MatchedImageTransitionState.awaitReverseCompletion() }
        MatchedImageTransitionState.clear() // root overlay immediate-cleanup
        waiter.await()
        assertNull(MatchedImageTransitionState.source)
        // After cleanup, a fresh reverse is NO_FLIGHT (no second flight/pop).
        assertEquals(ReverseDecision.NO_FLIGHT, MatchedImageTransitionState.requestReverse())
        MatchedImageTransitionState.clear()
    }

    @Test
    fun rapidBackYieldsExactlyOnePop() {
        MatchedImageTransitionState.capture("photo:300", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        // First press: starts reverse -> pop now (exactly one pop-carrying action).
        assertEquals(BackDecision.REVERSE_POP, resolveBackAction(owned = false, MatchedImageTransitionState.requestReverse()))
        // Rapid duplicate press: ALREADY_RUNNING -> NONE (never a second pop).
        assertEquals(BackDecision.NONE, resolveBackAction(owned = true, MatchedImageTransitionState.requestReverse()))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun reducedMotionReverseStillStartsThenRootCleansUp() = runBlocking {
        // Reduced-motion: the reverse still starts (REVERSE_POP) and the overlay's
        // motion-reduced fast path completes + clears (root-owned) after the single pop.
        MatchedImageTransitionState.reducedMotion = true
        try {
            MatchedImageTransitionState.capture("pose:301", Rect(0f, 0f, 50f, 50f))
            MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
            assertEquals(ReverseDecision.STARTED, MatchedImageTransitionState.requestReverse())
            assertEquals(BackDecision.REVERSE_POP, resolveBackAction(owned = false, ReverseDecision.STARTED))
            val waiter = async { MatchedImageTransitionState.awaitReverseCompletion() }
            MatchedImageTransitionState.clear() // root reduced-motion snap + cleanup
            waiter.await()
            assertNull(MatchedImageTransitionState.source)
        } finally {
            MatchedImageTransitionState.reducedMotion = false
        }
    }

    @Test
    fun offscreenNotRemeasuredSourceKeepsCapturedGeometry() {
        // The source card captures real window bounds at tap time; the flyer uses
        // that captured geometry even if the card is not re-measured after Back
        // (list re-entry). Geometry must remain deterministic/stable.
        val captured = Rect(12f, 34f, 212f, 334f)
        MatchedImageTransitionState.capture("pose:302", captured, imageModel = "m", cornerRadius = 12.dp)
        MatchedImageTransitionState.setTarget(Rect(40f, 60f, 240f, 360f))
        // Global state persists across list re-entry (pop-first): the same captured bounds.
        assertEquals(captured, MatchedImageTransitionState.source?.bounds)
        // Missing source (blank/Image card never captures) -> NO_FLIGHT -> single POP.
        MatchedImageTransitionState.clear()
        assertEquals(ReverseDecision.NO_FLIGHT, MatchedImageTransitionState.requestReverse())
        assertEquals(BackDecision.POP, resolveBackAction(owned = false, ReverseDecision.NO_FLIGHT))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun cancelCleanupLeavesIdleAndNextReverseIsNoFlight() = runBlocking {
        // Cancelled/interrupted reverse (tab switch, teardown): clear() leaves IDLE
        // and a subsequent request never re-runs a stale flight (no hang/leak).
        MatchedImageTransitionState.capture("pose:303", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        val first = async { MatchedImageTransitionState.awaitReverseCompletion() }
        MatchedImageTransitionState.clear() // cancellation
        first.await()
        assertEquals(SharedTransitionPhase.IDLE, MatchedImageTransitionState.transitionPhase)
        assertEquals(ReverseDecision.NO_FLIGHT, MatchedImageTransitionState.requestReverse())
        MatchedImageTransitionState.clear()
    }

    @Test
    fun resolveBackNoSourcePopsOnce() {
        // No-source/no-flight pops immediately once; a duplicate is a no-op.
        assertEquals(BackDecision.POP, resolveBackAction(owned = false, ReverseDecision.NO_FLIGHT))
        assertEquals(BackDecision.NONE, resolveBackAction(owned = true, ReverseDecision.NO_FLIGHT))
    }

    @Test
    fun resolveBackAlreadyRunningIsNotOwned() {
        // A reverse owned elsewhere must not be popped by this handler.
        assertEquals(BackDecision.NONE, resolveBackAction(owned = false, ReverseDecision.ALREADY_RUNNING))
    }

    // ── Gallery destination chrome readiness / border visibility ────────────

    @Test
    fun galleryChromeIdleGatesOnImageReady() {
        // No flight: the detail chrome (border/background/stroke) must never
        // appear as an empty frame — reveal only once Coil painted the media.
        MatchedImageTransitionState.clear()
        assertEquals(SharedTransitionPhase.IDLE, MatchedImageTransitionState.transitionPhase)
        assertFalse(destinationChromeVisible("photo:900", mediaReady = false))
        assertTrue(destinationChromeVisible("photo:900", mediaReady = true))
    }

    @Test
    fun galleryChromeHiddenMidFlightEvenIfImageReady() {
        // Forward flight underway: the flyer has not covered the destination yet,
        // so chrome stays hidden even though the media is already loaded.
        MatchedImageTransitionState.capture("photo:901", Rect(0f, 0f, 50f, 50f), imageModel = "m")
        assertEquals(SharedTransitionPhase.FORWARD, MatchedImageTransitionState.transitionPhase)
        assertFalse(destinationChromeVisible("photo:901", mediaReady = true))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        // Still forward (flyer mid-air): hidden.
        assertFalse(destinationChromeVisible("photo:901", mediaReady = true))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun galleryChromeCompletedForwardRequiresMedia() {
        // COMPLETED_FORWARD: the overlay returns and no longer draws the flyer
        // (it stops covering the hero), so the chrome must not reveal an empty
        // framed box — it needs the media to actually be painted.
        MatchedImageTransitionState.capture("photo:902", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        MatchedImageTransitionState.transitionPhase = SharedTransitionPhase.COMPLETED_FORWARD
        assertFalse(destinationChromeVisible("photo:902", mediaReady = false))
        assertTrue(destinationChromeVisible("photo:902", mediaReady = true))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun galleryChromeHiddenDuringReverse() {
        // Back flight in progress: no destination chrome, even with media ready.
        MatchedImageTransitionState.capture("photo:903", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.setTarget(Rect(0f, 0f, 200f, 200f))
        assertEquals(ReverseDecision.STARTED, MatchedImageTransitionState.requestReverse())
        assertFalse(destinationChromeVisible("photo:903", mediaReady = true))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun galleryChromeUnmatchedFlightIsNeverCovered() {
        // A completed flight for one photo must not reveal another photo's chrome
        // as an empty frame; it falls back to media readiness.
        MatchedImageTransitionState.capture("photo:904", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.transitionPhase = SharedTransitionPhase.COMPLETED_FORWARD
        assertFalse(destinationChromeVisible("photo:999", mediaReady = false))
        assertTrue(destinationChromeVisible("photo:999", mediaReady = true))
        MatchedImageTransitionState.clear()
    }

    @Test
    fun galleryChromeCleanupReturnsToReadinessGated() {
        // COMPLETED_FORWARD with no media painted: chrome must stay hidden so no
        // empty framed destination shows after the overlay stops drawing.
        MatchedImageTransitionState.capture("photo:905", Rect(0f, 0f, 50f, 50f))
        MatchedImageTransitionState.transitionPhase = SharedTransitionPhase.COMPLETED_FORWARD
        assertFalse(destinationChromeVisible("photo:905", mediaReady = false))
        assertTrue(destinationChromeVisible("photo:905", mediaReady = true))
        // After delete/dismiss/navigation cleanup the flight clears (IDLE); the
        // chrome drops back to media-readiness gating rather than staying open.
        MatchedImageTransitionState.clear()
        assertEquals(SharedTransitionPhase.IDLE, MatchedImageTransitionState.transitionPhase)
        assertFalse(destinationChromeVisible("photo:905", mediaReady = false))
        assertTrue(destinationChromeVisible("photo:905", mediaReady = true))
        // A fresh flight (flyer active) re-hides the chrome even if media is ready.
        MatchedImageTransitionState.capture("photo:905", Rect(0f, 0f, 50f, 50f))
        assertFalse(destinationChromeVisible("photo:905", mediaReady = true))
        MatchedImageTransitionState.clear()
    }
}
