package com.eventer.flutter_barcode_scanner_sdk

/**
 * Decides whether a config update actually needs the CameraX use cases rebound.
 *
 * The embedded view used to compare whole [ScannerConfig] instances and restart the camera on
 * any difference, so changing a label or an overlay colour visibly tore the preview down and
 * rebound it. Only the bound use cases and the ML Kit scanner options matter here; everything
 * else is applied in place.
 *
 * Kept free of Android framework types so it is unit-testable on the JVM.
 */
internal object ScannerUpdatePolicy {
    /**
     * True when moving from [current] to [next] changes something the bound use cases or the
     * ML Kit detector options depend on.
     *
     * [hasEverStartedCamera] gates `initialCameraLens`: once the camera has bound, the active
     * lens belongs to `switchCamera` and the initial value can no longer take effect.
     *
     * Formats are compared as sets, because the Dart side holds them in a `Set` and its
     * serialized order carries no meaning — reordering must not cost a rebind.
     */
    fun requiresCameraRebind(
        current: ScannerConfig,
        next: ScannerConfig,
        hasEverStartedCamera: Boolean,
    ): Boolean {
        if (current.allowedFormats.toSet() != next.allowedFormats.toSet()) {
            return true
        }
        return !hasEverStartedCamera && current.initialCameraLens != next.initialCameraLens
    }
}

/**
 * Bounded allowance for deferring camera start until the preview view has been laid out.
 *
 * A Flutter parent collapsed to zero height never lays the preview out, and an uncapped
 * re-post loop then spins the main thread for as long as the view stays mounted.
 */
internal class StartAttemptBudget(private val maxAttempts: Int) {
    /** Attempts consumed since construction or the last [reset]. */
    var attempts: Int = 0
        private set

    /**
     * Consumes one attempt and returns true, or returns false once [maxAttempts] have been
     * consumed without granting another.
     */
    fun tryAgain(): Boolean {
        if (attempts >= maxAttempts) {
            return false
        }
        attempts += 1
        return true
    }

    /** Restores the full allowance so a later start attempt gets its own budget. */
    fun reset() {
        attempts = 0
    }
}
