package com.eventer.flutter_barcode_scanner_sdk

/**
 * Maps Android's two-state permission model onto the Dart permission contract.
 *
 * Android reports only granted or not-granted. Distinguishing "never asked" from
 * "denied and don't ask again" needs two extra inputs, and neither is available
 * from the system alone:
 *
 * - `shouldShowRequestPermissionRationale` is true only *after* a refusal that
 *   can still be re-prompted, so it separates [DENIED] from [PERMANENTLY_DENIED].
 * - Before the first request it is also false, which is indistinguishable from
 *   permanent denial. The plugin therefore records that it has asked at least
 *   once and passes that in as [hasRequestedBefore].
 *
 * Kept free of Android framework types so it is unit-testable on the JVM.
 */
internal object CameraPermissionStatus {
    const val GRANTED = "granted"
    const val DENIED = "denied"
    const val PERMANENTLY_DENIED = "permanentlyDenied"
    const val NOT_DETERMINED = "notDetermined"

    /**
     * Resolves the status reported to Dart.
     *
     * `restricted` is never returned: it is an iOS device-policy state with no
     * Android equivalent.
     */
    fun resolve(
        isGranted: Boolean,
        hasRequestedBefore: Boolean,
        shouldShowRationale: Boolean,
    ): String {
        if (isGranted) {
            return GRANTED
        }
        if (!hasRequestedBefore) {
            return NOT_DETERMINED
        }
        return if (shouldShowRationale) DENIED else PERMANENTLY_DENIED
    }
}
