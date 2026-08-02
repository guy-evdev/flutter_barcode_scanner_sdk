package com.eventer.flutter_barcode_scanner_sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class ScannerUpdatePolicyTest {
    private val baseConfig = ScannerConfig.fromMap(
        mapOf(
            "allowedFormats" to listOf("QR_CODE", "CODE_128"),
            "uiConfig" to mapOf("initialCameraLens" to "back"),
        ),
    )

    @Test
    fun identicalConfigDoesNotRebind() {
        assertFalse(rebindRequired(baseConfig, hasEverStartedCamera = false))
        assertFalse(rebindRequired(baseConfig, hasEverStartedCamera = true))
    }

    @Test
    fun cosmeticChangesDoNotRebind() {
        val next = baseConfig.copy(
            strings = baseConfig.strings.copy(title = "Scan wristband"),
            overlayColor = 0x66FF0000,
            scanWindowEnabled = false,
            scanWindowWidthFactor = 0.9f,
            scanWindowHeightFactor = 0.4f,
            scanWindowCornerRadius = 0f,
            appBarTransparent = true,
            appBarBackgroundColor = 0xFF102030.toInt(),
            appBarForegroundColor = 0xFFFFFFFF.toInt(),
            statusBarTransparent = true,
            statusBarIconBrightness = "dark",
            showFlashButton = false,
            showCameraSwitchButton = false,
            textDirection = "rtl",
            initialTorchEnabled = true,
        )

        assertFalse(rebindRequired(next, hasEverStartedCamera = false))
        assertFalse(rebindRequired(next, hasEverStartedCamera = true))
    }

    @Test
    fun changedFormatsRebind() {
        val next = baseConfig.copy(allowedFormats = listOf("QR_CODE"))

        assertTrue(rebindRequired(next, hasEverStartedCamera = false))
        assertTrue(rebindRequired(next, hasEverStartedCamera = true))
    }

    @Test
    fun addedFormatRebinds() {
        val next = baseConfig.copy(allowedFormats = listOf("QR_CODE", "CODE_128", "EAN_13"))

        assertTrue(rebindRequired(next, hasEverStartedCamera = true))
    }

    @Test
    fun reorderedFormatsDoNotRebind() {
        val next = baseConfig.copy(allowedFormats = listOf("CODE_128", "QR_CODE"))

        assertFalse(rebindRequired(next, hasEverStartedCamera = false))
        assertFalse(rebindRequired(next, hasEverStartedCamera = true))
    }

    @Test
    fun initialLensRebindsOnlyBeforeTheFirstStart() {
        val next = baseConfig.copy(initialCameraLens = "front")

        assertTrue(rebindRequired(next, hasEverStartedCamera = false))
        assertFalse(rebindRequired(next, hasEverStartedCamera = true))
    }

    private fun rebindRequired(next: ScannerConfig, hasEverStartedCamera: Boolean): Boolean {
        return ScannerUpdatePolicy.requiresCameraRebind(
            current = baseConfig,
            next = next,
            hasEverStartedCamera = hasEverStartedCamera,
        )
    }
}

internal class StartAttemptBudgetTest {
    @Test
    fun grantsExactlyTheConfiguredNumberOfAttempts() {
        val budget = StartAttemptBudget(3)

        assertTrue(budget.tryAgain())
        assertTrue(budget.tryAgain())
        assertTrue(budget.tryAgain())
        assertFalse(budget.tryAgain())
        assertFalse(budget.tryAgain())
    }

    @Test
    fun countsOnlyGrantedAttempts() {
        val budget = StartAttemptBudget(2)

        budget.tryAgain()
        assertEquals(1, budget.attempts)
        budget.tryAgain()
        assertEquals(2, budget.attempts)
        budget.tryAgain()
        assertEquals(2, budget.attempts)
    }

    @Test
    fun resetRestoresTheFullAllowance() {
        val budget = StartAttemptBudget(1)

        assertTrue(budget.tryAgain())
        assertFalse(budget.tryAgain())

        budget.reset()

        assertEquals(0, budget.attempts)
        assertTrue(budget.tryAgain())
    }

    @Test
    fun aZeroAllowanceNeverGrantsAnAttempt() {
        val budget = StartAttemptBudget(0)

        assertFalse(budget.tryAgain())
        assertEquals(0, budget.attempts)
    }
}
