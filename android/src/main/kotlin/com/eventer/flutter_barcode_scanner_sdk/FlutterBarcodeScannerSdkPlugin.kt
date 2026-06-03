package com.eventer.flutter_barcode_scanner_sdk

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
    }

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel

    private var activityBinding: ActivityPluginBinding? = null
    private var activity: Activity? = null

    private var pendingScanResult: MethodChannel.Result? = null
    private var pendingScanConfig: ScannerConfig? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

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
            "requestCameraPermission" -> handlePermissionRequest(result)
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

        ActivityCompat.requestPermissions(
            hostActivity,
            arrayOf(Manifest.permission.CAMERA),
            REQUEST_PERMISSION,
        )
    }

    private fun handlePermissionRequest(result: MethodChannel.Result) {
        val hostActivity = activity
        if (hostActivity == null) {
            result.success(false)
            return
        }
        if (hasCameraPermission(hostActivity)) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            hostActivity,
            arrayOf(Manifest.permission.CAMERA),
            REQUEST_PERMISSION,
        )
    }

    private fun launchScanner(hostActivity: Activity, config: ScannerConfig) {
        val intent = Intent(hostActivity, FlutterBarcodeScannerMlKitActivity::class.java)
        intent.putExtra(ScannerActivityContract.EXTRA_CONFIG, config)
        hostActivity.startActivityForResult(intent, REQUEST_SCAN)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SCAN) {
            return false
        }

        val result = pendingScanResult
        pendingScanResult = null
        pendingScanConfig = null

        val payload = data?.getSerializableExtra(ScannerActivityContract.EXTRA_RESULT) as? HashMap<*, *>
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

        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED

        pendingPermissionResult?.let { permissionResult ->
            pendingPermissionResult = null
            permissionResult.success(granted)
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
}
