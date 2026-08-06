package com.eventer.flutter_barcode_scanner_sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The Kotlin half of the scan-window geometry contract.
 *
 * The same numbers are asserted by `FlutterBarcodeScannerScanWindow.resolve` in the Dart suite and
 * by `RunnerTests` in Swift. Three implementations exist because the preview is not measured until
 * it is laid out natively, so the config cannot carry a resolved rect — these tests are what keeps
 * them from drifting.
 */
internal class ScannerConfigTest {
    private fun config(window: Map<String, Any?> = emptyMap(), extra: Map<String, Any?> = emptyMap()) =
        ScannerConfig.fromMap(mapOf("scanWindow" to window) + extra)

    // Geometry.

    /// The shape has to survive the container. Fractions on both axes did not: one config drew a
    /// 2.2:1 band in a short embedded preview and a 1:1 square full-screen.
    @Test
    fun windowKeepsItsShapeAcrossPreviewAspectRatios() {
        val subject = config(mapOf("enabled" to true))

        val tall = subject.resolveScanWindow(400, 800)
        val short = subject.resolveScanWindow(400, 340)

        assertEquals(1.5f, tall.width / tall.height, 0.001f)
        assertEquals(1.5f, short.width / short.height, 0.001f)
    }

    @Test
    fun defaultWindowIsCentredAtEightyPercentWidthAndThreeToTwo() {
        val rect = config().resolveScanWindow(400, 800)

        assertEquals(320f, rect.width, 0.001f)
        assertEquals(320f / 1.5f, rect.height, 0.001f)
        assertEquals(200f, rect.centerX, 0.001f)
        assertEquals(400f, rect.centerY, 0.001f)
    }

    @Test
    fun windowShrinksRatherThanLosingItsShapeOnAShortPreview() {
        val rect = config(mapOf("enabled" to true, "aspectRatio" to 0.5)).resolveScanWindow(400, 200)

        assertEquals(180f, rect.height, 0.001f)
        assertEquals(90f, rect.width, 0.001f)
        assertEquals(0.5f, rect.width / rect.height, 0.001f)
    }

    @Test
    fun explicitRectOverridesAspectSizing() {
        val rect = config(
            mapOf(
                "enabled" to true,
                "rect" to mapOf(
                    "left" to 0.1,
                    "top" to 0.2,
                    "width" to 0.8,
                    "height" to 0.4,
                ),
            ),
        ).resolveScanWindow(400, 800)

        assertEquals(40f, rect.left, 0.001f)
        assertEquals(160f, rect.top, 0.001f)
        assertEquals(320f, rect.width, 0.001f)
        assertEquals(320f, rect.height, 0.001f)
    }

    @Test
    fun disabledWindowIsEmpty() {
        assertTrue(config(mapOf("enabled" to false)).resolveScanWindow(400, 800).isEmpty)
    }

    @Test
    fun degeneratePreviewIsEmpty() {
        assertTrue(config().resolveScanWindow(0, 800).isEmpty)
        assertTrue(config().resolveScanWindow(400, 0).isEmpty)
    }

    @Test
    fun outOfRangeValuesAreClamped() {
        val subject = config(
            mapOf(
                "widthFraction" to Double.POSITIVE_INFINITY,
                "aspectRatio" to 99.0,
                "cornerRadius" to -4.0,
            ),
        )

        assertEquals(0.8f, subject.scanWindowWidthFraction)
        assertEquals(5f, subject.scanWindowAspectRatio)
        assertEquals(0f, subject.scanWindowCornerRadius)
    }

    // Aim mode.

    /** Crosshair is the default: it is the only rule that cannot report an unaimed barcode. */
    @Test
    fun aimModeDefaultsToCrosshair() {
        assertTrue(config().requiresCenterOnBarcode())
    }

    /** An unrecognized mode must never widen what can be reported. */
    @Test
    fun unknownAimModeFallsBackToCrosshair() {
        assertTrue(config(mapOf("aimMode" to "laser")).requiresCenterOnBarcode())
    }

    @Test
    fun windowAimModeIsCarried() {
        assertFalse(config(mapOf("aimMode" to "window")).requiresCenterOnBarcode())
    }

    // Confirmation frames.

    @Test
    fun confirmationFramesDefaultsToTwo() {
        assertEquals(2, config().scanConfirmationFrames)
    }

    @Test
    fun confirmationFramesIsClamped() {
        assertEquals(1, config(extra = mapOf("scanConfirmationFrames" to 0)).scanConfirmationFrames)
        assertEquals(10, config(extra = mapOf("scanConfirmationFrames" to 99)).scanConfirmationFrames)
    }
}
