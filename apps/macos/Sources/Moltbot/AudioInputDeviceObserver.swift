import CoreAudio
import Foundation
import OSLog

/// 音频输入设备观察者类，用于监控系统音频输入设备的变化
/// 提供获取默认输入设备、活跃输入设备的功能，并支持监听设备变化事件
final class AudioInputDeviceObserver {
    /// 日志记录器，用于记录音频设备相关的日志信息
    private let logger = Logger(subsystem: "bot.molt", category: "audio.devices")
    /// 标记观察者是否处于活跃状态
    private var isActive = false
    /// 设备列表变化监听器
    private var devicesListener: AudioObjectPropertyListenerBlock?
    /// 默认输入设备变化监听器
    private var defaultInputListener: AudioObjectPropertyListenerBlock?

    /// 获取系统默认音频输入设备的唯一标识符(UID)
    /// - Returns: 默认输入设备的UID字符串，如果获取失败则返回nil
    static func defaultInputDeviceUID() -> String? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            &size,
            &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return self.deviceUID(for: deviceID)
    }

    /// 获取所有活跃的音频输入设备的唯一标识符(UID)集合
    /// - Returns: 活跃输入设备的UID字符串集合
    static func aliveInputDeviceUIDs() -> Set<String> {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else { return [] }

        var output = Set<String>()
        for deviceID in deviceIDs {
            guard self.deviceIsAlive(deviceID) else { continue }  // 跳过非活跃设备
            guard self.deviceHasInput(deviceID) else { continue }  // 跳过无输入功能的设备
            if let uid = self.deviceUID(for: deviceID) {
                output.insert(uid)
            }
        }
        return output
    }

    /// 获取默认音频输入设备的摘要信息
    /// - Returns: 包含默认输入设备名称和UID的字符串描述
    static func defaultInputDeviceSummary() -> String {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            &size,
            &deviceID)
        guard status == noErr, deviceID != 0 else {
            return "defaultInput=unknown"
        }
        let uid = self.deviceUID(for: deviceID) ?? "unknown"
        let name = self.deviceName(for: deviceID) ?? "unknown"
        return "defaultInput=\(name) (\(uid))"
    }

    /// 启动音频设备观察者，开始监听设备变化
    /// - Parameter onChange: 当音频设备发生变化时调用的回调函数
    func start(onChange: @escaping @Sendable () -> Void) {
        guard !self.isActive else { return }  // 如果已经活跃，则直接返回
        self.isActive = true

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let queue = DispatchQueue.main  // 使用主队列处理回调

        // 注册设备列表变化监听器
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let devicesListener: AudioObjectPropertyListenerBlock = { _, _ in
            self.logDefaultInputChange(reason: "devices")
            onChange()
        }
        let devicesStatus = AudioObjectAddPropertyListenerBlock(
            systemObject,
            &devicesAddress,
            queue,
            devicesListener)

        // 注册默认输入设备变化监听器
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let defaultInputListener: AudioObjectPropertyListenerBlock = { _, _ in
            self.logDefaultInputChange(reason: "default")
            onChange()
        }
        let defaultStatus = AudioObjectAddPropertyListenerBlock(
            systemObject,
            &defaultInputAddress,
            queue,
            defaultInputListener)

        // 检查监听器注册是否成功
        if devicesStatus != noErr || defaultStatus != noErr {
            self.logger.error("audio device observer install failed devices=\(devicesStatus) default=\(defaultStatus)")
        }

        self.logger.info("audio device observer started (\(Self.defaultInputDeviceSummary(), privacy: .public))")

        // 保存监听器引用，以便后续停止时移除
        self.devicesListener = devicesListener
        self.defaultInputListener = defaultInputListener
    }

    /// 停止音频设备观察者，移除所有监听器
    func stop() {
        guard self.isActive else { return }  // 如果已经非活跃，则直接返回
        self.isActive = false
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        // 移除设备列表变化监听器
        if let devicesListener {
            var devicesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(
                systemObject,
                &devicesAddress,
                DispatchQueue.main,
                devicesListener)
        }

        // 移除默认输入设备变化监听器
        if let defaultInputListener {
            var defaultInputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(
                systemObject,
                &defaultInputAddress,
                DispatchQueue.main,
                defaultInputListener)
        }

        // 清空监听器引用
        self.devicesListener = nil
        self.defaultInputListener = nil
    }

    /// 获取指定音频设备的唯一标识符(UID)
    /// - Parameter deviceID: 音频设备的ID
    /// - Returns: 设备的UID字符串，如果获取失败则返回nil
    private static func deviceUID(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { return nil }
        return uid.takeUnretainedValue() as String
    }

    /// 获取指定音频设备的名称
    /// - Parameter deviceID: 音频设备的ID
    /// - Returns: 设备的名称字符串，如果获取失败则返回nil
    private static func deviceName(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeUnretainedValue() as String
    }

    /// 检查指定音频设备是否处于活跃状态
    /// - Parameter deviceID: 音频设备的ID
    /// - Returns: 如果设备活跃则返回true，否则返回false
    private static func deviceIsAlive(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive)
        return status == noErr && alive != 0
    }

    /// 检查指定音频设备是否具有输入功能
    /// - Parameter deviceID: 音频设备的ID
    /// - Returns: 如果设备具有输入功能则返回true，否则返回false
    private static func deviceHasInput(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return false }

        // 分配内存用于存储音频缓冲区列表
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }  // 确保内存被正确释放
        let bufferList = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        guard status == noErr else { return false }

        // 检查是否有包含通道的缓冲区
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains(where: { $0.mNumberChannels > 0 })
    }

    /// 记录默认音频输入设备变化的日志
    /// - Parameter reason: 变化的原因
    private func logDefaultInputChange(reason: StaticString) {
        self.logger.info("audio input changed (\(reason)) (\(Self.defaultInputDeviceSummary(), privacy: .public))")
    }
}
