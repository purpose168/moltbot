import AVFoundation
import MoltbotIPC
import MoltbotKit
import CoreGraphics
import Foundation
import OSLog

/// 相机捕获服务，用于管理相机设备、拍摄照片和录制视频
actor CameraCaptureService {
    /// 相机设备信息结构体，用于编码和发送相机设备信息
    struct CameraDeviceInfo: Encodable, Sendable {
        let id: String        // 设备唯一标识符
        let name: String      // 设备本地化名称
        let position: String  // 设备位置（前置/后置）
        let deviceType: String // 设备类型
    }

    /// 相机错误枚举，定义了各种相机操作可能出现的错误
    enum CameraError: LocalizedError, Sendable {
        case cameraUnavailable       // 相机不可用
        case microphoneUnavailable   // 麦克风不可用
        case permissionDenied(kind: String) // 权限被拒绝
        case captureFailed(String)   // 捕获失败
        case exportFailed(String)    // 导出失败

        /// 错误描述
        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                "相机不可用"
            case .microphoneUnavailable:
                "麦克风不可用"
            case let .permissionDenied(kind):
                "\(kind) 权限被拒绝"
            case let .captureFailed(msg):
                msg
            case let .exportFailed(msg):
                msg
            }
        }
    }

    /// 日志记录器
    private let logger = Logger(subsystem: "bot.molt", category: "camera")

    /// 列出所有可用的相机设备
    /// - Returns: 相机设备信息数组
    func listDevices() -> [CameraDeviceInfo] {
        Self.availableCameras().map { device in
            CameraDeviceInfo(
                id: device.uniqueID,
                name: device.localizedName,
                position: Self.positionLabel(device.position),
                deviceType: device.deviceType.rawValue)
        }
    }

    /// 拍摄照片
    /// - Parameters:
    ///   - facing: 相机朝向（前置/后置）
    ///   - maxWidth: 最大宽度
    ///   - quality: 照片质量
    ///   - deviceId: 设备ID
    ///   - delayMs: 延迟时间（毫秒）
    /// - Returns: 包含照片数据和尺寸的元组
    func snap(
        facing: CameraFacing?,
        maxWidth: Int?,
        quality: Double?,
        deviceId: String?,
        delayMs: Int) async throws -> (data: Data, size: CGSize)
    {
        let facing = facing ?? .front
        let normalized = Self.normalizeSnap(maxWidth: maxWidth, quality: quality)
        let maxWidth = normalized.maxWidth
        let quality = normalized.quality
        let delayMs = max(0, delayMs)
        let deviceId = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines)

        // 确保有视频访问权限
        try await self.ensureAccess(for: .video)

        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // 选择相机设备
        guard let device = Self.pickCamera(facing: facing, deviceId: deviceId) else {
            throw CameraError.cameraUnavailable
        }

        // 添加相机输入
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.captureFailed("添加相机输入失败")
        }
        session.addInput(input)

        // 添加照片输出
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CameraError.captureFailed("添加照片输出失败")
        }
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality

        session.startRunning()
        defer { session.stopRunning() }
        await Self.warmUpCaptureSession()
        await self.waitForExposureAndWhiteBalance(device: device)
        await self.sleepDelayMs(delayMs)

        // 配置照片设置
        let settings: AVCapturePhotoSettings = {
            if output.availablePhotoCodecTypes.contains(.jpeg) {
                return AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            return AVCapturePhotoSettings()
        }()
        settings.photoQualityPrioritization = .quality

        // 捕获照片
        var delegate: PhotoCaptureDelegate?
        let rawData: Data = try await withCheckedThrowingContinuation { cont in
            let d = PhotoCaptureDelegate(cont)
            delegate = d
            output.capturePhoto(with: settings, delegate: d)
        }
        withExtendedLifetime(delegate) {}

        // 处理照片数据，确保大小不超过API限制
        let maxPayloadBytes = 5 * 1024 * 1024
        // Base64会使数据大小增加约4/3；限制编码后的字节数，确保 payload 不超过 5MB（API限制）
        let maxEncodedBytes = (maxPayloadBytes / 4) * 3
        let res = try JPEGTranscoder.transcodeToJPEG(
            imageData: rawData,
            maxWidthPx: maxWidth,
            quality: quality,
            maxBytes: maxEncodedBytes)
        return (data: res.data, size: CGSize(width: res.widthPx, height: res.heightPx))
    }

    /// 录制视频
    /// - Parameters:
    ///   - facing: 相机朝向（前置/后置）
    ///   - durationMs: 录制时长（毫秒）
    ///   - includeAudio: 是否包含音频
    ///   - deviceId: 设备ID
    ///   - outPath: 输出路径
    /// - Returns: 包含输出路径、录制时长和是否包含音频的元组
    func clip(
        facing: CameraFacing?,
        durationMs: Int?,
        includeAudio: Bool,
        deviceId: String?,
        outPath: String?) async throws -> (path: String, durationMs: Int, hasAudio: Bool)
    {
        let facing = facing ?? .front
        let durationMs = Self.clampDurationMs(durationMs)
        let deviceId = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines)

        // 确保有视频访问权限
        try await self.ensureAccess(for: .video)
        // 如果需要音频，确保有音频访问权限
        if includeAudio {
            try await self.ensureAccess(for: .audio)
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // 选择相机设备
        guard let camera = Self.pickCamera(facing: facing, deviceId: deviceId) else {
            throw CameraError.cameraUnavailable
        }
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else {
            throw CameraError.captureFailed("添加相机输入失败")
        }
        session.addInput(cameraInput)

        // 如果需要音频，添加麦克风输入
        if includeAudio {
            guard let mic = AVCaptureDevice.default(for: .audio) else {
                throw CameraError.microphoneUnavailable
            }
            let micInput = try AVCaptureDeviceInput(device: mic)
            guard session.canAddInput(micInput) else {
                throw CameraError.captureFailed("添加麦克风输入失败")
            }
            session.addInput(micInput)
        }

        // 添加视频输出
        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else {
            throw CameraError.captureFailed("添加视频输出失败")
        }
        session.addOutput(output)
        output.maxRecordedDuration = CMTime(value: Int64(durationMs), timescale: 1000)

        session.startRunning()
        defer { session.stopRunning() }
        await Self.warmUpCaptureSession()

        // 创建临时MOV文件
        let tmpMovURL = FileManager().temporaryDirectory
            .appendingPathComponent("moltbot-camera-\(UUID().uuidString).mov")
        defer { try? FileManager().removeItem(at: tmpMovURL) }

        // 确定输出URL
        let outputURL: URL = {
            if let outPath, !outPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return URL(fileURLWithPath: outPath)
            }
            return FileManager().temporaryDirectory
                .appendingPathComponent("moltbot-camera-\(UUID().uuidString).mp4")
        }()

        // 确保不会因为已有文件而导出失败
        try? FileManager().removeItem(at: outputURL)

        // 开始录制
        let logger = self.logger
        var delegate: MovieFileDelegate?
        let recordedURL: URL = try await withCheckedThrowingContinuation { cont in
            let d = MovieFileDelegate(cont, logger: logger)
            delegate = d
            output.startRecording(to: tmpMovURL, recordingDelegate: d)
        }
        withExtendedLifetime(delegate) {}

        // 导出为MP4格式
        try await Self.exportToMP4(inputURL: recordedURL, outputURL: outputURL)
        return (path: outputURL.path, durationMs: durationMs, hasAudio: includeAudio)
    }

    /// 确保有指定媒体类型的访问权限
    /// - Parameter mediaType: 媒体类型（视频/音频）
    private func ensureAccess(for mediaType: AVMediaType) async throws {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            // 请求访问权限
            let ok = await withCheckedContinuation(isolation: nil) { cont in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    cont.resume(returning: granted)
                }
            }
            if !ok {
                throw CameraError.permissionDenied(kind: mediaType == .video ? "相机" : "麦克风")
            }
        case .denied, .restricted:
            throw CameraError.permissionDenied(kind: mediaType == .video ? "相机" : "麦克风")
        @unknown default:
            throw CameraError.permissionDenied(kind: mediaType == .video ? "相机" : "麦克风")
        }
    }

    /// 获取所有可用的相机设备
    /// - Returns: 相机设备数组
    private nonisolated static func availableCameras() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .continuityCamera,
        ]
        if let external = externalDeviceType() {
            types.append(external)
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified)
        return session.devices
    }

    /// 获取外部设备类型
    /// - Returns: 外部设备类型
    private nonisolated static func externalDeviceType() -> AVCaptureDevice.DeviceType? {
        if #available(macOS 14.0, *) {
            return .external
        }
        // 使用原始值以避免SDK中的废弃符号
        return AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeExternalUnknown")
    }

    /// 选择相机设备
    /// - Parameters:
    ///   - facing: 相机朝向
    ///   - deviceId: 设备ID
    /// - Returns: 选中的相机设备
    private nonisolated static func pickCamera(
        facing: CameraFacing,
        deviceId: String?) -> AVCaptureDevice?
    {
        // 如果指定了设备ID，尝试找到匹配的设备
        if let deviceId, !deviceId.isEmpty {
            if let match = availableCameras().first(where: { $0.uniqueID == deviceId }) {
                return match
            }
        }
        // 根据朝向选择设备位置
        let position: AVCaptureDevice.Position = (facing == .front) ? .front : .back

        // 尝试获取指定位置的内置广角相机
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }

        // 许多macOS相机报告`unspecified`位置；回退到任何默认相机
        return AVCaptureDevice.default(for: .video)
    }

    /// 限制照片质量范围
    /// - Parameter quality: 照片质量
    /// - Returns: 限制后的照片质量
    private nonisolated static func clampQuality(_ quality: Double?) -> Double {
        let q = quality ?? 0.9
        return min(1.0, max(0.05, q))
    }

    /// 标准化照片拍摄参数
    /// - Parameters:
    ///   - maxWidth: 最大宽度
    ///   - quality: 照片质量
    /// - Returns: 标准化后的参数
    nonisolated static func normalizeSnap(maxWidth: Int?, quality: Double?) -> (maxWidth: Int, quality: Double) {
        // 默认使用合理的最大宽度，以保持下游payload大小可管理
        // 如果需要全分辨率，请显式请求更大的maxWidth
        let maxWidth = maxWidth.flatMap { $0 > 0 ? $0 : nil } ?? 1600
        let quality = Self.clampQuality(quality)
        return (maxWidth: maxWidth, quality: quality)
    }

    /// 限制录制时长范围
    /// - Parameter ms: 时长（毫秒）
    /// - Returns: 限制后的时长
    private nonisolated static func clampDurationMs(_ ms: Int?) -> Int {
        let v = ms ?? 3000
        return min(60000, max(250, v))
    }

    /// 导出为MP4格式
    /// - Parameters:
    ///   - inputURL: 输入URL
    ///   - outputURL: 输出URL
    private nonisolated static func exportToMP4(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw CameraError.exportFailed("创建导出会话失败")
        }
        export.shouldOptimizeForNetworkUse = true

        if #available(macOS 15.0, *) {
            do {
                try await export.export(to: outputURL, as: .mp4)
                return
            } catch {
                throw CameraError.exportFailed(error.localizedDescription)
            }
        } else {
            export.outputURL = outputURL
            export.outputFileType = .mp4

            try await withCheckedThrowingContinuation(isolation: nil) { (cont: CheckedContinuation<Void, Error>) in
                export.exportAsynchronously {
                    cont.resume(returning: ())
                }
            }

            switch export.status {
            case .completed:
                return
            case .failed:
                throw CameraError.exportFailed(export.error?.localizedDescription ?? "导出失败")
            case .cancelled:
                throw CameraError.exportFailed("导出取消")
            default:
                throw CameraError.exportFailed("导出未完成 (\(export.status.rawValue))")
            }
        }
    }

    /// 预热捕获会话
    /// 在`startRunning()`后短暂延迟可显著减少某些设备上的"空白第一帧"捕获问题
    private nonisolated static func warmUpCaptureSession() async {
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
    }

    /// 等待曝光和白平衡调整完成
    /// - Parameter device: 相机设备
    private func waitForExposureAndWhiteBalance(device: AVCaptureDevice) async {
        let stepNs: UInt64 = 50_000_000
        let maxSteps = 30 // ~1.5s
        for _ in 0..<maxSteps {
            if !(device.isAdjustingExposure || device.isAdjustingWhiteBalance) {
                return
            }
            try? await Task.sleep(nanoseconds: stepNs)
        }
    }

    /// 延迟指定毫秒数
    /// - Parameter delayMs: 延迟时间（毫秒）
    private func sleepDelayMs(_ delayMs: Int) async {
        guard delayMs > 0 else { return }
        let ns = UInt64(min(delayMs, 10000)) * 1_000_000
        try? await Task.sleep(nanoseconds: ns)
    }

    /// 获取位置标签
    /// - Parameter position: 相机位置
    /// - Returns: 位置标签字符串
    private nonisolated static func positionLabel(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: "front"
        case .back: "back"
        default: "unspecified"
        }
    }
}

