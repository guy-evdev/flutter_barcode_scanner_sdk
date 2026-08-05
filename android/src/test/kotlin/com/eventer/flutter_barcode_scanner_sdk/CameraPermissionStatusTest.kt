package com.eventer.flutter_barcode_scanner_sdk

import kotlin.test.Test
import kotlin.test.assertEquals

internal class CameraPermissionStatusTest {
    @Test
    fun grantedWinsRegardlessOfHistory() {
        assertEquals(
            CameraPermissionStatus.GRANTED,
            CameraPermissionStatus.resolve(
                isGranted = true,
                hasRequestedBefore = false,
                shouldShowRationale = false,
            ),
        )
    }

    @Test
    fun neverAskedIsNotDetermined() {
        // Android reports the same "not granted, no rationale" state both before
        // the first request and after a permanent denial. Only the recorded
        // history separates them.
        assertEquals(
            CameraPermissionStatus.NOT_DETERMINED,
            CameraPermissionStatus.resolve(
                isGranted = false,
                hasRequestedBefore = false,
                shouldShowRationale = false,
            ),
        )
    }

    @Test
    fun refusedOnceIsDenied() {
        assertEquals(
            CameraPermissionStatus.DENIED,
            CameraPermissionStatus.resolve(
                isGranted = false,
                hasRequestedBefore = true,
                shouldShowRationale = true,
            ),
        )
    }

    @Test
    fun refusedWithoutRationaleIsPermanent() {
        assertEquals(
            CameraPermissionStatus.PERMANENTLY_DENIED,
            CameraPermissionStatus.resolve(
                isGranted = false,
                hasRequestedBefore = true,
                shouldShowRationale = false,
            ),
        )
    }
}
