package com.eventer.flutter_barcode_scanner_sdk

import android.graphics.Color
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
    val textDirection: String?,
    val scanWindowEnabled: Boolean,
    val scanWindowWidthFactor: Float,
    val scanWindowHeightFactor: Float,
    val scanWindowCornerRadius: Float,
    val statusBarTransparent: Boolean,
    val statusBarBackgroundColor: Int?,
    val statusBarIconBrightness: String,
    val appBarTransparent: Boolean,
    val appBarBackgroundColor: Int?,
    val appBarForegroundColor: Int?,
    val overlayColor: Int,
) : Serializable {
    companion object {
        fun fromMap(map: Map<*, *>?): ScannerConfig {
            val stringsMap = map?.get("strings") as? Map<*, *>
            val uiMap = map?.get("uiConfig") as? Map<*, *>
            val windowMap = map?.get("scanWindow") as? Map<*, *>
            val statusBarMap = map?.get("statusBarStyle") as? Map<*, *>
            val allowedFormats = (map?.get("allowedFormats") as? List<*>)
                ?.mapNotNull { it as? String }
                ?.mapNotNull(::mapFormat)
                ?.ifEmpty { allFormats() } ?: allFormats()

            return ScannerConfig(
                allowedFormats = allowedFormats,
                strings = ScannerStrings(
                    title = stringsMap?.get("title") as? String ?: "Scan Ticket",
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
                    uiMap?.get("initialCameraLens") as? String ?: "back",
                initialTorchEnabled =
                    uiMap?.get("initialTorchEnabled") as? Boolean ?: false,
                textDirection = map?.get("textDirection") as? String,
                scanWindowEnabled =
                    windowMap?.get("enabled") as? Boolean ?: true,
                scanWindowWidthFactor =
                    ((windowMap?.get("widthFactor") as? Number)?.toFloat() ?: 0.58f)
                        .coerceIn(0.2f, 0.95f),
                scanWindowHeightFactor =
                    ((windowMap?.get("heightFactor") as? Number)?.toFloat() ?: 0.58f)
                        .coerceIn(0.2f, 0.9f),
                scanWindowCornerRadius =
                    (windowMap?.get("cornerRadius") as? Number)?.toFloat() ?: 18f,
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
                        ?: Color.parseColor("#99000000")),
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
    }

    fun toIntentMap(): HashMap<String, Serializable> {
        return hashMapOf(
            "allowedFormats" to ArrayList(allowedFormats),
            "strings" to strings,
            "showFlashButton" to showFlashButton,
            "showCameraSwitchButton" to showCameraSwitchButton,
            "initialCameraLens" to initialCameraLens,
            "initialTorchEnabled" to initialTorchEnabled,
            "textDirection" to (textDirection ?: ""),
            "scanWindowEnabled" to scanWindowEnabled,
            "scanWindowWidthFactor" to scanWindowWidthFactor,
            "scanWindowHeightFactor" to scanWindowHeightFactor,
            "scanWindowCornerRadius" to scanWindowCornerRadius,
            "statusBarTransparent" to statusBarTransparent,
            "statusBarBackgroundColor" to (statusBarBackgroundColor ?: Int.MIN_VALUE),
            "statusBarIconBrightness" to statusBarIconBrightness,
            "appBarTransparent" to appBarTransparent,
            "appBarBackgroundColor" to (appBarBackgroundColor ?: Int.MIN_VALUE),
            "appBarForegroundColor" to (appBarForegroundColor ?: Int.MIN_VALUE),
            "overlayColor" to overlayColor,
        )
    }

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
