package com.eventer.flutter_barcode_scanner_sdk

object ScannerActivityContract {
    const val EXTRA_CONFIG = "flutter_barcode_scanner_sdk_config"
    const val EXTRA_RESULT = "flutter_barcode_scanner_sdk_result"

    fun cancelledResult(): HashMap<String, Any?> = hashMapOf(
        "type" to "cancelled",
        "rawValue" to "",
        "format" to "QR_CODE",
        "errorCode" to null,
        "errorMessage" to null,
    )
}
