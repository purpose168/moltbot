import AVFoundation
import MoltbotKit
import Foundation

/// 相机控制器，用于管理相机操作
actor CameraController {
    /// 相机设备信息结构体
    struct CameraDeviceInfo: Codable, Sendable {
        var id: String              // 设备唯一标识符
        var name: String            // 设备名称
        var position: String        // 设备位置
        var deviceType: String      // 设备类型
    }

    /// 相机错误枚举
    enum CameraError: LocalizedError, Sendable {
        case cameraUnavailable       // 相机不可用
        case microphoneUnavailable   // 麦克风不可用
        case permissionDenied(kind: String) // 权限被拒绝
        case invalidParams(String)   // 参数无效
        case captureFailed(String)   // 捕获失败
        case exportFailed(String)    // 导出失败

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                "相机不可用"
            case .microphoneUnavailable:
                "麦克风不可用"
            case let .permissionDenied(kind):
                "\(kind) 权限被拒绝"
            case let .invalidParams(msg):
                msg
            case let .captureFailed(msg):
                msg
            case let .exportFailed(msg):
                msg
            }
        }
    }

    /// 拍摄照片
    /// - Parameter params: 拍摄参数
    /// - Returns: 包含格式、base64编码、宽度和高度的元组
    func snap(params: MoltbotCameraSnapParams) async throws -> (
        format: String,
        base64: String,
        width: Int,
        height: Int)
    {
        let facing = params.facing ?? .front    // 默认使用前置摄像头
        let format = params.format ?? .jpg      // 默认使用JPG格式
        // 默认设置合理的最大宽度，以保持网关有效负载大小可管理。
        // 如果需要全分辨率照片，请明确请求更大的maxWidth。
        let maxWidth = params.maxWidth.flatMap { $0 > 0 ? $0 : nil } ?? 1600
        let quality = Self.clampQuality(params.quality)  // 限制质量范围
        let delayMs = max(0, params.delayMs ?? 0)  // 延迟时间，确保非负

        // 确保有视频访问权限
        try await self.ensureAccess(for: .video)

        let session = AVCaptureSession()
        session.sessionPreset = .photo  // 设置为照片模式

        // 选择相机设备
        guard let device = Self.pickCamera(facing: facing, deviceId: params.deviceId) else {
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
        output.maxPhotoQualityPrioritization = .quality  // 优先考虑质量

        // 启动会话
        session.startRunning()
        defer { session.stopRunning() }  // 确保会话最终会停止
        await Self.warmUpCaptureSession()  // 预热捕获会话
        await Self.sleepDelayMs(delayMs)   // 应用延迟

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

        // 处理照片数据
        let maxPayloadBytes = 5 * 1024 * 1024
        // Base64会使有效负载膨胀约4/3；限制编码字节，使有效负载保持在5MB以下（API限制）。
        let maxEncodedBytes = (maxPayloadBytes / 4) * 3
        let res = try JPEGTranscoder.transcodeToJPEG(
            imageData: rawData,
            maxWidthPx: maxWidth,
            quality: quality,
            maxBytes: maxEncodedBytes)

        return (
            format: format.rawValue,
            base64: res.data.base64EncodedString(),
            width: res.widthPx,
            height: res.heightPx)
    }

    /// 录制视频
    /// - Parameter params: 录制参数
    /// - Returns: 包含格式、base64编码、持续时间和是否有音频的元组
    func clip(params: MoltbotCameraClipParams) async throws -> (
        format: String,
        base64: String,
        durationMs: Int,
        hasAudio: Bool)
    {
        let facing = params.facing ?? .front    // 默认使用前置摄像头
        let durationMs = Self.clampDurationMs(params.durationMs)  // 限制持续时间范围
        let includeAudio = params.includeAudio ?? true  // 默认包含音频
        let format = params.format ?? .mp4      // 默认使用MP4格式

        // 确保有视频访问权限
        try await self.ensureAccess(for: .video)
        if includeAudio {
            // 如果需要音频，确保有音频访问权限
            try await self.ensureAccess(for: .audio)
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high  // 设置为高质量

        // 选择相机设备
        guard let camera = Self.pickCamera(facing: facing, deviceId: params.deviceId) else {
            throw CameraError.cameraUnavailable
        }
        // 添加相机输入
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
            if session.canAddInput(micInput) {
                session.addInput(micInput)
            } else {
                throw CameraError.captureFailed("添加麦克风输入失败")
            }
        }

        // 添加视频输出
        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else {
            throw CameraError.captureFailed("添加视频输出失败")
        }
        session.addOutput(output)
        output.maxRecordedDuration = CMTime(value: Int64(durationMs), timescale: 1000)

        // 启动会话
        session.startRunning()
        defer { session.stopRunning() }  // 确保会话最终会停止
        await Self.warmUpCaptureSession()  // 预热捕获会话

        // 创建临时文件URL
        let movURL = FileManager().temporaryDirectory
            .appendingPathComponent("moltbot-camera-\(UUID().uuidString).mov")
        let mp4URL = FileManager().temporaryDirectory
            .appendingPathComponent("moltbot-camera-\(UUID().uuidString).mp4")

        // 确保临时文件最终会被删除
        defer {
            try? FileManager().removeItem(at: movURL)
            try? FileManager().removeItem(at: mp4URL)
        }

        // 开始录制
        var delegate: MovieFileDelegate?
        let recordedURL: URL = try await withCheckedThrowingContinuation { cont in
            let d = MovieFileDelegate(cont)
            delegate = d
            output.startRecording(to: movURL, recordingDelegate: d)
        }
        withExtendedLifetime(delegate) {}

        // 将.mov转换为.mp4以便于下游处理。
        try await Self.exportToMP4(inputURL: recordedURL, outputURL: mp4URL)

        // 读取MP4数据并返回
        let data = try Data(contentsOf: mp4URL)
        return (
            format: format.rawValue,
            base64: data.base64EncodedString(),
            durationMs: durationMs,
            hasAudio: includeAudio)
    }

    /// 列出所有可用的相机设备
    /// - Returns: 相机设备信息数组
    func listDevices() -> [CameraDeviceInfo] {
        return Self.discoverVideoDevices().map { device in
            CameraDeviceInfo(
                id: device.uniqueID,
                name: device.localizedName,
                position: Self.positionLabel(device.position),
                deviceType: device.deviceType.rawValue)
        }
    }

    /// 确保对指定媒体类型有访问权限
    /// - Parameter mediaType: 媒体类型（视频或音频）
    private func ensureAccess(for mediaType: AVMediaType) async throws {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        switch status {
        case .authorized:
            return  // 已经授权
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
            // 权限被拒绝或受限
            throw CameraError.permissionDenied(kind: mediaType == .video ? "相机" : "麦克风")
        @unknown default:
            // 未知状态，视为权限被拒绝
            throw CameraError.permissionDenied(kind: mediaType == .video ? "相机" : "麦克风")
        }
    }

    /// 选择相机设备
    /// - Parameters:
    ///   - facing: 摄像头朝向
    ///   - deviceId: 设备ID
    /// - Returns: 选中的相机设备，或nil如果没有找到
    private nonisolated static func pickCamera(
        facing: MoltbotCameraFacing,
        deviceId: String?) -> AVCaptureDevice?
    {
        // 如果指定了设备ID，尝试使用该设备
        if let deviceId, !deviceId.isEmpty {
            if let match = Self.discoverVideoDevices().first(where: { $0.uniqueID == deviceId }) {
                return match
            }
        }
        // 根据朝向选择相机
        let position: AVCaptureDevice.Position = (facing == .front) ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        // 回退到任何默认相机（例如模拟器/不寻常的设备配置）。
        return AVCaptureDevice.default(for: .video)
    }

    /// 获取位置标签
    /// - Parameter position: 设备位置
    /// - Returns: 位置标签字符串
    private nonisolated static func positionLabel(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: "front"
        case .back: "back"
        default: "unspecified"
        }
    }

    /// 发现所有视频设备
    /// - Returns: 视频设备数组
    private nonisolated static func discoverVideoDevices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,      // 内置广角相机
            .builtInUltraWideCamera,      // 内置超广角相机
            .builtInTelephotoCamera,      // 内置长焦相机
            .builtInDualCamera,           // 内置双摄像头
            .builtInDualWideCamera,       // 内置双广角相机
            .builtInTripleCamera,         // 内置三摄像头
            .builtInTrueDepthCamera,      // 内置TrueDepth相机
            .builtInLiDARDepthCamera,     // 内置LiDAR深度相机
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified)
        return session.devices
    }

    /// 限制质量值在有效范围内
    /// - Parameter quality: 质量值
    /// - Returns: 限制后的质量值
    nonisolated static func clampQuality(_ quality: Double?) -> Double {
        let q = quality ?? 0.9  // 默认质量为0.9
        return min(1.0, max(0.05, q))  // 限制在0.05到1.0之间
    }

    /// 限制持续时间在有效范围内
    /// - Parameter ms: 毫秒数
    /// - Returns: 限制后的毫秒数
    nonisolated static func clampDurationMs(_ ms: Int?) -> Int {
        let v = ms ?? 3000  // 默认持续时间为3秒
        // 默认保持视频片段较短；避免在网关上产生巨大的base64有效负载。
        return min(60000, max(250, v))  // 限制在250毫秒到60秒之间
    }

    /// 将视频导出为MP4格式
    /// - Parameters:
    ///   - inputURL: 输入文件URL
    ///   - outputURL: 输出文件URL
    private nonisolated static func exportToMP4(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw CameraError.exportFailed("创建导出会话失败")
        }
        exporter.shouldOptimizeForNetworkUse = true  // 优化网络使用

        // 检查iOS版本，使用适当的导出方法
        if #available(iOS 18.0, tvOS 18.0, visionOS 2.0, *) {
            do {
                try await exporter.export(to: outputURL, as: .mp4)
                return
            } catch {
                throw CameraError.exportFailed(error.localizedDescription)
            }
        } else {
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4

            // 使用传统的异步导出方法
            try await withCheckedThrowingContinuation(isolation: nil) { (cont: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    cont.resume(returning: ())
                }
            }

            // 检查导出状态
            switch exporter.status {
            case .completed:
                return
            case .failed:
                throw CameraError.exportFailed(exporter.error?.localizedDescription ?? "导出失败")
            case .cancelled:
                throw CameraError.exportFailed("导出被取消")
            default:
                throw CameraError.exportFailed("导出未完成")
            }
        }
    }

    /// 预热捕获会话
    /// 在`startRunning()`后短暂延迟可显著减少某些设备上的"空白第一帧"捕获。
    private nonisolated static func warmUpCaptureSession() async {
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
    }

    /// 延迟指定毫秒数
    /// - Parameter delayMs: 延迟毫秒数
    private nonisolated static func sleepDelayMs(_ delayMs: Int) async {
        guard delayMs > 0 else { return }
        let maxDelayMs = 10 * 1000  // 最大延迟10秒
        let ns = UInt64(min(delayMs, maxDelayMs)) * UInt64(NSEC_PER_MSEC)
        try? await Task.sleep(nanoseconds: ns)
    }
}