/// 照片捕获代理，处理照片捕获完成事件
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var cont: CheckedContinuation<Data, Error>?
    private var didResume = false

    init(_ cont: CheckedContinuation<Data, Error>) {
        self.cont = cont
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?)
    {
        guard !self.didResume, let cont else { return }
        self.didResume = true
        self.cont = nil
        if let error {
            cont.resume(throwing: error)
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            cont.resume(throwing: CameraCaptureService.CameraError.captureFailed("无照片数据"))
            return
        }
        if data.isEmpty {
            cont.resume(throwing: CameraCaptureService.CameraError.captureFailed("照片数据为空"))
            return
        }
        cont.resume(returning: data)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?)
    {
        guard let error else { return }
        guard !self.didResume, let cont else { return }
        self.didResume = true
        self.cont = nil
        cont.resume(throwing: error)
    }
}

/// 视频文件代理，处理视频录制完成事件
private final class MovieFileDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private var cont: CheckedContinuation<URL, Error>?
    private let logger: Logger

    init(_ cont: CheckedContinuation<URL, Error>, logger: Logger) {
        self.cont = cont
        self.logger = logger
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?)
    {
        guard let cont else { return }
        self.cont = nil

        if let error {
            let ns = error as NSError
            if ns.domain == AVFoundationErrorDomain,
               ns.code == AVError.maximumDurationReached.rawValue
            {
                // 达到最大录制时长，这是预期的，不是错误
                cont.resume(returning: outputFileURL)
                return
            }

            self.logger.error("相机录制失败: \(error.localizedDescription, privacy: .public)")
            cont.resume(throwing: error)
            return
        }

        cont.resume(returning: outputFileURL)
    }
}
