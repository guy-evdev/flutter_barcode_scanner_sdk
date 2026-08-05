package com.example.flutter_barcode_scanner_sdk

import com.eventer.flutter_barcode_scanner_sdk.FlutterBarcodeScannerSdkPlugin
import com.eventer.flutter_barcode_scanner_sdk.ScannerConfig
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class FlutterBarcodeScannerSdkPluginTest {
    @Test
    fun scanWithoutAttachedActivityReturnsError() {
        val plugin = FlutterBarcodeScannerSdkPlugin()
        val call = MethodCall("scan", emptyMap<String, Any?>())
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, result)

        Mockito.verify(result).error(
            "NO_ACTIVITY",
            "Scanner is not attached to an activity",
            null,
        )
    }

    @Test
    fun requestPermissionWithoutAttachedActivityReportsDenied() {
        val plugin = FlutterBarcodeScannerSdkPlugin()
        val call = MethodCall("requestCameraPermission", null)
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, result)

        // Not "granted", and not an error: no activity means no prompt is
        // possible, which is a denial from the caller's point of view.
        Mockito.verify(result).success("denied")
    }

    @Test
    fun unknownMethodIsNotImplemented() {
        val plugin = FlutterBarcodeScannerSdkPlugin()
        val call = MethodCall("unknown", null)
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, result)

        Mockito.verify(result).notImplemented()
    }

    @Test
    fun scannerConfigParsesDefaultsAndCoercesScanWindow() {
        val config = ScannerConfig.fromMap(
            mapOf(
                "allowedFormats" to listOf("QR_CODE", "INVALID", "CODE_128"),
                "scanWindow" to mapOf(
                    "enabled" to true,
                    "left" to 0.1,
                    "top" to 0.3,
                    "width" to 2.0,
                    "height" to 0.4,
                    "cornerRadius" to 24,
                ),
                "uiConfig" to mapOf(
                    "showFlashButton" to false,
                    "initialCameraLens" to "front",
                    "initialTorchEnabled" to true,
                ),
                "overlayColor" to 0x99000000.toInt(),
            ),
        )

        assertEquals(listOf("QR_CODE", "CODE_128"), config.allowedFormats)
        assertEquals("Scan Barcode", config.strings.title)
        assertFalse(config.showFlashButton)
        assertTrue(config.showCameraSwitchButton)
        assertEquals("front", config.initialCameraLens)
        assertTrue(config.initialTorchEnabled)
        // An over-wide window is clamped to the preview rather than rejected.
        assertEquals(1f, config.scanWindowWidth)
        assertEquals(0.4f, config.scanWindowHeight)
        assertEquals(24f, config.scanWindowCornerRadius)
    }

    @Test
    fun scannerConfigRejectsNonFiniteWindowValuesAndInvalidLens() {
        val config = ScannerConfig.fromMap(
            mapOf(
                "scanWindow" to mapOf(
                    "width" to Double.NaN,
                    "height" to Double.POSITIVE_INFINITY,
                    "cornerRadius" to -4,
                ),
                "uiConfig" to mapOf("initialCameraLens" to "external"),
                "overlayColor" to 0x99000000.toInt(),
            ),
        )

        assertEquals(0.8f, config.scanWindowWidth)
        assertEquals(0.4f, config.scanWindowHeight)
        assertEquals(0f, config.scanWindowCornerRadius)
        assertEquals("back", config.initialCameraLens)
    }
}
