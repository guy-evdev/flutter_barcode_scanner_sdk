package com.eventer.flutter_barcode_scanner_sdk

import android.graphics.RectF
import java.io.Serializable

data class ScannerStrings(
    val title: String,
    val close: String,
    val flashOn: String,
    val flashOff: String,
    val switchCamera: String,
    val cameraPermissionRequired: String,
    val cameraUnavailable: String,
) : Serializable

data class ScannerConfig(
    val allowedFormats: List<String>,
    val strings: ScannerStrings,
    val showFlashButton: Boolean,
    val showCameraSwitchButton: Boolean,
    val initialCameraLens: String,
    val initialTorchEnabled: Boolean,
    val keepScreenOn: Boolean,
    val textDirection: String?,
    val scanWindowEnabled: Boolean,
    val scanWindowWidthFraction: Float,
    val scanWindowAspectRatio: Float,
    val scanWindowMaxHeightFraction: Float,
    val scanWindowHasRect: Boolean,
    val scanWindowLeft: Float,
    val scanWindowTop: Float,
    val scanWindowWidth: Float,
    val scanWindowHeight: Float,
    val scanWindowCornerRadius: Float,
    val scanWindowAimMode: String,
    val scanConfirmationFrames: Int,
    val statusBarTransparent: Boolean,
    val statusBarBackgroundColor: Int?,
    val statusBarIconBrightness: String,
    val appBarTransparent: Boolean,
    val appBarBackgroundColor: Int?,
    val appBarForegroundColor: Int?,
    val overlayColor: Int,
) : Serializable {
    companion object {
        /** Aim mode where overlapping the window is enough to qualify. */
        const val AIM_MODE_WINDOW = "window"

        /** Aim mode where the barcode must contain the window's centre. */
        const val AIM_MODE_CROSSHAIR = "crosshair"

        private const val DEFAULT_WIDTH_FRACTION = 0.8f
        private const val DEFAULT_ASPECT_RATIO = 1.5f
        private const val DEFAULT_MAX_HEIGHT_FRACTION = 0.9f

        fun fromMap(map: Map<*, *>?): ScannerConfig {
            val stringsMap = map?.get("strings") as? Map<*, *>
            val uiMap = map?.get("uiConfig") as? Map<*, *>
            val windowMap = map?.get("scanWindow") as? Map<*, *>
            val rectMap = windowMap?.get("rect") as? Map<*, *>
            val statusBarMap = map?.get("statusBarStyle") as? Map<*, *>
            val allowedFormats = (map?.get("allowedFormats") as? List<*>)
                ?.mapNotNull { it as? String }
                ?.mapNotNull(::mapFormat)
                ?.ifEmpty { allFormats() } ?: allFormats()

            return ScannerConfig(
                allowedFormats = allowedFormats,
                strings = ScannerStrings(
                    title = stringsMap?.get("title") as? String ?: "Scan Barcode",
                    close = stringsMap?.get("close") as? String ?: "Close",
                    flashOn = stringsMap?.get("flashOn") as? String ?: "Flash on",
                    flashOff = stringsMap?.get("flashOff") as? String ?: "Flash off",
                    switchCamera = stringsMap?.get("switchCamera") as? String ?: "Switch camera",
                    cameraPermissionRequired =
                        stringsMap?.get("cameraPermissionRequired") as? String
                            ?: "Camera permission is required",
                    cameraUnavailable =
                        stringsMap?.get("cameraUnavailable") as? String
                            ?: "Camera unavailable",
                ),
                showFlashButton = uiMap?.get("showFlashButton") as? Boolean ?: true,
                showCameraSwitchButton =
                    uiMap?.get("showCameraSwitchButton") as? Boolean ?: true,
                initialCameraLens =
                    (uiMap?.get("initialCameraLens") as? String)
                        ?.takeIf { it == "front" || it == "back" }
                        ?: "back",
                initialTorchEnabled =
                    uiMap?.get("initialTorchEnabled") as? Boolean ?: false,
                keepScreenOn = uiMap?.get("keepScreenOn") as? Boolean ?: false,
                textDirection = map?.get("textDirection") as? String,
                scanWindowEnabled =
                    windowMap?.get("enabled") as? Boolean ?: true,
                scanWindowWidthFraction =
                    normalizedFloat(
                        windowMap?.get("widthFraction"),
                        fallback = DEFAULT_WIDTH_FRACTION,
                        minimum = 0.05f,
                        maximum = 1f,
                    ),
                scanWindowAspectRatio =
                    normalizedFloat(
                        windowMap?.get("aspectRatio"),
                        fallback = DEFAULT_ASPECT_RATIO,
                        minimum = 0.2f,
                        maximum = 5f,
                    ),
                scanWindowMaxHeightFraction =
                    normalizedFloat(
                        windowMap?.get("maxHeightFraction"),
                        fallback = DEFAULT_MAX_HEIGHT_FRACTION,
                        minimum = 0.1f,
                        maximum = 1f,
                    ),
                scanWindowHasRect = rectMap != null,
                scanWindowLeft =
                    normalizedFloat(
                        rectMap?.get("left"),
                        fallback = 0.1f,
                        minimum = 0f,
                        maximum = 1f,
                    ),
                scanWindowTop =
                    normalizedFloat(
                        rectMap?.get("top"),
                        fallback = 0.3f,
                        minimum = 0f,
                        maximum = 1f,
                    ),
                scanWindowWidth =
                    normalizedFloat(
                        rectMap?.get("width"),
                        fallback = 0.8f,
                        minimum = 0.05f,
                        maximum = 1f,
                    ),
                scanWindowHeight =
                    normalizedFloat(
                        rectMap?.get("height"),
                        fallback = 0.4f,
                        minimum = 0.05f,
                        maximum = 1f,
                    ),
                // An unrecognized mode falls back to the strict one: a mode this version does
                // not know about must never widen what can be reported.
                scanWindowAimMode =
                    (windowMap?.get("aimMode") as? String)
                        ?.takeIf { it == AIM_MODE_CROSSHAIR || it == AIM_MODE_WINDOW }
                        ?: AIM_MODE_CROSSHAIR,
                scanConfirmationFrames =
                    ((map?.get("scanConfirmationFrames") as? Number)?.toInt() ?: 2)
                        .coerceIn(1, 10),
                scanWindowCornerRadius =
                    normalizedFloat(
                        windowMap?.get("cornerRadius"),
                        fallback = 18f,
                        minimum = 0f,
                        maximum = Float.MAX_VALUE,
                    ),
                statusBarTransparent =
                    statusBarMap?.get("isTransparent") as? Boolean ?: false,
                statusBarBackgroundColor =
                    (statusBarMap?.get("backgroundColor") as? Number)?.toInt(),
                statusBarIconBrightness =
                    statusBarMap?.get("iconBrightness") as? String ?: "light",
                appBarTransparent =
                    map?.get("appBarTransparent") as? Boolean ?: false,
                appBarBackgroundColor =
                    (map?.get("appBarBackgroundColor") as? Number)?.toInt(),
                appBarForegroundColor =
                    (map?.get("appBarForegroundColor") as? Number)?.toInt(),
                overlayColor =
                    ((map?.get("overlayColor") as? Number)?.toInt()
                        ?: 0x99000000.toInt()),
            )
        }

        private fun allFormats() = listOf(
            "QR_CODE",
            "CODE_128",
            "CODE_39",
            "CODE_93",
            "EAN_13",
            "EAN_8",
            "UPC_A",
            "UPC_E",
            "ITF",
            "PDF_417",
            "DATA_MATRIX",
            "AZTEC",
        )

        private fun mapFormat(value: String): String? {
            return when (value) {
                "QR_CODE" -> "QR_CODE"
                "CODE_128" -> "CODE_128"
                "CODE_39" -> "CODE_39"
                "CODE_93" -> "CODE_93"
                "EAN_13" -> "EAN_13"
                "EAN_8" -> "EAN_8"
                "UPC_A" -> "UPC_A"
                "UPC_E" -> "UPC_E"
                "ITF" -> "ITF"
                "PDF_417" -> "PDF_417"
                "DATA_MATRIX" -> "DATA_MATRIX"
                "AZTEC" -> "AZTEC"
                else -> null
            }
        }

        private fun normalizedFloat(
            value: Any?,
            fallback: Float,
            minimum: Float,
            maximum: Float,
        ): Float {
            val number = (value as? Number)?.toFloat()?.takeIf { it.isFinite() } ?: fallback
            return number.coerceIn(minimum, maximum)
        }
    }

    /**
     * The scan window in view pixels, for a preview of [width] x [height].
     *
     * Mirrors `FlutterBarcodeScannerScanWindow.resolve` in Dart and
     * `ScannerConfig.scanWindowRect(in:)` in Swift. The preview is not measured
     * until it is laid out natively, so the config cannot carry a resolved
     * rect and each layer resolves the same rule instead. `ScannerConfigTest`
     * asserts the numbers the other two produce.
     *
     * Without an explicit rect the window is centred, [scanWindowWidthFraction]
     * of the preview wide and that width divided by [scanWindowAspectRatio]
     * tall, shrunk to fit while keeping its shape. Fractions on both axes made
     * the window's shape follow the preview's, so one config drew a flat band
     * in a short embedded preview and a square in the full-screen scanner.
     */
    fun scanWindowRect(width: Int, height: Int): RectF {
        if (!scanWindowEnabled) {
            return RectF()
        }
        val resolved = resolveScanWindow(width, height)
        return RectF(resolved.left, resolved.top, resolved.right, resolved.bottom)
    }

    /** The same window as [scanWindowRect], free of Android types so unit tests can assert it. */
    internal fun resolveScanWindow(width: Int, height: Int): ScanWindowGeometry.Rect {
        if (!scanWindowEnabled) {
            return ScanWindowGeometry.Rect.EMPTY
        }
        return ScanWindowGeometry.resolve(
            previewWidth = width,
            previewHeight = height,
            widthFraction = scanWindowWidthFraction,
            aspectRatio = scanWindowAspectRatio,
            maxHeightFraction = scanWindowMaxHeightFraction,
            rect = if (scanWindowHasRect) {
                ScanWindowGeometry.Rect(
                    scanWindowLeft,
                    scanWindowTop,
                    scanWindowLeft + scanWindowWidth,
                    scanWindowTop + scanWindowHeight,
                )
            } else {
                null
            },
        )
    }

    /** Whether a candidate must contain the window's centre to qualify. */
    fun requiresCenterOnBarcode(): Boolean = scanWindowAimMode == AIM_MODE_CROSSHAIR

    fun resolveStatusBarBackground(): Int? {
        return if (statusBarBackgroundColor == null || statusBarBackgroundColor == Int.MIN_VALUE) {
            null
        } else {
            statusBarBackgroundColor
        }
    }

    fun resolveAppBarBackground(): Int? {
        return if (appBarBackgroundColor == null || appBarBackgroundColor == Int.MIN_VALUE) {
            null
        } else {
            appBarBackgroundColor
        }
    }

    fun resolveAppBarForeground(): Int? {
        return if (appBarForegroundColor == null || appBarForegroundColor == Int.MIN_VALUE) {
            null
        } else {
            appBarForegroundColor
        }
    }
}
