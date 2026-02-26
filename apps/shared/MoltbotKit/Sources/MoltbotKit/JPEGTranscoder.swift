import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG转码错误枚举，定义了转码过程中可能出现的各种错误
public enum JPEGTranscodeError: LocalizedError, Sendable {
    case decodeFailed          // 解码失败
    case propertiesMissing     // 缺少图像属性
    case encodeFailed          // 编码失败
    case sizeLimitExceeded(maxBytes: Int, actualBytes: Int)  // 超出大小限制

    /// 错误描述
    public var errorDescription: String? {
        switch self {
        case .decodeFailed:
            "图像数据解码失败"
        case .propertiesMissing:
            "读取图像属性失败"
        case .encodeFailed:
            "JPEG编码失败"
        case let .sizeLimitExceeded(maxBytes, actualBytes):
            "JPEG超出大小限制 (\(actualBytes) 字节 > \(maxBytes) 字节)"
        }
    }
}

/// JPEG转码器，用于将图像数据重新编码为JPEG格式，支持调整大小和质量
public struct JPEGTranscoder: Sendable {
    /// 限制质量值在有效范围内
    /// - Parameter quality: 输入的质量值
    /// - Returns: 限制在0.05到1.0之间的质量值
    public static func clampQuality(_ quality: Double) -> Double {
        min(1.0, max(0.05, quality))
    }

    /// 将图像数据重新编码为JPEG，可选择缩小尺寸以确保*定向*像素宽度 <= `maxWidthPx`
    ///
    /// - 重要: 此方法会标准化EXIF方向（输出像素会根据需要旋转；不依赖方向标签）
    ///
    /// - Parameters:
    ///   - imageData: 原始图像数据
    ///   - maxWidthPx: 最大宽度（像素），为nil时不限制
    ///   - quality: 编码质量，范围0.0到1.0
    ///   - maxBytes: 最大输出字节数，为nil时不限制
    /// - Returns: 包含转码后数据、宽度和高度的元组
    /// - Throws: JPEGTranscodeError类型的错误
    public static func transcodeToJPEG(
        imageData: Data,
        maxWidthPx: Int?,
        quality: Double,
        maxBytes: Int? = nil) throws -> (data: Data, widthPx: Int, heightPx: Int)
    {
        // 创建图像源
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw JPEGTranscodeError.decodeFailed
        }
        
        // 读取图像属性
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let rawWidth = props[kCGImagePropertyPixelWidth] as? NSNumber,
            let rawHeight = props[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw JPEGTranscodeError.propertiesMissing
        }

        let pixelWidth = rawWidth.intValue
        let pixelHeight = rawHeight.intValue
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1

        // 验证图像尺寸
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw JPEGTranscodeError.propertiesMissing
        }

        // 根据方向计算实际显示的宽度和高度
        let rotates90 = orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8
        let orientedWidth = rotates90 ? pixelHeight : pixelWidth
        let orientedHeight = rotates90 ? pixelWidth : pixelHeight

        // 计算最大维度
        let maxDim = max(orientedWidth, orientedHeight)
        
        // 计算目标最大像素尺寸
        var targetMaxPixelSize: Int = {
            guard let maxWidthPx, maxWidthPx > 0 else { return maxDim }
            guard orientedWidth > maxWidthPx else { return maxDim } // 从不放大

            let scale = Double(maxWidthPx) / Double(orientedWidth)
            return max(1, Int((Double(maxDim) * scale).rounded(.toNearestOrAwayFromZero)))
        }()

        /// 编码图像的内部函数
        /// - Parameters:
        ///   - maxPixelSize: 最大像素尺寸
        ///   - quality: 编码质量
        /// - Returns: 包含编码后数据、宽度和高度的元组
        /// - Throws: JPEGTranscodeError类型的错误
        func encode(maxPixelSize: Int, quality: Double) throws -> (data: Data, widthPx: Int, heightPx: Int) {
            // 缩略图选项
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,         // 始终创建缩略图
                kCGImageSourceCreateThumbnailWithTransform: true,          // 应用变换（包括方向）
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,         // 最大像素尺寸
                kCGImageSourceShouldCacheImmediately: true,                // 立即缓存
            ]

            // 创建缩略图
            guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
                throw JPEGTranscodeError.decodeFailed
            }

            // 准备输出数据
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw JPEGTranscodeError.encodeFailed
            }
            
            // 限制质量值并编码
            let q = self.clampQuality(quality)
            let encodeProps = [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary
            CGImageDestinationAddImage(dest, img, encodeProps)
            guard CGImageDestinationFinalize(dest) else {
                throw JPEGTranscodeError.encodeFailed
            }

            return (out as Data, img.width, img.height)
        }

        // 如果没有设置最大字节数限制，直接编码并返回
        guard let maxBytes, maxBytes > 0 else {
            return try encode(maxPixelSize: targetMaxPixelSize, quality: quality)
        }

        // 设置质量和尺寸的最小值
        let minQuality = max(0.2, self.clampQuality(quality) * 0.35)
        let minPixelSize = 256
        
        // 首先尝试使用指定的质量和尺寸进行编码
        var best = try encode(maxPixelSize: targetMaxPixelSize, quality: quality)
        if best.data.count <= maxBytes {
            return best
        }

        // 尝试降低质量和尺寸以满足大小限制
        // 最多尝试6次尺寸调整
        for _ in 0..<6 {
            var q = self.clampQuality(quality)
            // 每次尺寸调整后，最多尝试6次质量调整
            for _ in 0..<6 {
                let candidate = try encode(maxPixelSize: targetMaxPixelSize, quality: q)
                best = candidate
                if candidate.data.count <= maxBytes {
                    return candidate
                }
                if q <= minQuality { break }
                q = max(minQuality, q * 0.75)  // 每次降低25%的质量
            }

            // 计算下一个尺寸（缩小15%）
            let nextPixelSize = max(Int(Double(targetMaxPixelSize) * 0.85), minPixelSize)
            if nextPixelSize == targetMaxPixelSize {
                break  // 已达到最小尺寸，退出循环
            }
            targetMaxPixelSize = nextPixelSize
        }

        // 检查最终结果是否满足大小限制
        if best.data.count > maxBytes {
            throw JPEGTranscodeError.sizeLimitExceeded(maxBytes: maxBytes, actualBytes: best.data.count)
        }

        return best
    }
}
