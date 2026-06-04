package com.eventer.flutter_barcode_scanner_sdk

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.graphics.RectF
import android.os.Bundle
import android.text.TextUtils
import android.util.Size
import android.view.Gravity
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.camera.view.transform.CoordinateTransform
import androidx.camera.view.transform.ImageProxyTransformFactory
import androidx.camera.view.transform.OutputTransform
import androidx.core.content.ContextCompat
import androidx.core.graphics.toColorInt
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.google.common.util.concurrent.ListenableFuture
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.io.Serializable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class FlutterBarcodeScannerMlKitActivity : ComponentActivity() {
    private lateinit var config: ScannerConfig
    private lateinit var previewView: PreviewView
    private lateinit var overlayView: ScanWindowOverlayView
    private lateinit var flashButton: ImageButton
    private lateinit var switchCameraButton: ImageButton

    private lateinit var cameraProviderFuture: ListenableFuture<ProcessCameraProvider>
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var analysis: ImageAnalysis? = null
    private var preview: Preview? = null
    private var hasReturnedResult = false
    private var isFlashEnabled = false
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var isAnalyzerBusy = false
    private val transformLock = Any()
    private var cachedOverlayRect = RectF()
    private var cachedPreviewTransform: OutputTransform? = null

    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val barcodeScanner by lazy {
        BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(
                    resolveMlKitFormats().firstOrNull() ?: Barcode.FORMAT_QR_CODE,
                    *resolveMlKitFormats().drop(1).toIntArray(),
                )
                .build(),
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        config = intent.getSerializableExtra(ScannerActivityContract.EXTRA_CONFIG) as? ScannerConfig
            ?: ScannerConfig.fromMap(emptyMap<String, Serializable>())
        lensFacing =
            if (config.initialCameraLens == "front") {
                CameraSelector.LENS_FACING_FRONT
            } else {
                CameraSelector.LENS_FACING_BACK
            }
        isFlashEnabled = config.initialTorchEnabled

        requestedOrientation = resolveCurrentOrientation()
        applyWindowStyle()
        setContentView(buildContentView())
        cameraProviderFuture = ProcessCameraProvider.getInstance(this)
    }

    override fun onResume() {
        super.onResume()
        bindCamera()
    }

    override fun onPause() {
        cameraProvider?.unbindAll()
        super.onPause()
    }

    override fun onDestroy() {
        cameraProvider?.unbindAll()
        barcodeScanner.close()
        analysisExecutor.shutdown()
        super.onDestroy()
    }

    override fun onBackPressed() {
        finishWithPayload(ScannerActivityContract.cancelledResult())
    }

    private fun bindCamera() {
        cameraProviderFuture.addListener(
            {
                val provider = cameraProviderFuture.get()
                cameraProvider = provider

                val selector = CameraSelector.Builder()
                    .requireLensFacing(lensFacing)
                    .build()

                preview = Preview.Builder().build().also { previewUseCase ->
                    previewUseCase.surfaceProvider = previewView.surfaceProvider
                }

                analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(barcodeAnalysisResolutionSelector())
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { analysisUseCase ->
                        analysisUseCase.setAnalyzer(analysisExecutor) { imageProxy ->
                            analyzeImage(imageProxy)
                        }
                    }

                provider.unbindAll()
                camera = provider.bindToLifecycle(this, selector, preview, analysis)
                camera?.cameraControl?.enableTorch(isFlashEnabled)
                previewView.post { refreshCachedPreviewData() }
                updateFlashButtonUi()
            },
            ContextCompat.getMainExecutor(this),
        )
    }

    private fun analyzeImage(imageProxy: androidx.camera.core.ImageProxy) {
        if (hasReturnedResult || isAnalyzerBusy) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        isAnalyzerBusy = true
        val inputImage = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        val overlayRect: RectF
        val previewTransform: OutputTransform?
        synchronized(transformLock) {
            previewTransform = cachedPreviewTransform
            overlayRect = RectF(cachedOverlayRect)
        }
        if (previewTransform == null || overlayRect.isEmpty) {
            previewView.post { refreshCachedPreviewData() }
        }
        val imageTransform =
            ImageProxyTransformFactory()
                .apply {
                    isUsingCropRect = true
                    isUsingRotationDegrees = true
                }
                .getOutputTransform(imageProxy)
        val coordinateTransform =
            previewTransform?.let { CoordinateTransform(imageTransform, it) }

        barcodeScanner.process(inputImage)
            .addOnSuccessListener(ContextCompat.getMainExecutor(this)) { barcodes ->
                if (hasReturnedResult) {
                    return@addOnSuccessListener
                }
                val matchedBarcode =
                    if (!config.scanWindowEnabled) {
                        barcodes.firstOrNull { barcode ->
                            barcode.rawValue?.isNotBlank() == true
                        }
                    } else {
                        barcodes.firstOrNull { barcode ->
                            barcode.rawValue?.isNotBlank() == true &&
                                barcode.boundingBox != null &&
                                coordinateTransform != null &&
                                isBarcodeInsideOverlay(barcode, overlayRect, coordinateTransform)
                        }
                    }

                if (matchedBarcode != null) {
                    finishWithPayload(
                        hashMapOf(
                            "type" to "barcode",
                            "rawValue" to matchedBarcode.rawValue,
                            "format" to mapMlKitFormat(matchedBarcode.format),
                            "errorCode" to null,
                            "errorMessage" to null,
                        ),
                    )
                }
            }
            .addOnCompleteListener {
                isAnalyzerBusy = false
                imageProxy.close()
            }
    }

    private fun isBarcodeInsideOverlay(
        barcode: Barcode,
        overlayRect: RectF,
        coordinateTransform: CoordinateTransform?,
    ): Boolean {
        if (coordinateTransform == null || overlayRect.isEmpty) {
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

    private fun buildContentView(): View {
        val foregroundColor = config.resolveAppBarForeground() ?: Color.WHITE
        val backgroundColor =
            config.resolveAppBarBackground()
                ?: config.resolveStatusBarBackground()
                ?: "#0A1C58".toColorInt()

        val root = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            layoutDirection = View.LAYOUT_DIRECTION_LTR
        }

        previewView = PreviewView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            scaleType = PreviewView.ScaleType.FILL_CENTER
            addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                refreshCachedPreviewData()
            }
        }
        root.addView(previewView)

        overlayView = ScanWindowOverlayView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            setMaskColor(config.overlayColor)
            setBorderColor(Color.WHITE)
            setBorderStrokeWidth(dp(3))
            setBorderLineLength(dp(26))
            setBorderCornerRadius(config.scanWindowCornerRadius.toInt())
            applyWindowConfig(
                widthFactor = config.scanWindowWidthFactor,
                heightFactor = config.scanWindowHeightFactor,
                cornerRadius = config.scanWindowCornerRadius,
            )
            addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                refreshCachedPreviewData()
            }
            visibility = if (config.scanWindowEnabled) View.VISIBLE else View.GONE
        }
        root.addView(overlayView)

        val topInset = getStatusBarInset()
        root.addView(
            View(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    topInset,
                    Gravity.TOP,
                )
                setBackgroundColor(
                    if (config.statusBarTransparent) {
                        Color.TRANSPARENT
                    } else {
                        backgroundColor
                    },
                )
            },
        )

        val topBar = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dp(56),
                Gravity.TOP,
            ).apply {
                topMargin = topInset
            }
            if (config.textDirection == "rtl") {
                layoutDirection = View.LAYOUT_DIRECTION_RTL
            }
            setBackgroundColor(if (config.appBarTransparent) Color.TRANSPARENT else backgroundColor)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            elevation = if (config.appBarTransparent) 0f else dp(3).toFloat()
        }

        val closeButton = createIconButton(
            iconRes = R.drawable.ic_scanner_close,
            tintColor = foregroundColor,
            contentDescription = config.strings.close,
            overlayStyle = false,
        ).apply {
            setOnClickListener { finishWithPayload(ScannerActivityContract.cancelledResult()) }
        }
        topBar.addView(
            closeButton,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_VERTICAL or Gravity.START,
            ),
        )

        val titleView = TextView(this).apply {
            text = config.strings.title
            setTextColor(foregroundColor)
            textSize = 20f
            gravity = Gravity.CENTER
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.END
        }
        topBar.addView(
            titleView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ).apply {
                marginStart = dp(56)
                marginEnd = dp(56)
            },
        )

        flashButton = createIconButton(
            iconRes = R.drawable.ic_scanner_flash_on,
            tintColor = foregroundColor,
            contentDescription = config.strings.flashOn,
            overlayStyle = true,
        ).apply {
            setOnClickListener {
                isFlashEnabled = !isFlashEnabled
                camera?.cameraControl?.enableTorch(isFlashEnabled)
                updateFlashButtonUi()
            }
        }
        switchCameraButton = createIconButton(
            iconRes = R.drawable.ic_scanner_switch_camera,
            tintColor = foregroundColor,
            contentDescription = config.strings.switchCamera,
            overlayStyle = true,
        ).apply {
            setOnClickListener { toggleCamera() }
        }

        if (config.showFlashButton) {
            root.addView(
                flashButton,
                FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply {
                    topMargin = topInset + dp(72)
                    marginStart = dp(16)
                },
            )
        }
        if (config.showCameraSwitchButton && hasFrontAndBackCameras()) {
            root.addView(
                switchCameraButton,
                FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).apply {
                    topMargin = topInset + dp(72)
                    marginEnd = dp(16)
                },
            )
        }

        root.addView(topBar)
        updateFlashButtonUi()
        return root
    }

    private fun toggleCamera() {
        lensFacing =
            if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                CameraSelector.LENS_FACING_BACK
            } else {
                CameraSelector.LENS_FACING_FRONT
            }
        bindCamera()
    }

    private fun updateFlashButtonUi() {
        if (::flashButton.isInitialized) {
            flashButton.alpha = if (isFlashEnabled) 1f else 0.84f
            flashButton.setImageResource(
                if (isFlashEnabled) {
                    R.drawable.ic_scanner_flash_off
                } else {
                    R.drawable.ic_scanner_flash_on
                },
            )
            flashButton.contentDescription =
                if (isFlashEnabled) config.strings.flashOff else config.strings.flashOn
        }
    }

    private fun createIconButton(
        iconRes: Int,
        tintColor: Int,
        contentDescription: String,
        overlayStyle: Boolean,
    ): ImageButton {
        return ImageButton(this).apply {
            setImageResource(iconRes)
            imageTintList = android.content.res.ColorStateList.valueOf(tintColor)
            this.contentDescription = contentDescription
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            if (overlayStyle) {
                background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(Color.parseColor("#66000000"))
                }
                setPadding(dp(10), dp(10), dp(10), dp(10))
            } else {
                background = null
            }
        }
    }

    private fun finishWithPayload(payload: HashMap<String, Any?>) {
        if (hasReturnedResult) {
            return
        }
        hasReturnedResult = true
        val intent = Intent().apply {
            putExtra(ScannerActivityContract.EXTRA_RESULT, payload)
        }
        setResult(RESULT_OK, intent)
        finish()
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
            else -> "QR_CODE"
        }
    }

    private fun applyWindowStyle() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.isAppearanceLightStatusBars = config.statusBarIconBrightness == "dark"
        if (config.statusBarTransparent) {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            window.statusBarColor = Color.TRANSPARENT
        } else {
            WindowCompat.setDecorFitsSystemWindows(window, true)
            window.statusBarColor =
                config.resolveStatusBarBackground()
                    ?: config.resolveAppBarBackground()
                    ?: "#0A1C58".toColorInt()
        }
    }

    private fun getStatusBarInset(): Int {
        val rootInsets = window.decorView.rootWindowInsets
        val inset =
            if (rootInsets != null) {
                WindowInsetsCompat.toWindowInsetsCompat(rootInsets)
                    .getInsets(WindowInsetsCompat.Type.statusBars()).top
            } else {
                0
            }
        if (inset > 0) {
            return inset
        }
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else dp(24)
    }

    private fun resolveCurrentOrientation(): Int {
        val rotation = (getSystemService(Context.WINDOW_SERVICE) as WindowManager)
            .defaultDisplay.rotation
        return when (rotation) {
            Surface.ROTATION_0 -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            Surface.ROTATION_90 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            Surface.ROTATION_180 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
            else -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
        }
    }

    private fun hasFrontAndBackCameras(): Boolean {
        return packageManager.hasSystemFeature("android.hardware.camera.front") &&
            packageManager.hasSystemFeature("android.hardware.camera")
    }

    private fun refreshCachedPreviewData() {
        val outputTransform = previewView.outputTransform ?: return
        val overlayRect = overlayView.getFramingRectF()
        if (!config.scanWindowEnabled) {
            synchronized(transformLock) {
                cachedPreviewTransform = outputTransform
                cachedOverlayRect = RectF()
            }
            return
        }
        if (overlayRect.isEmpty) {
            return
        }
        synchronized(transformLock) {
            cachedPreviewTransform = outputTransform
            cachedOverlayRect = RectF(overlayRect)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
