import Foundation

/// 桥接帧基础结构体，所有桥接帧的基类
/// 实现了Codable和Sendable协议，用于序列化和并发安全
public struct BridgeBaseFrame: Codable, Sendable {
    /// 帧类型
    public let type: String

    /// 初始化方法
    /// - Parameter type: 帧类型
    public init(type: String) {
        self.type = type
    }
}

/// 桥接调用请求结构体
/// 用于从节点向桥接发送命令调用请求
public struct BridgeInvokeRequest: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 请求唯一标识符
    public let id: String
    /// 要执行的命令
    public let command: String
    /// 参数的JSON字符串表示
    public let paramsJSON: String?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"invoke"
    ///   - id: 请求唯一标识符
    ///   - command: 要执行的命令
    ///   - paramsJSON: 参数的JSON字符串表示，默认为nil
    public init(type: String = "invoke", id: String, command: String, paramsJSON: String? = nil) {
        self.type = type
        self.id = id
        self.command = command
        self.paramsJSON = paramsJSON
    }
}

/// 桥接调用响应结构体
/// 用于从桥接向节点返回命令执行结果
public struct BridgeInvokeResponse: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 响应唯一标识符，与请求的id对应
    public let id: String
    /// 命令执行是否成功
    public let ok: Bool
    /// 响应数据的JSON字符串表示
    public let payloadJSON: String?
    /// 错误信息，如果有的话
    public let error: MoltbotNodeError?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"invoke-res"
    ///   - id: 响应唯一标识符，与请求的id对应
    ///   - ok: 命令执行是否成功
    ///   - payloadJSON: 响应数据的JSON字符串表示，默认为nil
    ///   - error: 错误信息，如果有的话，默认为nil
    public init(
        type: String = "invoke-res",
        id: String,
        ok: Bool,
        payloadJSON: String? = nil,
        error: MoltbotNodeError? = nil)
    {
        self.type = type
        self.id = id
        self.ok = ok
        self.payloadJSON = payloadJSON
        self.error = error
    }
}

/// 桥接事件帧结构体
/// 用于从桥接向节点发送事件通知
public struct BridgeEventFrame: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 事件名称
    public let event: String
    /// 事件数据的JSON字符串表示
    public let payloadJSON: String?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"event"
    ///   - event: 事件名称
    ///   - payloadJSON: 事件数据的JSON字符串表示，默认为nil
    public init(type: String = "event", event: String, payloadJSON: String? = nil) {
        self.type = type
        self.event = event
        self.payloadJSON = payloadJSON
    }
}

/// 桥接握手请求结构体
/// 用于节点与桥接建立连接时的握手过程
public struct BridgeHello: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 节点唯一标识符
    public let nodeId: String
    /// 节点显示名称
    public let displayName: String?
    /// 认证令牌
    public let token: String?
    /// 平台信息
    public let platform: String?
    /// 版本信息
    public let version: String?
    /// 核心版本信息
    public let coreVersion: String?
    /// UI版本信息
    public let uiVersion: String?
    /// 设备家族
    public let deviceFamily: String?
    /// 模型标识符
    public let modelIdentifier: String?
    /// 节点能力列表
    public let caps: [String]?
    /// 支持的命令列表
    public let commands: [String]?
    /// 权限映射表
    public let permissions: [String: Bool]?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"hello"
    ///   - nodeId: 节点唯一标识符
    ///   - displayName: 节点显示名称
    ///   - token: 认证令牌
    ///   - platform: 平台信息
    ///   - version: 版本信息
    ///   - coreVersion: 核心版本信息，默认为nil
    ///   - uiVersion: UI版本信息，默认为nil
    ///   - deviceFamily: 设备家族，默认为nil
    ///   - modelIdentifier: 模型标识符，默认为nil
    ///   - caps: 节点能力列表，默认为nil
    ///   - commands: 支持的命令列表，默认为nil
    ///   - permissions: 权限映射表，默认为nil
    public init(
        type: String = "hello",
        nodeId: String,
        displayName: String?,
        token: String?,
        platform: String?,
        version: String?,
        coreVersion: String? = nil,
        uiVersion: String? = nil,
        deviceFamily: String? = nil,
        modelIdentifier: String? = nil,
        caps: [String]? = nil,
        commands: [String]? = nil,
        permissions: [String: Bool]? = nil)
    {
        self.type = type
        self.nodeId = nodeId
        self.displayName = displayName
        self.token = token
        self.platform = platform
        self.version = version
        self.coreVersion = coreVersion
        self.uiVersion = uiVersion
        self.deviceFamily = deviceFamily
        self.modelIdentifier = modelIdentifier
        self.caps = caps
        self.commands = commands
        self.permissions = permissions
    }
}

/// 桥接握手响应结构体
/// 用于桥接对节点握手请求的响应
public struct BridgeHelloOk: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 服务器名称
    public let serverName: String
    /// Canvas主机URL
    public let canvasHostUrl: String?
    /// 主会话密钥
    public let mainSessionKey: String?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"hello-ok"
    ///   - serverName: 服务器名称
    ///   - canvasHostUrl: Canvas主机URL，默认为nil
    ///   - mainSessionKey: 主会话密钥，默认为nil
    public init(
        type: String = "hello-ok",
        serverName: String,
        canvasHostUrl: String? = nil,
        mainSessionKey: String? = nil)
    {
        self.type = type
        self.serverName = serverName
        self.canvasHostUrl = canvasHostUrl
        self.mainSessionKey = mainSessionKey
    }
}

