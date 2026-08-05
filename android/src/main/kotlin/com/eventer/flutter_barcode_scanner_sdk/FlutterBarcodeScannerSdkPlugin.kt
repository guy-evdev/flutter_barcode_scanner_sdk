package com.eventer.flutter_barcode_scanner_sdk

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class FlutterBarcodeScannerSdkPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val METHOD_CHANNEL = "flutter_barcode_scanner_sdk/methods"
        private const val SCANNER_VIEW_TYPE = "flutter_barcode_scanner_sdk/scanner_view"
        private const val REQUEST_SCAN = 41012
        private const val REQUEST_PERMISSION = 41013
        private const val PREFS = "flutter_barcode_scanner_sdk"
        private const val KEY_REQUESTED_CAMERA = "has_requested_camera_permission"
    }

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel

    private var activityBinding: ActivityPluginBinding? = null
    private var activity: Activity? = null

    private var pendingScanResult: MethodChannel.Result? = null
    private var pendingScanConfig: ScannerConfig? = null
    private val pendingPermissionResults = mutableListOf<MethodChannel.Result>()
    private var permissionRequestInFlight = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            SCANNER_VIEW_TYPE,
            FlutterBarcodeScannerEmbeddedViewFactory(binding.binaryMessenger) { activity },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        failPendingOperations("PLUGIN_DETACHED", "Scanner plugin detached from the Flutter engine")
        methodChannel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
        failPendingOperations("NO_ACTIVITY", "Scanner is not attached to an activity")
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scan" -> handleScan(call, result)
            "checkCameraPermission" -> result.success(cameraPermissionStatus())
            "requestCameraPermission" -> handlePermissionRequest(result)
            "openAppSettings" -> result.success(openAppSettings())
            else -> result.notImplemented()
        }
    }

    private fun handleScan(call: MethodCall, result: MethodChannel.Result) {
        val hostActivity = activity
        if (hostActivity == null) {
            result.error("NO_ACTIVITY", "Scanner is not attached to an activity", null)
            return
        }

        if (pendingScanResult != null) {
            result.error("SCAN_IN_PROGRESS", "A scan is already in progress", null)
            return
        }

        pendingScanConfig = ScannerConfig.fromMap(call.arguments as? Map<*, *>)
        pendingScanResult = result

        if (hasCameraPermission(hostActivity)) {
            launchScanner(hostActivity, pendingScanConfig!!)
            return
        }

        requestCameraPermissionIfNeeded(hostActivity)
    }

    private fun handlePermissionRequest(result: MethodChannel.Result) {
        val hostActivity = activity
        if (hostActivity == null) {
            result.success(CameraPermissionStatus.DENIED)
            return
        }
        val status = cameraPermissionStatus()
        // Asking again when the system will not prompt would hang the caller on
        // a dialog that never appears, so report the terminal status instead.
        if (status != CameraPermissionStatus.GRANTED &&
            status != CameraPermissionStatus.PERMANENTLY_DENIED
        ) {
            pendingPermissionResults += result
            markCameraPermissionRequested()
            requestCameraPermissionIfNeeded(hostActivity)
            return
        }
        result.success(status)
    }

    /**
     * The permission status reported to Dart.
     *
     * Falls back to the raw grant check when no activity is attached, because
     * `shouldShowRequestPermissionRationale` needs one.
     */
    private fun cameraPermissionStatus(): String {
        val context = activity ?: applicationContext
        val granted = hasCameraPermission(context)
        val hostActivity = activity
        if (granted) {
            return CameraPermissionStatus.GRANTED
        }
        if (hostActivity == null) {
            return CameraPermissionStatus.DENIED
        }
        return CameraPermissionStatus.resolve(
            isGranted = false,
            hasRequestedBefore = hasRequestedCameraPermission(),
            shouldShowRationale = ActivityCompat.shouldShowRequestPermissionRationale(
                hostActivity,
                Manifest.permission.CAMERA,
            ),
        )
    }

    private fun hasRequestedCameraPermission(): Boolean {
        return applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_REQUESTED_CAMERA, false)
    }

    private fun markCameraPermissionRequested() {
        applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_REQUESTED_CAMERA, true)
            .apply()
    }

    private fun openAppSettings(): Boolean {
        val hostActivity = activity ?: return false
        return try {
            hostActivity.startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", hostActivity.packageName, null),
                ),
            )
            true
        } catch (error: RuntimeException) {
            false
        }
    }

    private fun launchScanner(hostActivity: Activity, config: ScannerConfig) {
        try {
            val intent = Intent(hostActivity, FlutterBarcodeScannerMlKitActivity::class.java)
            intent.putExtra(ScannerActivityContract.EXTRA_CONFIG, config)
            @Suppress("DEPRECATION")
            hostActivity.startActivityForResult(intent, REQUEST_SCAN)
        } catch (error: RuntimeException) {
            pendingScanResult?.error(
                "CAMERA_UNAVAILABLE",
                error.localizedMessage ?: config.strings.cameraUnavailable,
                null,
            )
            pendingScanResult = null
            pendingScanConfig = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SCAN) {
            return false
        }

        val result = pendingScanResult
        pendingScanResult = null
        pendingScanConfig = null

        val payload = scannerResultFromIntent(data)
        @Suppress("UNCHECKED_CAST")
        result?.success(payload as? Map<String, Any?> ?: ScannerActivityContract.cancelledResult())
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_PERMISSION) {
            return false
        }

        permissionRequestInFlight = false
        val cameraPermissionIndex = permissions.indexOf(Manifest.permission.CAMERA)
        val granted = cameraPermissionIndex >= 0 &&
            cameraPermissionIndex < grantResults.size &&
            grantResults[cameraPermissionIndex] == PackageManager.PERMISSION_GRANTED

        val status = cameraPermissionStatus()
        val permissionResults = pendingPermissionResults.toList()
        pendingPermissionResults.clear()
        permissionResults.forEach { permissionResult ->
            permissionResult.success(status)
        }

        val hostActivity = activity
        val scanResult = pendingScanResult
        val scanConfig = pendingScanConfig
        if (scanResult != null && scanConfig != null) {
            if (granted && hostActivity != null) {
                launchScanner(hostActivity, scanConfig)
            } else {
                pendingScanResult = null
                pendingScanConfig = null
                scanResult.error(
                    "PERMISSION_DENIED",
                    scanConfig.strings.cameraPermissionRequired,
                    null,
                )
            }
        }

        return true
    }

    private fun hasCameraPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun scannerResultFromIntent(data: Intent?): HashMap<*, *>? {
        if (data == null) {
            return null
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data.getSerializableExtra(
                ScannerActivityContract.EXTRA_RESULT,
                HashMap::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            data.getSerializableExtra(ScannerActivityContract.EXTRA_RESULT) as? HashMap<*, *>
        }
    }

    private fun requestCameraPermissionIfNeeded(hostActivity: Activity) {
        if (permissionRequestInFlight) {
            return
        }
        permissionRequestInFlight = true
        try {
            ActivityCompat.requestPermissions(
                hostActivity,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_PERMISSION,
            )
        } catch (error: RuntimeException) {
            permissionRequestInFlight = false
            failPendingOperations(
                "PERMISSION_REQUEST_FAILED",
                error.localizedMessage ?: "Unable to request camera permission",
            )
        }
    }

    private fun failPendingOperations(code: String, message: String) {
        pendingScanResult?.error(code, message, null)
        pendingScanResult = null
        pendingScanConfig = null
        val permissionResults = pendingPermissionResults.toList()
        pendingPermissionResults.clear()
        permissionResults.forEach { it.success(false) }
        permissionRequestInFlight = false
    }
}
