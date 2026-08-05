package com.eventer.flutter_barcode_scanner_sdk

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

class ScanWindowOverlayView(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {
    private var framingRect: Rect = Rect()
    private var config: ScannerConfig? = null
    private var cornerRadius: Float = 18f
    private var maskColor: Int = android.graphics.Color.parseColor("#99000000")
    private var borderColor: Int = android.graphics.Color.WHITE
    private var borderStrokeWidth: Int = (3 * resources.displayMetrics.density).toInt()
    private var borderLineLength: Int = (26 * resources.displayMetrics.density).toInt()
    private var borderAlpha: Float = 1f

    private val maskPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val clearPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.CLEAR)
    }

    /**
     * Adopts [config] as the source of the framing rect.
     *
     * The geometry lives in [ScannerConfig.scanWindowRect] so this view, the embedded view and
     * the Flutter overlay cannot drift apart — they did when each held its own copy of the rule.
     */
    fun applyWindowConfig(config: ScannerConfig) {
        this.config = config
        this.cornerRadius = config.scanWindowCornerRadius
        updateFramingRect()
        invalidate()
    }

    fun getFramingRectF(): RectF = RectF(framingRect)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (framingRect.isEmpty) {
            return
        }

        maskPaint.color = maskColor
        borderPaint.color = borderColor
        borderPaint.strokeWidth = borderStrokeWidth.toFloat()
        borderPaint.alpha = (255 * borderAlpha).toInt()

        val saveLayer = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), maskPaint)
        canvas.drawRoundRect(RectF(framingRect), cornerRadius, cornerRadius, clearPaint)
        canvas.restoreToCount(saveLayer)

        canvas.drawRoundRect(RectF(framingRect), cornerRadius, cornerRadius, borderPaint)
        drawCorners(canvas)
        if (config?.requiresCenterOnBarcode() == true) {
            drawCrosshair(canvas)
        }
    }

    /**
     * Marks the aim point under crosshair aiming.
     *
     * Without it the mode changes what gets scanned with nothing on screen to explain why a code
     * sitting inside the frame was ignored.
     */
    private fun drawCrosshair(canvas: Canvas) {
        val rect = RectF(framingRect)
        val arm = borderLineLength / 2f
        val gap = arm / 3f
        val x = rect.centerX()
        val y = rect.centerY()

        canvas.drawLine(x - arm, y, x - gap, y, borderPaint)
        canvas.drawLine(x + gap, y, x + arm, y, borderPaint)
        canvas.drawLine(x, y - arm, x, y - gap, borderPaint)
        canvas.drawLine(x, y + gap, x, y + arm, borderPaint)
    }

    private fun drawCorners(canvas: Canvas) {
        val rect = RectF(framingRect)
        val corner = borderLineLength.toFloat()
        val strokeHalf = borderStrokeWidth / 2f

        canvas.drawLine(rect.left - strokeHalf, rect.top + corner, rect.left - strokeHalf, rect.top, borderPaint)
        canvas.drawLine(rect.left, rect.top - strokeHalf, rect.left + corner, rect.top - strokeHalf, borderPaint)

        canvas.drawLine(rect.right + strokeHalf, rect.top + corner, rect.right + strokeHalf, rect.top, borderPaint)
        canvas.drawLine(rect.right - corner, rect.top - strokeHalf, rect.right, rect.top - strokeHalf, borderPaint)

        canvas.drawLine(rect.left - strokeHalf, rect.bottom - corner, rect.left - strokeHalf, rect.bottom, borderPaint)
        canvas.drawLine(rect.left, rect.bottom + strokeHalf, rect.left + corner, rect.bottom + strokeHalf, borderPaint)

        canvas.drawLine(rect.right + strokeHalf, rect.bottom - corner, rect.right + strokeHalf, rect.bottom, borderPaint)
        canvas.drawLine(rect.right - corner, rect.bottom + strokeHalf, rect.right, rect.bottom + strokeHalf, borderPaint)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateFramingRect()
    }

    fun setMaskColor(color: Int) {
        maskColor = color
        invalidate()
    }

    fun setBorderColor(color: Int) {
        borderColor = color
        invalidate()
    }

    fun setBorderStrokeWidth(width: Int) {
        borderStrokeWidth = width
        invalidate()
    }

    fun setBorderLineLength(length: Int) {
        borderLineLength = length
        invalidate()
    }

    fun setBorderAlpha(alpha: Float) {
        borderAlpha = alpha
        invalidate()
    }

    fun setBorderCornerRadius(radius: Int) {
        cornerRadius = radius.toFloat()
        invalidate()
    }

    fun updateFramingRect() {
        val activeConfig = config ?: return
        if (width == 0 || height == 0) {
            return
        }
        val rect = activeConfig.scanWindowRect(width, height)
        framingRect = Rect(
            rect.left.toInt(),
            rect.top.toInt(),
            rect.right.toInt(),
            rect.bottom.toInt(),
        )
        invalidate()
    }
}