/// 桥接配对请求结构体
/// 用于节点请求与桥接进行配对
public struct BridgePairRequest: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 节点唯一标识符
    public let nodeId: String
    /// 节点显示名称
    public let displayName: String?
    /// 平台信息
    public let platform: String?
    /// 版本信息
    public let version: String?
    /// 核心版本信息
    public let coreVersion: String?
    /// UI版本信息
    public let uiVersion: String?
    /// 设备家族
    public let deviceFamily: String?
    /// 模型标识符
    public let modelIdentifier: String?
    /// 节点能力列表
    public let caps: [String]?
    /// 支持的命令列表
    public let commands: [String]?
    /// 权限映射表
    public let permissions: [String: Bool]?
    /// 远程地址
    public let remoteAddress: String?
    /// 是否静默配对
    public let silent: Bool?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"pair-request"
    ///   - nodeId: 节点唯一标识符
    ///   - displayName: 节点显示名称
    ///   - platform: 平台信息
    ///   - version: 版本信息
    ///   - coreVersion: 核心版本信息，默认为nil
    ///   - uiVersion: UI版本信息，默认为nil
    ///   - deviceFamily: 设备家族，默认为nil
    ///   - modelIdentifier: 模型标识符，默认为nil
    ///   - caps: 节点能力列表，默认为nil
    ///   - commands: 支持的命令列表，默认为nil
    ///   - permissions: 权限映射表，默认为nil
    ///   - remoteAddress: 远程地址，默认为nil
    ///   - silent: 是否静默配对，默认为nil
    public init(
        type: String = "pair-request",
        nodeId: String,
        displayName: String?,
        platform: String?,
        version: String?,
        coreVersion: String? = nil,
        uiVersion: String? = nil,
        deviceFamily: String? = nil,
        modelIdentifier: String? = nil,
        caps: [String]? = nil,
        commands: [String]? = nil,
        permissions: [String: Bool]? = nil,
        remoteAddress: String? = nil,
        silent: Bool? = nil)
    {
        self.type = type
        self.nodeId = nodeId
        self.displayName = displayName
        self.platform = platform
        self.version = version
        self.coreVersion = coreVersion
        self.uiVersion = uiVersion
        self.deviceFamily = deviceFamily
        self.modelIdentifier = modelIdentifier
        self.caps = caps
        self.commands = commands
        self.permissions = permissions
        self.remoteAddress = remoteAddress
        self.silent = silent
    }
}

/// 桥接配对响应结构体
/// 用于桥接对节点配对请求的响应
public struct BridgePairOk: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 配对令牌
    public let token: String

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"pair-ok"
    ///   - token: 配对令牌
    public init(type: String = "pair-ok", token: String) {
        self.type = type
        self.token = token
    }
}

/// 桥接 Ping 结构体
/// 用于测试连接是否活跃
public struct BridgePing: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 请求唯一标识符
    public let id: String

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"ping"
    ///   - id: 请求唯一标识符
    public init(type: String = "ping", id: String) {
        self.type = type
        self.id = id
    }
}

/// 桥接 Pong 结构体
/// 用于响应 Ping 请求
public struct BridgePong: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 响应唯一标识符，与请求的id对应
    public let id: String

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"pong"
    ///   - id: 响应唯一标识符，与请求的id对应
    public init(type: String = "pong", id: String) {
        self.type = type
        self.id = id
    }
}

/// 桥接错误帧结构体
/// 用于传递错误信息
public struct BridgeErrorFrame: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 错误代码
    public let code: String
    /// 错误消息
    public let message: String

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"error"
    ///   - code: 错误代码
    ///   - message: 错误消息
    public init(type: String = "error", code: String, message: String) {
        self.type = type
        self.code = code
        self.message = message
    }
}

// MARK: - 可选 RPC (节点 -> 桥接)

/// 桥接 RPC 请求结构体
/// 用于节点向桥接发送 RPC 请求
public struct BridgeRPCRequest: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 请求唯一标识符
    public let id: String
    /// 要调用的方法
    public let method: String
    /// 参数的JSON字符串表示
    public let paramsJSON: String?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"req"
    ///   - id: 请求唯一标识符
    ///   - method: 要调用的方法
    ///   - paramsJSON: 参数的JSON字符串表示，默认为nil
    public init(type: String = "req", id: String, method: String, paramsJSON: String? = nil) {
        self.type = type
        self.id = id
        self.method = method
        self.paramsJSON = paramsJSON
    }
}

/// 桥接 RPC 错误结构体
/// 用于表示 RPC 调用的错误
public struct BridgeRPCError: Codable, Sendable, Equatable {
    /// 错误代码
    public let code: String
    /// 错误消息
    public let message: String

    /// 初始化方法
    /// - Parameters:
    ///   - code: 错误代码
    ///   - message: 错误消息
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// 桥接 RPC 响应结构体
/// 用于桥接对 RPC 请求的响应
public struct BridgeRPCResponse: Codable, Sendable {
    /// 帧类型
    public let type: String
    /// 响应唯一标识符，与请求的id对应
    public let id: String
    /// RPC调用是否成功
    public let ok: Bool
    /// 响应数据的JSON字符串表示
    public let payloadJSON: String?
    /// 错误信息，如果有的话
    public let error: BridgeRPCError?

    /// 初始化方法
    /// - Parameters:
    ///   - type: 帧类型，默认为"res"
    ///   - id: 响应唯一标识符，与请求的id对应
    ///   - ok: RPC调用是否成功
    ///   - payloadJSON: 响应数据的JSON字符串表示，默认为nil
    ///   - error: 错误信息，如果有的话，默认为nil
    public init(
        type: String = "res",
        id: String,
        ok: Bool,
        payloadJSON: String? = nil,
        error: BridgeRPCError? = nil)
    {
        self.type = type
        self.id = id
        self.ok = ok
        self.payloadJSON = payloadJSON
        self.error = error
    }
}
