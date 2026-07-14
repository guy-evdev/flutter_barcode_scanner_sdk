package com.eventer.flutter_barcode_scanner_sdk

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.camera.view.transform.CoordinateTransform
import androidx.camera.view.transform.ImageProxyTransformFactory
import androidx.camera.view.transform.OutputTransform
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.common.util.concurrent.ListenableFuture
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class FlutterBarcodeScannerEmbeddedViewFactory(
    private val binaryMessenger: BinaryMessenger,
    private val activityProvider: () -> Activity?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return FlutterBarcodeScannerEmbeddedView(
            context = context,
            viewId = viewId,
            args = args as? Map<*, *>,
            binaryMessenger = binaryMessenger,
            activityProvider = activityProvider,
        )
    }
}

class FlutterBarcodeScannerEmbeddedView(
    private val context: Context,
    viewId: Int,
    args: Map<*, *>?,
    binaryMessenger: BinaryMessenger,
    private val activityProvider: () -> Activity?,
) : PlatformView,
    MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(binaryMessenger, "flutter_barcode_scanner_sdk/scanner_view/$viewId")
    private val rootView = FrameLayout(context)
    private val previewView = PreviewView(context)
    private val freezeView = ImageView(context)
    private val transformLock = Any()
    private val isProcessingFrame = AtomicBoolean(false)

    private var config = ScannerConfig.fromMap(args?.get("config") as? Map<*, *>)
    private var autoPauseOnScan = args?.get("autoPauseOnScan") as? Boolean ?: true
    private var freezePreviewWhenPaused = freezePreviewWhenPausedFrom(args)
    private var cameraProviderFuture: ListenableFuture<ProcessCameraProvider>? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var barcodeScanner: BarcodeScanner? = null
    private var lensFacing = if (config.initialCameraLens == "front") CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
    private var isFlashEnabled = config.initialTorchEnabled
    private var shouldStartCamera = false
    private var startGeneration = 0
    private var isCameraRunning = false
    private var hasEverStartedCamera = false
    private var isDetectionPaused = false
    private var isDisposed = false
    private var cachedOverlayRect = RectF()
    private var cachedPreviewTransform: OutputTransform? = null
    private var frozenBitmap: Bitmap? = null

    init {
        rootView.setBackgroundColor(Color.BLACK)
        rootView.addView(
            previewView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        freezeView.scaleType = ImageView.ScaleType.FIT_XY
        freezeView.visibility = View.GONE
        rootView.addView(
            freezeView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
        // TextureView-backed composition keeps the embedded preview clipped to
        // Flutter widget bounds.
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        previewView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            refreshCachedPreviewData()
        }
        channel.setMethodCallHandler(this)
        if (args?.get("autoStart") as? Boolean ?: true) {
            previewView.post { startCamera() }
        } else {
            emitState("idle")
        }
    }

    override fun getView(): View = rootView

    override fun dispose() {
        isDisposed = true
        stopCamera(emitState = false)
        barcodeScanner?.close()
        barcodeScanner = null
        channel.setMethodCallHandler(null)
        analysisExecutor.shutdownNow()
        emitState("disposed")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCamera" -> {
                startCamera()
                result.success(null)
            }
            "stopCamera" -> {
                stopCamera()
                result.success(null)
            }
            "pauseDetection" -> {
                pauseDetection()
                result.success(null)
            }
            "resumeDetection" -> {
                resumeDetection()
                result.success(null)
            }
            "toggleFlash" -> {
                val requested = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
                toggleFlash(requested, result)
            }
            "switchCamera" -> {
                val lens = (call.arguments as? Map<*, *>)?.get("lens") as? String
                if (switchCamera(lens)) {
                    result.success(null)
                } else {
                    result.error(
                        "CAMERA_UNAVAILABLE",
                        "The requested camera lens is unavailable.",
                        null,
                    )
                }
            }
            "updateConfig" -> {
                updateConfig(call.arguments as? Map<*, *>)
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startCamera() {
        if (isDisposed || isCameraRunning || shouldStartCamera) {
            return
        }
        if (previewView.width <= 0 || previewView.height <= 0) {
            emitState("initializing")
            previewView.post { startCamera() }
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            emitError("PERMISSION_DENIED", config.strings.cameraPermissionRequired)
            emitState("error")
            return
        }

        previewView.visibility = View.VISIBLE
        clearFrozenPreview()
        shouldStartCamera = true
        startGeneration += 1
        val generation = startGeneration
        emitState("initializing")
        ensureScanner()
        val future = cameraProviderFuture ?: ProcessCameraProvider.getInstance(context).also {
            cameraProviderFuture = it
        }
        future.addListener(
            {
                if (isDisposed || !shouldStartCamera || generation != startGeneration) {
                    return@addListener
                }
                try {
                    cameraProvider = future.get()
                    bindCamera(generation)
                } catch (error: Exception) {
                    shouldStartCamera = false
                    emitError("CAMERA_UNAVAILABLE", error.localizedMessage ?: config.strings.cameraUnavailable)
                    emitState("error")
                }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun bindCamera(generation: Int? = null) {
        if (isDisposed ||
            (!shouldStartCamera && !isCameraRunning) ||
            (generation != null && generation != startGeneration)
        ) {
            return
        }
        val owner = activityProvider() as? LifecycleOwner
        if (owner == null) {
            shouldStartCamera = false
            emitError("NO_LIFECYCLE_OWNER", "Host activity is not a LifecycleOwner.")
            emitState("error")
            return
        }
        val provider = cameraProvider ?: return
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()

        val previewUseCase = Preview.Builder().build().also { useCase ->
            useCase.setSurfaceProvider(previewView.surfaceProvider)
        }
        val analysisUseCase = ImageAnalysis.Builder()
            .setResolutionSelector(barcodeAnalysisResolutionSelector())
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { useCase ->
                useCase.setAnalyzer(analysisExecutor) { imageProxy ->
                    analyzeImage(imageProxy)
                }
            }

        try {
            analysis?.clearAnalyzer()
            unbindCurrentUseCases(provider)
            preview = previewUseCase
            analysis = analysisUseCase
            // Keep embedded binding aligned with the full-screen ML Kit scanner.
            // A ViewPort/UseCaseGroup plus a fixed analysis resolution can make
            // CameraX report mismatched source/target viewports, which shifts
            // the barcode-to-preview coordinate transform used for ROI checks.
            camera = provider.bindToLifecycle(owner, selector, previewUseCase, analysisUseCase)
            hasEverStartedCamera = true
            val boundCamera = camera
            if (boundCamera?.cameraInfo?.hasFlashUnit() != true) {
                isFlashEnabled = false
            } else {
                boundCamera.cameraControl.enableTorch(isFlashEnabled)
            }
            shouldStartCamera = false
            isCameraRunning = true
            previewView.visibility = View.VISIBLE
            previewView.post { refreshCachedPreviewData() }
            emitState(if (isDetectionPaused) "detectionPaused" else "running")
        } catch (error: Exception) {
            shouldStartCamera = false
            emitError("CAMERA_UNAVAILABLE", error.localizedMessage ?: config.strings.cameraUnavailable)
            emitState("error")
        }
    }

    private fun stopCamera(emitState: Boolean = true) {
        shouldStartCamera = false
        startGeneration += 1
        isCameraRunning = false
        isProcessingFrame.set(false)
        analysis?.clearAnalyzer()
        cameraProvider?.let(::unbindCurrentUseCases)
        preview?.setSurfaceProvider(null)
        preview = null
        analysis = null
        camera = null
        barcodeScanner?.close()
        barcodeScanner = null
        previewView.post {
            previewView.visibility = View.INVISIBLE
        }
        clearFrozenPreview()
        if (emitState && !isDisposed) {
            emitState("cameraStopped")
        }
    }

    private fun pauseDetection() {
        showFrozenPreview()
        isDetectionPaused = true
        if (isCameraRunning) {
            emitState("detectionPaused")
        }
    }

    private fun resumeDetection() {
        if (!isCameraRunning) {
            emitState("cameraStopped")
            return
        }
        isDetectionPaused = false
        clearFrozenPreview()
        emitState("running")
    }

    private fun toggleFlash(enabled: Boolean?, result: MethodChannel.Result) {
        val activeCamera = camera
        if (activeCamera == null || !isCameraRunning || !activeCamera.cameraInfo.hasFlashUnit()) {
            isFlashEnabled = false
            result.success(false)
            return
        }
        val requested = enabled ?: !isFlashEnabled
        val operation = activeCamera.cameraControl.enableTorch(requested)
        operation.addListener(
            {
                try {
                    operation.get()
                    isFlashEnabled = requested
                    result.success(isFlashEnabled)
                } catch (error: Exception) {
                    isFlashEnabled = activeCamera.cameraInfo.torchState.value == androidx.camera.core.TorchState.ON
                    emitError("TORCH_UNAVAILABLE", error.localizedMessage ?: "Unable to change torch state")
                    result.error(
                        "TORCH_UNAVAILABLE",
                        error.localizedMessage ?: "Unable to change torch state",
                        null,
                    )
                }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun switchCamera(lens: String?): Boolean {
        val requestedLens =
            when (lens) {
                "front" -> CameraSelector.LENS_FACING_FRONT
                "back" -> CameraSelector.LENS_FACING_BACK
                else ->
                    if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                        CameraSelector.LENS_FACING_BACK
                    } else {
                        CameraSelector.LENS_FACING_FRONT
                    }
            }
        if (requestedLens == lensFacing) {
            return true
        }
        val selector = CameraSelector.Builder().requireLensFacing(requestedLens).build()
        val provider = cameraProvider
        if (provider != null && !runCatching { provider.hasCamera(selector) }.getOrDefault(false)) {
            return false
        }
        lensFacing = requestedLens
        isFlashEnabled = false
        if (isCameraRunning) {
            bindCamera()
        }
        return true
    }

    private fun unbindCurrentUseCases(provider: ProcessCameraProvider) {
        val useCases = listOfNotNull<UseCase>(preview, analysis)
        if (useCases.isNotEmpty()) {
            provider.unbind(*useCases.toTypedArray())
        }
    }

    private fun updateConfig(arguments: Map<*, *>?) {
        val nextConfig = ScannerConfig.fromMap(arguments)
        val nextAutoPauseOnScan = (arguments?.get("autoPauseOnScan") as? Boolean) ?: autoPauseOnScan
        val nextFreezePreviewWhenPaused = freezePreviewWhenPausedFrom(arguments)
        if (nextConfig == config) {
            autoPauseOnScan = nextAutoPauseOnScan
            freezePreviewWhenPaused = nextFreezePreviewWhenPaused
            if (!freezePreviewWhenPaused) {
                clearFrozenPreview()
            } else if (isDetectionPaused) {
                showFrozenPreview()
            }
            return
        }
        val wasRunning = isCameraRunning
        val wasPaused = isDetectionPaused
        stopCamera(emitState = false)
        config = nextConfig
        autoPauseOnScan = nextAutoPauseOnScan
        freezePreviewWhenPaused = nextFreezePreviewWhenPaused
        if (!hasEverStartedCamera) {
            lensFacing = if (config.initialCameraLens == "front") CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
            isFlashEnabled = config.initialTorchEnabled
        }
        isDetectionPaused = wasPaused
        refreshCachedPreviewData()
        if (wasRunning) {
            startCamera()
        }
    }

    private fun analyzeImage(imageProxy: androidx.camera.core.ImageProxy) {
        if (isDisposed || !isCameraRunning || isDetectionPaused || !isProcessingFrame.compareAndSet(false, true)) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            isProcessingFrame.set(false)
            imageProxy.close()
            return
        }

        val inputImage = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        val overlayRect: RectF
        val previewTransform: OutputTransform?
        synchronized(transformLock) {
            previewTransform = cachedPreviewTransform
            overlayRect = RectF(cachedOverlayRect)
        }
        if (previewTransform == null || (config.scanWindowEnabled && overlayRect.isEmpty)) {
            previewView.post { refreshCachedPreviewData() }
        }
        val imageTransform =
            ImageProxyTransformFactory()
                .apply {
                    isUsingCropRect = true
                    isUsingRotationDegrees = true
                }
                .getOutputTransform(imageProxy)
        val coordinateTransform = previewTransform?.let { CoordinateTransform(imageTransform, it) }

        ensureScanner().process(inputImage)
            .addOnSuccessListener(ContextCompat.getMainExecutor(context)) { barcodes ->
                if (isDisposed || isDetectionPaused) {
                    return@addOnSuccessListener
                }
                val matchedBarcode = barcodes.firstOrNull { barcode ->
                    barcode.rawValue?.isNotBlank() == true &&
                        (!config.scanWindowEnabled ||
                            (coordinateTransform != null && isBarcodeInsideOverlay(barcode, overlayRect, coordinateTransform)))
                }
                if (matchedBarcode != null) {
                    if (autoPauseOnScan) {
                        showFrozenPreview()
                        isDetectionPaused = true
                    }
                    emitResult(matchedBarcode)
                    if (autoPauseOnScan) {
                        emitState("detectionPaused")
                    }
                }
            }
            .addOnCompleteListener(ContextCompat.getMainExecutor(context)) {
                isProcessingFrame.set(false)
                imageProxy.close()
            }
    }

    private fun isBarcodeInsideOverlay(
        barcode: Barcode,
        overlayRect: RectF,
        coordinateTransform: CoordinateTransform,
    ): Boolean {
        if (overlayRect.isEmpty) {
            return false
        }
        val boundingBox = barcode.boundingBox ?: return false
        val mappedRect = RectF(boundingBox)
        coordinateTransform.mapRect(mappedRect)
        return overlayRect.contains(mappedRect.centerX(), mappedRect.centerY())
    }

    private fun barcodeAnalysisResolutionSelector(): ResolutionSelector {
        return ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
            .setResolutionStrategy(
                ResolutionStrategy(
                    Size(1280, 720),
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                ),
            )
            .build()
    }

    private fun ensureScanner(): BarcodeScanner {
        val current = barcodeScanner
        if (current != null) {
            return current
        }
        return BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(
                    resolveMlKitFormats().firstOrNull() ?: Barcode.FORMAT_QR_CODE,
                    *resolveMlKitFormats().drop(1).toIntArray(),
                )
                .build(),
        ).also { scanner ->
            barcodeScanner = scanner
        }
    }

    private fun resolveMlKitFormats(): List<Int> {
        return config.allowedFormats.mapNotNull { format ->
            when (format) {
                "QR_CODE" -> Barcode.FORMAT_QR_CODE
                "CODE_128" -> Barcode.FORMAT_CODE_128
                "CODE_39" -> Barcode.FORMAT_CODE_39
                "CODE_93" -> Barcode.FORMAT_CODE_93
                "EAN_13" -> Barcode.FORMAT_EAN_13
                "EAN_8" -> Barcode.FORMAT_EAN_8
                "UPC_A" -> Barcode.FORMAT_UPC_A
                "UPC_E" -> Barcode.FORMAT_UPC_E
                "ITF" -> Barcode.FORMAT_ITF
                "PDF_417" -> Barcode.FORMAT_PDF417
                "DATA_MATRIX" -> Barcode.FORMAT_DATA_MATRIX
                "AZTEC" -> Barcode.FORMAT_AZTEC
                else -> null
            }
        }.ifEmpty { listOf(Barcode.FORMAT_QR_CODE, Barcode.FORMAT_CODE_128) }
    }

    private fun mapMlKitFormat(format: Int): String {
        return when (format) {
            Barcode.FORMAT_QR_CODE -> "QR_CODE"
            Barcode.FORMAT_CODE_128 -> "CODE_128"
            Barcode.FORMAT_CODE_39 -> "CODE_39"
            Barcode.FORMAT_CODE_93 -> "CODE_93"
            Barcode.FORMAT_EAN_13 -> "EAN_13"
            Barcode.FORMAT_EAN_8 -> "EAN_8"
            Barcode.FORMAT_UPC_A -> "UPC_A"
            Barcode.FORMAT_UPC_E -> "UPC_E"
            Barcode.FORMAT_ITF -> "ITF"
            Barcode.FORMAT_PDF417 -> "PDF_417"
            Barcode.FORMAT_DATA_MATRIX -> "DATA_MATRIX"
            Barcode.FORMAT_AZTEC -> "AZTEC"
            else -> "UNKNOWN"
        }
    }

    private fun refreshCachedPreviewData() {
        val outputTransform = previewView.outputTransform ?: return
        val overlayRect = scanWindowRect()
        synchronized(transformLock) {
            cachedPreviewTransform = outputTransform
            cachedOverlayRect = overlayRect
        }
    }

    private fun scanWindowRect(): RectF {
        if (!config.scanWindowEnabled || previewView.width <= 0 || previewView.height <= 0) {
            return RectF()
        }
        val requestedWidth = previewView.width * config.scanWindowWidthFactor
        val requestedHeight = previewView.height * config.scanWindowHeightFactor
        val useSquare = kotlin.math.abs(config.scanWindowWidthFactor - config.scanWindowHeightFactor) < 0.001f
        val width = if (useSquare) minOf(requestedWidth, requestedHeight) else requestedWidth
        val height = if (useSquare) width else requestedHeight
        val left = (previewView.width - width) / 2f
        val top = (previewView.height - height) / 2f
        return RectF(left, top, left + width, top + height)
    }

    private fun showFrozenPreview() {
        if (!freezePreviewWhenPaused || previewView.width <= 0 || previewView.height <= 0) {
            return
        }
        mainHandler.post {
            val bitmap = snapshotPreviewBitmap() ?: return@post
            recycleFrozenBitmap()
            frozenBitmap = bitmap
            freezeView.setImageBitmap(bitmap)
            freezeView.visibility = View.VISIBLE
        }
    }

    private fun clearFrozenPreview() {
        mainHandler.post {
            freezeView.setImageDrawable(null)
            freezeView.visibility = View.GONE
            recycleFrozenBitmap()
        }
    }

    private fun recycleFrozenBitmap() {
        frozenBitmap?.takeIf { !it.isRecycled }?.recycle()
        frozenBitmap = null
    }

    private fun freezePreviewWhenPausedFrom(arguments: Map<*, *>?): Boolean {
        val widgetConfig = arguments?.get("widgetConfig") as? Map<*, *>
        return widgetConfig?.get("freezePreviewWhenPaused") as? Boolean ?: false
    }

    private fun snapshotPreviewBitmap(): Bitmap? {
        val textureBitmap = findTextureView(previewView)?.bitmap
        if (textureBitmap != null) {
            return textureBitmap
        }

        val previewBitmap = previewView.bitmap
        if (previewBitmap != null) {
            return previewBitmap
        }

        return runCatching {
            Bitmap.createBitmap(previewView.width, previewView.height, Bitmap.Config.ARGB_8888).also { bitmap ->
                previewView.draw(Canvas(bitmap))
            }
        }.getOrNull()
    }

    private fun findTextureView(view: View): TextureView? {
        if (view is TextureView) {
            return view
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                val textureView = findTextureView(view.getChildAt(index))
                if (textureView != null) {
                    return textureView
                }
            }
        }
        return null
    }

    private fun emitResult(barcode: Barcode) {
        invokeOnMain(
            "onResult",
            hashMapOf(
                "type" to "barcode",
                "rawValue" to barcode.rawValue,
                "format" to mapMlKitFormat(barcode.format),
                "errorCode" to null,
                "errorMessage" to null,
            ),
        )
    }

    private fun emitState(state: String) {
        invokeOnMain("onState", state)
    }

    private fun emitError(code: String, message: String) {
        invokeOnMain(
            "onError",
            hashMapOf(
                "code" to code,
                "message" to message,
                "details" to null,
            ),
        )
    }

    private fun invokeOnMain(method: String, arguments: Any?) {
        mainHandler.post {
            if (!isDisposed || method == "onState") {
                channel.invokeMethod(method, arguments)
            }
        }
    }
}
