package com.eventer.flutter_barcode_scanner_sdk

/**
 * Resolves the scan window against a preview size.
 *
 * Mirrors `FlutterBarcodeScannerScanWindow.resolve` in Dart and `ScannerConfig.scanWindowRect(in:)`
 * in Swift. The preview is not measured until it is laid out natively, so the config cannot carry
 * a resolved rect and each layer resolves the same rule instead. `ScannerConfigTest` asserts the
 * numbers the other two produce.
 *
 * Deliberately free of Android framework types — `RectF` is not available to JVM unit tests — so
 * the geometry that decides what gets scanned is covered without an instrumentation run.
 */
internal object ScanWindowGeometry {
    /** An axis-aligned rectangle in view pixels. */
    data class Rect(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top
        val centerX: Float get() = (left + right) / 2f
        val centerY: Float get() = (top + bottom) / 2f
        val isEmpty: Boolean get() = left >= right || top >= bottom

        companion object {
            val EMPTY = Rect(0f, 0f, 0f, 0f)
        }
    }

    /**
     * The window for a preview of [previewWidth] x [previewHeight].
     *
     * With [rect] set the window is that rect scaled onto the preview, so its shape follows the
     * preview's. Without one it is centred, [widthFraction] of the preview wide and that width
     * divided by [aspectRatio] tall — shrunk to fit while keeping its shape, never taller than
     * [maxHeightFraction] of the preview. Fractions on both axes were what made one config draw a
     * flat band in a short embedded preview and a square in the full-screen scanner.
     */
    fun resolve(
        previewWidth: Int,
        previewHeight: Int,
        widthFraction: Float,
        aspectRatio: Float,
        maxHeightFraction: Float,
        rect: Rect? = null,
    ): Rect {
        if (previewWidth <= 0 || previewHeight <= 0) {
            return Rect.EMPTY
        }
        if (rect != null) {
            return Rect(
                rect.left * previewWidth,
                rect.top * previewHeight,
                rect.right * previewWidth,
                rect.bottom * previewHeight,
            )
        }
        var width = widthFraction * previewWidth
        var height = width / aspectRatio
        val maxHeight = previewHeight * maxHeightFraction
        if (height > maxHeight) {
            height = maxHeight
            width = height * aspectRatio
        }
        if (width > previewWidth) {
            width = previewWidth.toFloat()
            height = width / aspectRatio
        }
        val left = (previewWidth - width) / 2f
        val top = (previewHeight - height) / 2f
        return Rect(left, top, left + width, top + height)
    }
}