/// 照片捕获委托，用于处理照片捕获完成事件
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<Data, Error>
    private var didResume = false

    init(_ continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?)
    {
        guard !self.didResume else { return }
        self.didResume = true

        // 处理错误
        if let error {
            self.continuation.resume(throwing: error)
            return
        }
        // 检查照片数据
        guard let data = photo.fileDataRepresentation() else {
            self.continuation.resume(
                throwing: NSError(domain: "Camera", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "照片数据缺失",
                ]))
            return
        }
        // 检查数据是否为空
        if data.isEmpty {
            self.continuation.resume(
                throwing: NSError(domain: "Camera", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "照片数据为空",
                ]))
            return
        }
        // 返回照片数据
        self.continuation.resume(returning: data)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?)
    {
        guard let error else { return }
        guard !self.didResume else { return }
        self.didResume = true
        self.continuation.resume(throwing: error)
    }
}

/// 视频文件委托，用于处理视频录制完成事件
private final class MovieFileDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let continuation: CheckedContinuation<URL, Error>
    private var didResume = false

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?)
    {
        guard !self.didResume else { return }
        self.didResume = true

        if let error {
            let ns = error as NSError
            // 处理达到最大持续时间的情况（这不是真正的错误）
            if ns.domain == AVFoundationErrorDomain,
               ns.code == AVError.maximumDurationReached.rawValue
            {
                self.continuation.resume(returning: outputFileURL)
                return
            }
            // 处理其他错误
            self.continuation.resume(throwing: error)
            return
        }
        // 没有错误，返回录制的文件URL
        self.continuation.resume(returning: outputFileURL)
    }
}
