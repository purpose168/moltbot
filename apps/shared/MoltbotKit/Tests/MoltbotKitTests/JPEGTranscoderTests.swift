import MoltbotKit
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers

/// JPEG转码器测试套件
@Suite struct JPEGTranscoderTests {
    /// 创建一个纯色JPEG图像
    /// - Parameters:
    ///   - width: 图像宽度
    ///   - height: 图像高度
    ///   - orientation: 图像方向（可选）
    /// - Returns: JPEG图像数据
    private func makeSolidJPEG(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        // 创建RGB颜色空间
        let cs = CGColorSpaceCreateDeviceRGB()
        // 设置位图信息，使用预乘Alpha通道
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: bitmapInfo)
        else {
            throw NSError(domain: "JPEGTranscoderTests", code: 1)
        }

        // 设置填充颜色为红色
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        // 填充整个画布
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // 创建CGImage
        guard let img = ctx.makeImage() else {
            throw NSError(domain: "JPEGTranscoderTests", code: 5)
        }

        // 准备输出数据
        let out = NSMutableData()
        // 创建JPEG图像目标
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "JPEGTranscoderTests", code: 2)
        }

        // 设置JPEG编码属性
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0, // 最高质量
        ]
        // 如果指定了方向，添加方向属性
        if let orientation {
            props[kCGImagePropertyOrientation] = orientation
        }

        // 添加图像到目标并编码
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "JPEGTranscoderTests", code: 3)
        }

        return out as Data
    }

    /// 创建一个包含随机噪声的JPEG图像
    /// - Parameters:
    ///   - width: 图像宽度
    ///   - height: 图像高度
    /// - Returns: JPEG图像数据
    private func makeNoiseJPEG(width: Int, height: Int) throws -> Data {
        // 每个像素4字节（RGBA）
        let bytesPerPixel = 4
        let byteCount = width * height * bytesPerPixel
        // 创建指定大小的数据
        var data = Data(count: byteCount)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // 填充随机噪声数据并编码为JPEG
        let out = try data.withUnsafeMutableBytes { rawBuffer -> Data in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw NSError(domain: "JPEGTranscoderTests", code: 6)
            }
            // 为每个字节生成随机值
            for idx in 0..<byteCount {
                base[idx] = UInt8.random(in: 0...255)
            }

            // 创建CGContext
            guard
                let ctx = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * bytesPerPixel,
                    space: cs,
                    bitmapInfo: bitmapInfo)
            else {
                throw NSError(domain: "JPEGTranscoderTests", code: 7)
            }

            // 创建CGImage
            guard let img = ctx.makeImage() else {
                throw NSError(domain: "JPEGTranscoderTests", code: 8)
            }

            // 编码为JPEG
            let encoded = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil)
            else {
                throw NSError(domain: "JPEGTranscoderTests", code: 9)
            }
            CGImageDestinationAddImage(dest, img, nil)
            guard CGImageDestinationFinalize(dest) else {
                throw NSError(domain: "JPEGTranscoderTests", code: 10)
            }
            return encoded as Data
        }

        return out
    }

    /// 测试缩放到最大宽度
    @Test func downscalesToMaxWidthPx() throws {
        // 创建2000x1000的红色JPEG图像
        let input = try makeSolidJPEG(width: 2000, height: 1000)
        // 转码到最大宽度1600，质量0.9
        let out = try JPEGTranscoder.transcodeToJPEG(imageData: input, maxWidthPx: 1600, quality: 0.9)
        // 验证输出宽度为1600
        #expect(out.widthPx == 1600)
        // 验证输出高度约为800（允许1像素误差）
        #expect(abs(out.heightPx - 800) <= 1)
        // 验证输出数据不为空
        #expect(out.data.count > 0)
    }

    /// 测试当图像小于最大宽度时不进行放大
    @Test func doesNotUpscaleWhenSmallerThanMaxWidthPx() throws {
        // 创建800x600的红色JPEG图像
        let input = try makeSolidJPEG(width: 800, height: 600)
        // 尝试转码到最大宽度1600，质量0.9
        let out = try JPEGTranscoder.transcodeToJPEG(imageData: input, maxWidthPx: 1600, quality: 0.9)
        // 验证输出宽度保持800
        #expect(out.widthPx == 800)
        // 验证输出高度保持600
        #expect(out.heightPx == 600)
    }

    /// 测试标准化方向并使用定向宽度作为最大宽度参考
    @Test func normalizesOrientationAndUsesOrientedWidthForMaxWidthPx() throws {
        // 编码一个横向图像，但标记为旋转90度（方向6）。定向宽度变为1000。
        let input = try makeSolidJPEG(width: 2000, height: 1000, orientation: 6)
        // 转码到最大宽度1600，质量0.9
        let out = try JPEGTranscoder.transcodeToJPEG(imageData: input, maxWidthPx: 1600, quality: 0.9)
        // 验证输出宽度为1000
        #expect(out.widthPx == 1000)
        // 验证输出高度为2000
        #expect(out.heightPx == 2000)
    }

    /// 测试尊重最大字节数限制
    @Test func respectsMaxBytes() throws {
        // 创建1600x1200的噪声JPEG图像
        let input = try makeNoiseJPEG(width: 1600, height: 1200)
        // 转码并限制最大字节数为180,000
        let out = try JPEGTranscoder.transcodeToJPEG(
            imageData: input,
            maxWidthPx: 1600,
            quality: 0.95,
            maxBytes: 180_000)
        // 验证输出数据大小不超过180,000字节
        #expect(out.data.count <= 180_000)
    }
}
