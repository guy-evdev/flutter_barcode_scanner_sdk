package com.eventer.flutter_barcode_scanner_sdk

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class ScanConfirmationTrackerTest {
    @Test
    fun oneObservationReportsImmediately() {
        val tracker = ScanConfirmationTracker(1)

        assertTrue(tracker.observe("A", 0))
    }

    @Test
    fun holdsBackUntilTheRunCompletes() {
        val tracker = ScanConfirmationTracker(3)

        assertFalse(tracker.observe("A", 0))
        assertFalse(tracker.observe("A", 30))
        assertTrue(tracker.observe("A", 60))
    }

    @Test
    fun consumesTheRunSoAHeldCodeDoesNotRepeat() {
        val tracker = ScanConfirmationTracker(2)

        assertFalse(tracker.observe("A", 0))
        assertTrue(tracker.observe("A", 30))
        assertFalse(tracker.observe("A", 60))
        assertTrue(tracker.observe("A", 90))
    }

    /** The point of the feature: a code caught while sweeping towards another never confirms. */
    @Test
    fun discardsAValueSweptPast() {
        val tracker = ScanConfirmationTracker(2)

        assertFalse(tracker.observe("PASSING", 0))
        assertFalse(tracker.observe("TARGET", 30))
        assertTrue(tracker.observe("TARGET", 60))
    }

    @Test
    fun discardsAStaleRun() {
        val tracker = ScanConfirmationTracker(2, staleAfterMillis = 500)

        assertFalse(tracker.observe("A", 0))
        assertFalse(tracker.observe("A", 10_000))
        assertTrue(tracker.observe("A", 10_030))
    }

    /**
     * iOS reports an unpredictable subset of the barcodes it can see, so frames that decode
     * nothing are routine. Breaking the run on each one meant a scan took seconds.
     */
    @Test
    fun aShortGapDoesNotBreakTheRun() {
        val tracker = ScanConfirmationTracker(2)

        assertFalse(tracker.observe("A", 0))
        // Several frames decode nothing, then the value comes back inside the staleness window.
        assertTrue(tracker.observe("A", 200))
    }

    @Test
    fun aLongGapStillBreaksTheRun() {
        val tracker = ScanConfirmationTracker(2, staleAfterMillis = 500)

        assertFalse(tracker.observe("A", 0))
        assertFalse(tracker.observe("A", 900))
        assertTrue(tracker.observe("A", 930))
    }

    /** Several codes sharing the window is when a hasty result is most likely to be wrong. */
    @Test
    fun anAmbiguousFrameNeedsALongerRun() {
        val tracker = ScanConfirmationTracker(2)

        assertFalse(tracker.observe("A", 0, ambiguous = true))
        assertFalse(tracker.observe("A", 30, ambiguous = true))
        assertFalse(tracker.observe("A", 60, ambiguous = true))
        assertTrue(tracker.observe("A", 90, ambiguous = true))
    }

    @Test
    fun anUnambiguousFrameKeepsTheShortRun() {
        val tracker = ScanConfirmationTracker(2)

        assertFalse(tracker.observe("A", 0))
        assertTrue(tracker.observe("A", 30))
    }

    @Test
    fun zeroOrNegativeRequirementBehavesAsOne() {
        assertTrue(ScanConfirmationTracker(0).observe("A", 0))
        assertTrue(ScanConfirmationTracker(-5).observe("A", 0))
    }
}
