package com.eventer.flutter_barcode_scanner_sdk

/**
 * Holds a scan back until the same value has been selected several times in a row.
 *
 * A camera decodes many times a second, so the first code to satisfy the scan window wins — even
 * when the phone is still sweeping towards the one the user meant. A code caught in passing does
 * not stay the best candidate, so requiring a short run of agreement discards it while costing
 * roughly one frame per required observation.
 *
 * Progress is discarded when nothing has been observed for [staleAfterMillis], and **only** then.
 * A frame that decodes nothing does not break the run: iOS reports an unpredictable subset of the
 * barcodes it can see, so demanding strictly back-to-back observations there means a run almost
 * never completes and the scan takes seconds. The staleness window is what separates "a gap of a
 * few frames" from "the user looked away".
 *
 * Not thread-safe: call it from the single thread that handles detector results.
 */
internal class ScanConfirmationTracker(
    requiredObservations: Int,
    private val staleAfterMillis: Long = DEFAULT_STALE_AFTER_MILLIS,
) {
    /** How many consecutive observations of one value are needed, at least 1. */
    private val required: Int = requiredObservations.coerceAtLeast(1)

    private var currentValue: String? = null
    private var streak: Int = 0
    private var lastObservedAt: Long = 0

    /**
     * Records an observation and reports whether it completes a run.
     *
     * @param value the selected candidate's value.
     * @param nowMillis a monotonic clock reading, normally `SystemClock.elapsedRealtime()`.
     * @param ambiguous whether more than one barcode was inside the scan window. When it was, the
     *   run has to be twice as long: several codes in the frame is exactly when a hasty result is
     *   the wrong one, and the extra frames give the user time to centre the code they meant.
     * @return true when [value] has now been observed [required] times in a row, at which point
     *   the run is consumed — the next observation starts a new one, so a barcode held in frame
     *   does not re-report on every subsequent frame.
     */
    fun observe(value: String, nowMillis: Long, ambiguous: Boolean = false): Boolean {
        if (currentValue != value || nowMillis - lastObservedAt > staleAfterMillis) {
            currentValue = value
            streak = 0
        }
        lastObservedAt = nowMillis
        streak += 1
        val needed = if (ambiguous) required * AMBIGUOUS_MULTIPLIER else required
        if (streak >= needed) {
            reset()
            return true
        }
        return false
    }

    /** Drops any run in progress. Call when detection pauses, stops, or is reconfigured. */
    fun reset() {
        currentValue = null
        streak = 0
        lastObservedAt = 0
    }

    companion object {
        /** How much longer the run must be when several barcodes share the window. */
        const val AMBIGUOUS_MULTIPLIER = 2

        /**
         * How long a run survives without a new observation.
         *
         * Long enough to bridge the gap between analyzer frames on a slow device, short enough
         * that looking away and back never counts as continuous.
         */
        const val DEFAULT_STALE_AFTER_MILLIS = 500L
    }
}
