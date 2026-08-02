package com.eventer.flutter_barcode_scanner_sdk

object ScannerActivityContract {
    const val EXTRA_CONFIG = "flutter_barcode_scanner_sdk_config"
    const val EXTRA_RESULT = "flutter_barcode_scanner_sdk_result"

    /** The format reported when no barcode was decoded. */
    const val UNKNOWN_FORMAT = "UNKNOWN"

    /**
     * Payload for a scan the user dismissed.
     *
     * The format is `UNKNOWN`, not `QR_CODE`: reporting a real format made every cancellation
     * arrive on the Dart side as `FlutterBarcodeScannerFormat.qrCode`.
     */
    fun cancelledResult(): HashMap<String, Any?> = hashMapOf(
        "type" to "cancelled",
        "rawValue" to "",
        "format" to UNKNOWN_FORMAT,
        "errorCode" to null,
        "errorMessage" to null,
    )
}
