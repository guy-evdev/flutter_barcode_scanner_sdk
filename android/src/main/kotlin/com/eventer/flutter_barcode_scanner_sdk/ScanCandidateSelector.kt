package com.eventer.flutter_barcode_scanner_sdk

import android.graphics.RectF
import kotlin.math.sqrt

/**
 * Chooses which of a frame's decoded barcodes the scanner reports.
 *
 * A detector returns its results in an order that has no relation to what the user is aiming at.
 * Accepting the first result that passed the scan-window test therefore let a neighbouring code
 * on a dense sheet win silently, and the app validated the wrong code. Candidates are ranked by
 * distance from the scan-window centre instead, and the nearest wins.
 *
 * A candidate qualifies when its bounds *overlap* the scan window. Requiring the bounds' centre
 * point to be inside the window rejected codes that visibly sat within the overlay, which is why
 * repositioning the camera eventually worked — the user was hunting for the centre to land.
 *
 * Geometry only: values, formats and detector state are the caller's to filter first. Deliberately
 * free of Android framework types so it is covered by JVM unit tests.
 */
internal object ScanCandidateSelector {
    /** An axis-aligned rectangle in view coordinates. */
    data class Bounds(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    ) {
        val centerX: Float get() = (left + right) / 2f
        val centerY: Float get() = (top + bottom) / 2f

        /** Whether this rectangle has no area, and so can neither overlap nor be aimed at. */
        val isEmpty: Boolean get() = left >= right || top >= bottom

        /** Whether the two rectangles share any area. Touching edges do not overlap. */
        fun overlaps(other: Bounds): Boolean =
            left < other.right && other.left < right && top < other.bottom && other.top < bottom
    }

    /**
     * The index of the candidate to report, or null when none qualifies.
     *
     * @param candidates mapped bounds per decoded candidate, in view coordinates, in detector
     *   order. A null entry is a candidate whose bounds could not be resolved: it never qualifies
     *   while [window] applies, and ranks behind every positioned candidate when it does not.
     * @param window the scan window in view coordinates, or null when the scan window is disabled
     *   or has no area. When null, every candidate qualifies and ranking falls back to
     *   [frameCenterX] / [frameCenterY] — nearest to the middle of the preview, which is still a
     *   better answer than whichever result the detector happened to list first.
     * @param frameCenterX horizontal centre of the preview, used only when [window] is null.
     * @param frameCenterY vertical centre of the preview, used only when [window] is null.
     */
    fun selectNearest(
        candidates: List<Bounds?>,
        window: Bounds?,
        frameCenterX: Float,
        frameCenterY: Float,
    ): Int? {
        val anchorX = window?.centerX ?: frameCenterX
        val anchorY = window?.centerY ?: frameCenterY

        var bestIndex: Int? = null
        var bestDistance = Float.MAX_VALUE
        candidates.forEachIndexed { index, bounds ->
            if (bounds == null || bounds.isEmpty) {
                // Unpositioned: only usable when there is no window to test it against, and only
                // once nothing positioned has qualified.
                if (window == null && bestIndex == null) {
                    bestIndex = index
                }
                return@forEachIndexed
            }
            if (window != null && !bounds.overlaps(window)) {
                return@forEachIndexed
            }
            val dx = bounds.centerX - anchorX
            val dy = bounds.centerY - anchorY
            val distance = sqrt(dx * dx + dy * dy)
            // Strictly nearer, so the earliest candidate wins a tie and selection stays stable
            // across frames.
            if (bestIndex == null || distance < bestDistance) {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
    }
}

/** The scan window as [ScanCandidateSelector.Bounds], or null when it is disabled or has no area. */
internal fun RectF.toScanWindowBounds(): ScanCandidateSelector.Bounds? =
    if (isEmpty) null else ScanCandidateSelector.Bounds(left, top, right, bottom)

/** These bounds as [ScanCandidateSelector.Bounds]. */
internal fun RectF.toCandidateBounds(): ScanCandidateSelector.Bounds =
    ScanCandidateSelector.Bounds(left, top, right, bottom)
