package com.eventer.flutter_barcode_scanner_sdk

import com.eventer.flutter_barcode_scanner_sdk.ScanCandidateSelector.Bounds
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class ScanCandidateSelectorTest {
    // A 400x400 window centred in an 800x800 preview.
    private val window = Bounds(left = 200f, top = 200f, right = 600f, bottom = 600f)
    private val frameCenterX = 400f
    private val frameCenterY = 400f

    private fun select(
        candidates: List<Bounds?>,
        window: Bounds? = this.window,
        crosshair: Boolean = false,
        aimRadius: Float = 0f,
    ): Int? =
        ScanCandidateSelector.selectNearest(
            candidates,
            window,
            frameCenterX,
            frameCenterY,
            requireCenterOnCandidate = crosshair,
            aimRadius = aimRadius,
        )

    // B21 — detector order must not decide the result.

    @Test
    fun nearestToTheWindowCentreWinsOverAnEarlierCandidate() {
        val neighbour = Bounds(210f, 210f, 290f, 250f)
        val aimedAt = Bounds(370f, 380f, 430f, 420f)

        assertEquals(1, select(listOf(neighbour, aimedAt)))
    }

    @Test
    fun nearestWinsRegardlessOfWhichEndOfTheListItIsOn() {
        val aimedAt = Bounds(370f, 380f, 430f, 420f)
        val neighbour = Bounds(210f, 210f, 290f, 250f)

        assertEquals(0, select(listOf(aimedAt, neighbour)))
    }

    @Test
    fun theNearestOfSeveralCandidatesWins() {
        val candidates = listOf(
            Bounds(205f, 205f, 265f, 235f),
            Bounds(520f, 520f, 580f, 550f),
            Bounds(390f, 405f, 450f, 435f),
            Bounds(240f, 500f, 300f, 530f),
        )

        assertEquals(2, select(candidates))
    }

    @Test
    fun equallyDistantCandidatesResolveToTheEarliestSoSelectionIsStable() {
        val left = Bounds(300f, 390f, 340f, 410f)
        val right = Bounds(460f, 390f, 500f, 410f)

        assertEquals(0, select(listOf(left, right)))
        assertEquals(0, select(listOf(right, left)))
    }

    // B22 — overlapping the window is enough; the centre point need not be inside it.

    @Test
    fun aCodeOverlappingTheWindowQualifiesEvenWhenItsCentreIsOutside() {
        // A long 1D code crossing the window's left edge: the centre sits well outside.
        val overlapping = Bounds(left = 20f, top = 390f, right = 260f, bottom = 420f)

        assertEquals(0, select(listOf(overlapping)))
    }

    @Test
    fun aCodeEntirelyOutsideTheWindowNeverQualifies() {
        val outside = Bounds(left = 20f, top = 20f, right = 180f, bottom = 60f)

        assertNull(select(listOf(outside)))
    }

    @Test
    fun touchingTheWindowEdgeIsNotOverlapping() {
        val touching = Bounds(left = 100f, top = 390f, right = 200f, bottom = 410f)

        assertNull(select(listOf(touching)))
    }

    @Test
    fun anOverlappingCandidateLosesToOneCentredNearerTheWindow() {
        val overlapping = Bounds(20f, 390f, 260f, 420f)
        val centred = Bounds(380f, 390f, 440f, 420f)

        assertEquals(1, select(listOf(overlapping, centred)))
    }

    // Unpositioned candidates.

    @Test
    fun aCandidateWithoutBoundsNeverQualifiesWhileTheWindowApplies() {
        assertNull(select(listOf(null)))
    }

    @Test
    fun zeroAreaBoundsAreTreatedAsUnpositioned() {
        val degenerate = Bounds(400f, 400f, 400f, 400f)

        assertNull(select(listOf(degenerate)))
    }

    @Test
    fun aPositionedCandidateBeatsAnUnpositionedOneWithNoWindow() {
        val positioned = Bounds(700f, 700f, 760f, 730f)

        assertEquals(1, select(listOf(null, positioned), window = null))
    }

    @Test
    fun anUnpositionedCandidateIsStillReportedWhenNothingElseQualifies() {
        assertEquals(0, select(listOf(null), window = null))
    }

    // No scan window — ranking falls back to the centre of the preview.

    @Test
    fun withoutAWindowTheCandidateNearestThePreviewCentreWins() {
        val edge = Bounds(20f, 20f, 80f, 50f)
        val middle = Bounds(370f, 380f, 430f, 420f)

        assertEquals(1, select(listOf(edge, middle), window = null))
    }

    @Test
    fun withoutAWindowNothingIsRejectedForBeingFarAway() {
        val faraway = Bounds(760f, 760f, 800f, 790f)

        assertEquals(0, select(listOf(faraway), window = null))
    }

    // Degenerate input.

    @Test
    fun noCandidatesSelectsNothing() {
        assertNull(select(emptyList()))
        assertNull(select(emptyList(), window = null))
    }

    @Test
    fun everyCandidateOutsideTheWindowSelectsNothing() {
        val candidates = listOf(
            Bounds(20f, 20f, 100f, 60f),
            Bounds(650f, 650f, 780f, 700f),
            null,
        )

        assertNull(select(candidates))
    }

    // Crosshair aiming — the barcode must contain the aim point, not merely overlap the window.

    /// The dense-sheet case. A neighbour can sit entirely inside the window and still lose,
    /// because the aim point is not on it.
    @Test
    fun crosshairRejectsANeighbourInsideTheWindow() {
        val neighbour = Bounds(220f, 220f, 300f, 260f)

        assertEquals(0, select(listOf(neighbour)))
        assertNull(select(listOf(neighbour), crosshair = true))
    }

    @Test
    fun crosshairAcceptsTheCodeUnderTheAimPoint() {
        val underAim = Bounds(360f, 380f, 440f, 420f)

        assertEquals(0, select(listOf(underAim), crosshair = true))
    }

    @Test
    fun crosshairPicksTheOneUnderTheAimPointNotTheNearest() {
        val nearMiss = Bounds(300f, 380f, 340f, 420f)
        val underAim = Bounds(360f, 380f, 440f, 420f)

        assertEquals(1, select(listOf(nearMiss, underAim), crosshair = true))
    }

    @Test
    fun crosshairFallsBackToThePreviewCentreWithoutAWindow() {
        val elsewhere = Bounds(20f, 20f, 100f, 60f)
        val underCentre = Bounds(360f, 360f, 440f, 440f)

        assertEquals(1, select(listOf(elsewhere, underCentre), window = null, crosshair = true))
    }

    @Test
    fun crosshairNeverAcceptsAnUnpositionedCandidate() {
        assertEquals(0, select(listOf(null), window = null))
        assertNull(select(listOf(null), window = null, crosshair = true))
    }

    /**
     * A bare point was too brittle: detectors report partial and wobbling bounds, so a code
     * sitting visibly under the crosshair could be unscannable however carefully the user aimed.
     */
    @Test
    fun crosshairToleratesBoundsThatMissTheExactCentre() {
        // Reported bounds cover only part of the code and stop 10px short of the anchor.
        val partial = Bounds(300f, 380f, 390f, 420f)

        assertNull(select(listOf(partial), crosshair = true))
        assertEquals(0, select(listOf(partial), crosshair = true, aimRadius = 24f))
    }

    @Test
    fun theAimRegionIsStillTooSmallForANeighbour() {
        // Stacked codes on a sheet sit far enough apart that the region cannot reach the next one.
        val neighbour = Bounds(220f, 220f, 300f, 260f)

        assertNull(select(listOf(neighbour), crosshair = true, aimRadius = 24f))
    }

    @Test
    fun theAimRadiusIsClampedToASensibleRange() {
        assertEquals(8f, ScanCandidateSelector.aimRadius(10f))
        assertEquals(48f, ScanCandidateSelector.aimRadius(10_000f))
        assertEquals(11.58f, ScanCandidateSelector.aimRadius(193f), 0.01f)
    }
}