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
    fun requestPermissionWithoutAttachedActivityReturnsFalse() {
        val plugin = FlutterBarcodeScannerSdkPlugin()
        val call = MethodCall("requestCameraPermission", null)
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, result)

        Mockito.verify(result).success(false)
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
                    "widthFactor" to 2.0,
                    "heightFactor" to 0.1,
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
        assertEquals("Scan Ticket", config.strings.title)
        assertFalse(config.showFlashButton)
        assertTrue(config.showCameraSwitchButton)
        assertEquals("front", config.initialCameraLens)
        assertTrue(config.initialTorchEnabled)
        assertEquals(0.95f, config.scanWindowWidthFactor)
        assertEquals(0.2f, config.scanWindowHeightFactor)
        assertEquals(24f, config.scanWindowCornerRadius)
    }

    @Test
    fun scannerConfigRejectsNonFiniteWindowValuesAndInvalidLens() {
        val config = ScannerConfig.fromMap(
            mapOf(
                "scanWindow" to mapOf(
                    "widthFactor" to Double.NaN,
                    "heightFactor" to Double.POSITIVE_INFINITY,
                    "cornerRadius" to -4,
                ),
                "uiConfig" to mapOf("initialCameraLens" to "external"),
                "overlayColor" to 0x99000000.toInt(),
            ),
        )

        assertEquals(0.58f, config.scanWindowWidthFactor)
        assertEquals(0.58f, config.scanWindowHeightFactor)
        assertEquals(0f, config.scanWindowCornerRadius)
        assertEquals("back", config.initialCameraLens)
    }
}
