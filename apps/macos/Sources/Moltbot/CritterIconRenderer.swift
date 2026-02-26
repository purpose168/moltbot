import AppKit

/// 小动物图标渲染器
/// 
/// 用于生成和渲染应用中的小动物图标
enum CritterIconRenderer {
    /// 图标大小
    private static let size = NSSize(width: 18, height: 18)

    /// 徽章结构
    /// 
    /// 表示图标的徽章
    struct Badge {
        /// 符号名称
        let symbolName: String
        /// 徽章突出度
        let prominence: IconState.BadgeProminence
    }

    /// 画布结构
    /// 
    /// 表示绘制图标时使用的画布
    private struct Canvas {
        /// 宽度
        let w: CGFloat
        /// 高度
        let h: CGFloat
        /// X轴步长
        let stepX: CGFloat
        /// Y轴步长
        let stepY: CGFloat
        /// X轴对齐函数
        let snapX: (CGFloat) -> CGFloat
        /// Y轴对齐函数
        let snapY: (CGFloat) -> CGFloat
        /// 上下文
        let context: CGContext
    }

    /// 几何结构
    /// 
    /// 表示图标的几何形状参数
    private struct Geometry {
        /// 身体矩形
        let bodyRect: CGRect
        /// 身体圆角
        let bodyCorner: CGFloat
        /// 左耳矩形
        let leftEarRect: CGRect
        /// 右耳矩形
        let rightEarRect: CGRect
        /// 耳朵圆角
        let earCorner: CGFloat
        /// 耳朵宽度
        let earW: CGFloat
        /// 耳朵高度
        let earH: CGFloat
        /// 腿宽度
        let legW: CGFloat
        /// 腿高度
        let legH: CGFloat
        /// 腿间距
        let legSpacing: CGFloat
        /// 腿起始X坐标
        let legStartX: CGFloat
        /// 腿Y基准
        let legYBase: CGFloat
        /// 腿抬起高度
        let legLift: CGFloat
        /// 腿高度缩放
        let legHeightScale: CGFloat
        /// 眼睛宽度
        let eyeW: CGFloat
        /// 眼睛Y坐标
        let eyeY: CGFloat
        /// 眼睛偏移
        let eyeOffset: CGFloat

