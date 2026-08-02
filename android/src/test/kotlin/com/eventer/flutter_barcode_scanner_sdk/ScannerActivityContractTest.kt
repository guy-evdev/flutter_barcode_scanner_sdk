package com.eventer.flutter_barcode_scanner_sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class ScannerActivityContractTest {
    @Test
    fun cancelledResultReportsUnknownFormat() {
        val payload = ScannerActivityContract.cancelledResult()

        assertEquals("cancelled", payload["type"])
        // Never "QR_CODE": that made every cancellation arrive on the Dart side as a QR scan.
        assertEquals("UNKNOWN", payload["format"])
        assertEquals("", payload["rawValue"])
        assertNull(payload["errorCode"])
        assertNull(payload["errorMessage"])
    }
}