        /// 初始化几何结构
        /// - Parameters:
        ///   - canvas: 画布
        ///   - legWiggle: 腿摆动幅度
        ///   - earWiggle: 耳朵摆动幅度
        ///   - earScale: 耳朵缩放比例
        init(canvas: Canvas, legWiggle: CGFloat, earWiggle: CGFloat, earScale: CGFloat) {
            let w = canvas.w
            let h = canvas.h
            let snapX = canvas.snapX
            let snapY = canvas.snapY

            let bodyW = snapX(w * 0.78)
            let bodyH = snapY(h * 0.58)
            let bodyX = snapX((w - bodyW) / 2)
            let bodyY = snapY(h * 0.36)
            let bodyCorner = snapX(w * 0.09)

            let earW = snapX(w * 0.22)
            let earH = snapY(bodyH * 0.54 * earScale * (1 - 0.08 * abs(earWiggle)))
            let earCorner = snapX(earW * 0.24)
            let leftEarRect = CGRect(
                x: snapX(bodyX - earW * 0.55 + earWiggle),
                y: snapY(bodyY + bodyH * 0.08 + earWiggle * 0.4),
                width: earW,
                height: earH)
            let rightEarRect = CGRect(
                x: snapX(bodyX + bodyW - earW * 0.45 - earWiggle),
                y: snapY(bodyY + bodyH * 0.08 - earWiggle * 0.4),
                width: earW,
                height: earH)

            let legW = snapX(w * 0.11)
            let legH = snapY(h * 0.26)
            let legSpacing = snapX(w * 0.085)
            let legsWidth = snapX(4 * legW + 3 * legSpacing)
            let legStartX = snapX((w - legsWidth) / 2)
            let legLift = snapY(legH * 0.35 * legWiggle)
            let legYBase = snapY(bodyY - legH + h * 0.05)
            let legHeightScale = 1 - 0.12 * legWiggle

            let eyeW = snapX(bodyW * 0.2)
            let eyeY = snapY(bodyY + bodyH * 0.56)
            let eyeOffset = snapX(bodyW * 0.24)

            self.bodyRect = CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH)
            self.bodyCorner = bodyCorner
            self.leftEarRect = leftEarRect
            self.rightEarRect = rightEarRect
            self.earCorner = earCorner
            self.earW = earW
            self.earH = earH
            self.legW = legW
            self.legH = legH
            self.legSpacing = legSpacing
            self.legStartX = legStartX
            self.legYBase = legYBase
            self.legLift = legLift
            self.legHeightScale = legHeightScale
            self.eyeW = eyeW
            self.eyeY = eyeY
            self.eyeOffset = eyeOffset
        }
    }

    /// 面部选项结构
    /// 
    /// 表示图标的面部选项
    private struct FaceOptions {
        /// 眨眼程度
        let blink: CGFloat
        /// 是否显示耳洞
        let earHoles: Bool
        /// 耳朵缩放比例
        let earScale: CGFloat
        /// 是否显示闭眼线条
        let eyesClosedLines: Bool
    }

    /// 生成图标
    /// - Parameters:
    ///   - blink: 眨眼程度
    ///   - legWiggle: 腿摆动幅度，默认为0
    ///   - earWiggle: 耳朵摆动幅度，默认为0
    ///   - earScale: 耳朵缩放比例，默认为1
    ///   - earHoles: 是否显示耳洞，默认为false
    ///   - eyesClosedLines: 是否显示闭眼线条，默认为false
    ///   - badge: 徽章，默认为nil
    /// - Returns: 生成的图标
    static func makeIcon(
        blink: CGFloat,
        legWiggle: CGFloat = 0,
        earWiggle: CGFloat = 0,
        earScale: CGFloat = 1,
        earHoles: Bool = false,
        eyesClosedLines: Bool = false,
        badge: Badge? = nil) -> NSImage
    {
        guard let rep = self.makeBitmapRep() else {
            return NSImage(size: self.size)
        }
        rep.size = self.size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: self.size)
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        context.cgContext.setShouldAntialias(false)

        let canvas = self.makeCanvas(for: rep, context: context)
        let geometry = Geometry(canvas: canvas, legWiggle: legWiggle, earWiggle: earWiggle, earScale: earScale)

        self.drawBody(in: canvas, geometry: geometry)
        let face = FaceOptions(
            blink: blink,
            earHoles: earHoles,
            earScale: earScale,
            eyesClosedLines: eyesClosedLines)
        self.drawFace(in: canvas, geometry: geometry, options: face)

        if let badge {
            self.drawBadge(badge, canvas: canvas)
        }

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    /// 创建位图表示
    /// - Returns: 位图表示
    private static func makeBitmapRep() -> NSBitmapImageRep? {
        // 强制使用36×36px的后备存储（18pt逻辑画布的2倍），使菜单栏图标在Retina上保持清晰。
        let pixelsWide = 36
        let pixelsHigh = 36
        return NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0)
    }

    /// 创建画布
    /// - Parameters:
    ///   - rep: 位图表示
    ///   - context: 图形上下文
    /// - Returns: 画布
    private static func makeCanvas(for rep: NSBitmapImageRep, context: NSGraphicsContext) -> Canvas {
        let stepX = self.size.width / max(CGFloat(rep.pixelsWide), 1)
        let stepY = self.size.height / max(CGFloat(rep.pixelsHigh), 1)
        let snapX: (CGFloat) -> CGFloat = { ($0 / stepX).rounded() * stepX }
        let snapY: (CGFloat) -> CGFloat = { ($0 / stepY).rounded() * stepY }

        let w = snapX(size.width)
        let h = snapY(size.height)

        return Canvas(
            w: w,
            h: h,
            stepX: stepX,
            stepY: stepY,
            snapX: snapX,
            snapY: snapY,
            context: context.cgContext)
    }

    /// 绘制身体
    /// - Parameters:
    ///   - canvas: 画布
    ///   - geometry: 几何形状
    private static func drawBody(in canvas: Canvas, geometry: Geometry) {
        canvas.context.setFillColor(NSColor.labelColor.cgColor)

        canvas.context.addPath(CGPath(
            roundedRect: geometry.bodyRect,
            cornerWidth: geometry.bodyCorner,
            cornerHeight: geometry.bodyCorner,
            transform: nil))
        canvas.context.addPath(CGPath(
            roundedRect: geometry.leftEarRect,
            cornerWidth: geometry.earCorner,
            cornerHeight: geometry.earCorner,
            transform: nil))
        canvas.context.addPath(CGPath(
            roundedRect: geometry.rightEarRect,
            cornerWidth: geometry.earCorner,
            cornerHeight: geometry.earCorner,
            transform: nil))

        for i in 0..<4 {
            let x = geometry.legStartX + CGFloat(i) * (geometry.legW + geometry.legSpacing)
            let lift = i % 2 == 0 ? geometry.legLift : -geometry.legLift
            let rect = CGRect(
                x: x,
                y: geometry.legYBase + lift,
                width: geometry.legW,
                height: geometry.legH * geometry.legHeightScale)
            canvas.context.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: geometry.legW * 0.34,
                cornerHeight: geometry.legW * 0.34,
                transform: nil))
        }
        canvas.context.fillPath()
    }

    /// 绘制面部
    /// - Parameters:
    ///   - canvas: 画布
    ///   - geometry: 几何形状
    ///   - options: 面部选项
    private static func drawFace(
        in canvas: Canvas,
        geometry: Geometry,
        options: FaceOptions)
    {
        canvas.context.saveGState()
        canvas.context.setBlendMode(.clear)

        let leftCenter = CGPoint(
            x: canvas.snapX(canvas.w / 2 - geometry.eyeOffset),
            y: canvas.snapY(geometry.eyeY))
        let rightCenter = CGPoint(
            x: canvas.snapX(canvas.w / 2 + geometry.eyeOffset),
            y: canvas.snapY(geometry.eyeY))

        if options.earHoles || options.earScale > 1.05 {
            let holeW = canvas.snapX(geometry.earW * 0.6)
            let holeH = canvas.snapY(geometry.earH * 0.46)
            let holeCorner = canvas.snapX(holeW * 0.34)
            let leftHoleRect = CGRect(
                x: canvas.snapX(geometry.leftEarRect.midX - holeW / 2),
                y: canvas.snapY(geometry.leftEarRect.midY - holeH / 2 + geometry.earH * 0.04),
                width: holeW,
                height: holeH)
            let rightHoleRect = CGRect(
                x: canvas.snapX(geometry.rightEarRect.midX - holeW / 2),
                y: canvas.snapY(geometry.rightEarRect.midY - holeH / 2 + geometry.earH * 0.04),
                width: holeW,
                height: holeH)

            canvas.context.addPath(CGPath(
                roundedRect: leftHoleRect,
                cornerWidth: holeCorner,
                cornerHeight: holeCorner,
                transform: nil))
            canvas.context.addPath(CGPath(
                roundedRect: rightHoleRect,
                cornerWidth: holeCorner,
                cornerHeight: holeCorner,
                transform: nil))
        }

        if options.eyesClosedLines {
            let lineW = canvas.snapX(geometry.eyeW * 0.95)
            let lineH = canvas.snapY(max(canvas.stepY * 2, geometry.bodyRect.height * 0.06))
            let corner = canvas.snapX(lineH * 0.6)
            let leftRect = CGRect(
                x: canvas.snapX(leftCenter.x - lineW / 2),
                y: canvas.snapY(leftCenter.y - lineH / 2),
                width: lineW,
                height: lineH)
            let rightRect = CGRect(
                x: canvas.snapX(rightCenter.x - lineW / 2),
                y: canvas.snapY(rightCenter.y - lineH / 2),
                width: lineW,
                height: lineH)
            canvas.context.addPath(CGPath(
                roundedRect: leftRect,
                cornerWidth: corner,
                cornerHeight: corner,
                transform: nil))
            canvas.context.addPath(CGPath(
                roundedRect: rightRect,
                cornerWidth: corner,
                cornerHeight: corner,
                transform: nil))
        } else {
            let eyeOpen = max(0.05, 1 - options.blink)
            let eyeH = canvas.snapY(geometry.bodyRect.height * 0.26 * eyeOpen)

            let left = CGMutablePath()
            left.move(to: CGPoint(
                x: canvas.snapX(leftCenter.x - geometry.eyeW / 2),
                y: canvas.snapY(leftCenter.y - eyeH)))
            left.addLine(to: CGPoint(
                x: canvas.snapX(leftCenter.x + geometry.eyeW / 2),
                y: canvas.snapY(leftCenter.y)))
            left.addLine(to: CGPoint(
                x: canvas.snapX(leftCenter.x - geometry.eyeW / 2),
                y: canvas.snapY(leftCenter.y + eyeH)))
            left.closeSubpath()

            let right = CGMutablePath()
            right.move(to: CGPoint(
                x: canvas.snapX(rightCenter.x + geometry.eyeW / 2),
                y: canvas.snapY(rightCenter.y - eyeH)))
            right.addLine(to: CGPoint(
                x: canvas.snapX(rightCenter.x - geometry.eyeW / 2),
                y: canvas.snapY(rightCenter.y)))
            right.addLine(to: CGPoint(
                x: canvas.snapX(rightCenter.x + geometry.eyeW / 2),
                y: canvas.snapY(rightCenter.y + eyeH)))
            right.closeSubpath()

            canvas.context.addPath(left)
            canvas.context.addPath(right)
        }

        canvas.context.fillPath()
        canvas.context.restoreGState()
    }

    /// 绘制徽章
    /// - Parameters:
    ///   - badge: 徽章
    ///   - canvas: 画布
    private static func drawBadge(_ badge: Badge, canvas: Canvas) {
        let strength: CGFloat = switch badge.prominence {
        case .primary: 1.0
        case .secondary: 0.58
        case .overridden: 0.85
        }

        // 更大、对比度更高的徽章：
        // - 增加直径，使工具活动更加明显。
        // - 绘制一个填充的"圆盘"，然后挖出符号形状（透明孔）。
        //   这在模板渲染的菜单栏图标中比微小的单色符号可读性更好。
        let diameter = canvas.snapX(canvas.w * 0.52 * (0.92 + 0.08 * strength)) // 在18pt画布上约为9-10pt
        let margin = canvas.snapX(max(0.45, canvas.w * 0.03))
        let rect = CGRect(
            x: canvas.snapX(canvas.w - diameter - margin),
            y: canvas.snapY(margin),
            width: diameter,
            height: diameter)

        canvas.context.saveGState()
        canvas.context.setShouldAntialias(true)

        // 清除底层像素，使徽章在小动物上方保持可读性。
        canvas.context.saveGState()
        canvas.context.setBlendMode(.clear)
        canvas.context.addEllipse(in: rect.insetBy(dx: -1.0, dy: -1.0))
        canvas.context.fillPath()
        canvas.context.restoreGState()

        let fillAlpha: CGFloat = min(1.0, 0.36 + 0.24 * strength)
        let strokeAlpha: CGFloat = min(1.0, 0.78 + 0.22 * strength)

        canvas.context.setFillColor(NSColor.labelColor.withAlphaComponent(fillAlpha).cgColor)
        canvas.context.addEllipse(in: rect)
        canvas.context.fillPath()

        canvas.context.setStrokeColor(NSColor.labelColor.withAlphaComponent(strokeAlpha).cgColor)
        canvas.context.setLineWidth(max(1.25, canvas.snapX(canvas.w * 0.075)))
        canvas.context.strokeEllipse(in: rect.insetBy(dx: 0.45, dy: 0.45))

        if let base = NSImage(systemSymbolName: badge.symbolName, accessibilityDescription: nil) {
            let pointSize = max(7.0, diameter * 0.82)
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .black)
            let symbol = base.withSymbolConfiguration(config) ?? base
            symbol.isTemplate = true

            let symbolRect = rect.insetBy(dx: diameter * 0.17, dy: diameter * 0.17)
            canvas.context.saveGState()
            canvas.context.setBlendMode(.clear)
            symbol.draw(
                in: symbolRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil)
            canvas.context.restoreGState()
        }

        canvas.context.restoreGState()
    }
}
