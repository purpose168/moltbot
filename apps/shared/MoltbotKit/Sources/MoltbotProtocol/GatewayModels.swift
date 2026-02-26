// 由 scripts/protocol-gen-swift.ts 自动生成 — 请勿手动编辑
import Foundation

/// 网关协议版本
public let GATEWAY_PROTOCOL_VERSION = 3

/// 错误代码枚举
public enum ErrorCode: String, Codable, Sendable {
    /// 未链接
    case notLinked = "NOT_LINKED"
    /// 未配对
    case notPaired = "NOT_PAIRED"
    /// 代理超时
    case agentTimeout = "AGENT_TIMEOUT"
    /// 请求无效
    case invalidRequest = "INVALID_REQUEST"
    /// 服务不可用
    case unavailable = "UNAVAILABLE"
}

/// 连接参数结构体
public struct ConnectParams: Codable, Sendable {
    /// 最低协议版本
    public let minprotocol: Int
    /// 最高协议版本
    public let maxprotocol: Int
    /// 客户端信息
    public let client: [String: AnyCodable]
    /// 能力列表
    public let caps: [String]?
    /// 命令列表
    public let commands: [String]?
    /// 权限信息
    public let permissions: [String: AnyCodable]?
    /// 路径环境变量
    public let pathenv: String?
    /// 角色
    public let role: String?
    /// 作用域
    public let scopes: [String]?
    /// 设备信息
    public let device: [String: AnyCodable]?
    /// 认证信息
    public let auth: [String: AnyCodable]?
    /// 区域设置
    public let locale: String?
    /// 用户代理
    public let useragent: String?

    /// 初始化连接参数
    public init(
        minprotocol: Int,
        maxprotocol: Int,
        client: [String: AnyCodable],
        caps: [String]?,
        commands: [String]?,
        permissions: [String: AnyCodable]?,
        pathenv: String?,
        role: String?,
        scopes: [String]?,
        device: [String: AnyCodable]?,
        auth: [String: AnyCodable]?,
        locale: String?,
        useragent: String?
    ) {
        self.minprotocol = minprotocol
        self.maxprotocol = maxprotocol
        self.client = client
        self.caps = caps
        self.commands = commands
        self.permissions = permissions
        self.pathenv = pathenv
        self.role = role
        self.scopes = scopes
        self.device = device
        self.auth = auth
        self.locale = locale
        self.useragent = useragent
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case minprotocol = "minProtocol"
        case maxprotocol = "maxProtocol"
        case client
        case caps
        case commands
        case permissions
        case pathenv = "pathEnv"
        case role
        case scopes
        case device
        case auth
        case locale
        case useragent = "userAgent"
    }
}

/// 连接成功响应结构体
public struct HelloOk: Codable, Sendable {
    /// 消息类型
    public let type: String
    /// 协议版本
    public let _protocol: Int
    /// 服务器信息
    public let server: [String: AnyCodable]
    /// 特性列表
    public let features: [String: AnyCodable]
    /// 系统快照
    public let snapshot: Snapshot
    /// Canvas 主机 URL
    public let canvashosturl: String?
    /// 认证信息
    public let auth: [String: AnyCodable]?
    /// 策略配置
    public let policy: [String: AnyCodable]

    /// 初始化连接成功响应
    public init(
        type: String,
        _protocol: Int,
        server: [String: AnyCodable],
        features: [String: AnyCodable],
        snapshot: Snapshot,
        canvashosturl: String?,
        auth: [String: AnyCodable]?,
        policy: [String: AnyCodable]
    ) {
        self.type = type
        self._protocol = _protocol
        self.server = server
        self.features = features
        self.snapshot = snapshot
        self.canvashosturl = canvashosturl
        self.auth = auth
        self.policy = policy
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case type
        case _protocol = "protocol"
        case server
        case features
        case snapshot
        case canvashosturl = "canvasHostUrl"
        case auth
        case policy
    }
}

/// 请求帧结构体
public struct RequestFrame: Codable, Sendable {
    /// 消息类型
    public let type: String
    /// 请求 ID
    public let id: String
    /// 请求方法
    public let method: String
    /// 请求参数
    public let params: AnyCodable?

    /// 初始化请求帧
    public init(
        type: String,
        id: String,
        method: String,
        params: AnyCodable?
    ) {
        self.type = type
        self.id = id
        self.method = method
        self.params = params
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case method
        case params
    }
}

/// 响应帧结构体
public struct ResponseFrame: Codable, Sendable {
    /// 消息类型
    public let type: String
    /// 响应 ID
    public let id: String
    /// 是否成功
    public let ok: Bool
    /// 响应数据
    public let payload: AnyCodable?
    /// 错误信息
    public let error: [String: AnyCodable]?

    /// 初始化响应帧
    public init(
        type: String,
        id: String,
        ok: Bool,
        payload: AnyCodable?,
        error: [String: AnyCodable]?
    ) {
        self.type = type
        self.id = id
        self.ok = ok
        self.payload = payload
        self.error = error
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case ok
        case payload
        case error
    }
}

/// 事件帧结构体
public struct EventFrame: Codable, Sendable {
    /// 消息类型
    public let type: String
    /// 事件名称
    public let event: String
    /// 事件数据
    public let payload: AnyCodable?
    /// 序列号
    public let seq: Int?
    /// 状态版本
    public let stateversion: [String: AnyCodable]?

    /// 初始化事件帧
    public init(
        type: String,
        event: String,
        payload: AnyCodable?,
        seq: Int?,
        stateversion: [String: AnyCodable]?
    ) {
        self.type = type
        self.event = event
        self.payload = payload
        self.seq = seq
        self.stateversion = stateversion
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case type
        case event
        case payload
        case seq
        case stateversion = "stateVersion"
    }
}

/// 存在状态条目结构体
public struct PresenceEntry: Codable, Sendable {
    /// 主机名
    public let host: String?
    /// IP 地址
    public let ip: String?
    /// 版本号
    public let version: String?
    /// 平台
    public let platform: String?
    /// 设备家族
    public let devicefamily: String?
    /// 模型标识符
    public let modelidentifier: String?
    /// 模式
    public let mode: String?
    /// 最后输入时间（秒）
    public let lastinputseconds: Int?
    /// 原因
    public let reason: String?
    /// 标签列表
    public let tags: [String]?
    /// 文本信息
    public let text: String?
    /// 时间戳
    public let ts: Int
    /// 设备 ID
    public let deviceid: String?
    /// 角色列表
    public let roles: [String]?
    /// 作用域列表
    public let scopes: [String]?
    /// 实例 ID
    public let instanceid: String?

    /// 初始化存在状态条目
    public init(
        host: String?,
        ip: String?,
        version: String?,
        platform: String?,
        devicefamily: String?,
        modelidentifier: String?,
        mode: String?,
        lastinputseconds: Int?,
        reason: String?,
        tags: [String]?,
        text: String?,
        ts: Int,
        deviceid: String?,
        roles: [String]?,
        scopes: [String]?,
        instanceid: String?
    ) {
        self.host = host
        self.ip = ip
        self.version = version
        self.platform = platform
        self.devicefamily = devicefamily
        self.modelidentifier = modelidentifier
        self.mode = mode
        self.lastinputseconds = lastinputseconds
        self.reason = reason
        self.tags = tags
        self.text = text
        self.ts = ts
        self.deviceid = deviceid
        self.roles = roles
        self.scopes = scopes
        self.instanceid = instanceid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case host
        case ip
        case version
        case platform
        case devicefamily = "deviceFamily"
        case modelidentifier = "modelIdentifier"
        case mode
        case lastinputseconds = "lastInputSeconds"
        case reason
        case tags
        case text
        case ts
        case deviceid = "deviceId"
        case roles
        case scopes
        case instanceid = "instanceId"
    }
}

/// 状态版本结构体
public struct StateVersion: Codable, Sendable {
    /// 存在状态版本
    public let presence: Int
    /// 健康状态版本
    public let health: Int

    /// 初始化状态版本
    public init(
        presence: Int,
        health: Int
    ) {
        self.presence = presence
        self.health = health
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case presence
        case health
    }
}

/// 系统快照结构体
public struct Snapshot: Codable, Sendable {
    /// 存在状态条目列表
    public let presence: [PresenceEntry]
    /// 健康状态
    public let health: AnyCodable
    /// 状态版本
    public let stateversion: StateVersion
    /// 运行时间（毫秒）
    public let uptimems: Int
    /// 配置路径
    public let configpath: String?
    /// 状态目录
    public let statedir: String?
    /// 会话默认值
    public let sessiondefaults: [String: AnyCodable]?

    /// 初始化系统快照
    public init(
        presence: [PresenceEntry],
        health: AnyCodable,
        stateversion: StateVersion,
        uptimems: Int,
        configpath: String?,
        statedir: String?,
        sessiondefaults: [String: AnyCodable]?
    ) {
        self.presence = presence
        self.health = health
        self.stateversion = stateversion
        self.uptimems = uptimems
        self.configpath = configpath
        self.statedir = statedir
        self.sessiondefaults = sessiondefaults
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case presence
        case health
        case stateversion = "stateVersion"
        case uptimems = "uptimeMs"
        case configpath = "configPath"
        case statedir = "stateDir"
        case sessiondefaults = "sessionDefaults"
    }
}

/// 错误信息结构体
public struct ErrorShape: Codable, Sendable {
    /// 错误代码
    public let code: String
    /// 错误消息
    public let message: String
    /// 错误详情
    public let details: AnyCodable?
    /// 是否可重试
    public let retryable: Bool?
    /// 重试间隔（毫秒）
    public let retryafterms: Int?

    /// 初始化错误信息
    public init(
        code: String,
        message: String,
        details: AnyCodable?,
        retryable: Bool?,
        retryafterms: Int?
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.retryable = retryable
        self.retryafterms = retryafterms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case details
        case retryable
        case retryafterms = "retryAfterMs"
    }
}

/// 代理事件结构体
public struct AgentEvent: Codable, Sendable {
    /// 运行 ID
    public let runid: String
    /// 序列号
    public let seq: Int
    /// 流名称
    public let stream: String
    /// 时间戳
    public let ts: Int
    /// 事件数据
    public let data: [String: AnyCodable]

    /// 初始化代理事件
    public init(
        runid: String,
        seq: Int,
        stream: String,
        ts: Int,
        data: [String: AnyCodable]
    ) {
        self.runid = runid
        self.seq = seq
        self.stream = stream
        self.ts = ts
        self.data = data
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case runid = "runId"
        case seq
        case stream
        case ts
        case data
    }
}

/// 发送消息参数结构体
public struct SendParams: Codable, Sendable {
    /// 接收者
    public let to: String
    /// 消息内容
    public let message: String
    /// 媒体 URL
    public let mediaurl: String?
    /// 媒体 URL 列表
    public let mediaurls: [String]?
    /// GIF 播放控制
    public let gifplayback: Bool?
    /// 通道
    public let channel: String?
    /// 账户 ID
    public let accountid: String?
    /// 会话密钥
    public let sessionkey: String?
    /// 幂等性键
    public let idempotencykey: String

    /// 初始化发送消息参数
    public init(
        to: String,
        message: String,
        mediaurl: String?,
        mediaurls: [String]?,
        gifplayback: Bool?,
        channel: String?,
        accountid: String?,
        sessionkey: String?,
        idempotencykey: String
    ) {
        self.to = to
        self.message = message
        self.mediaurl = mediaurl
        self.mediaurls = mediaurls
        self.gifplayback = gifplayback
        self.channel = channel
        self.accountid = accountid
        self.sessionkey = sessionkey
        self.idempotencykey = idempotencykey
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case to
        case message
        case mediaurl = "mediaUrl"
        case mediaurls = "mediaUrls"
        case gifplayback = "gifPlayback"
        case channel
        case accountid = "accountId"
        case sessionkey = "sessionKey"
        case idempotencykey = "idempotencyKey"
    }
}

/// 发送投票参数结构体
public struct PollParams: Codable, Sendable {
    /// 接收者
    public let to: String
    /// 投票问题
    public let question: String
    /// 投票选项
    public let options: [String]
    /// 最大选择数量
    public let maxselections: Int?
    /// 持续时间（小时）
    public let durationhours: Int?
    /// 通道
    public let channel: String?
    /// 账户 ID
    public let accountid: String?
    /// 幂等性键
    public let idempotencykey: String

    /// 初始化发送投票参数
    public init(
        to: String,
        question: String,
        options: [String],
        maxselections: Int?,
        durationhours: Int?,
        channel: String?,
        accountid: String?,
        idempotencykey: String
    ) {
        self.to = to
        self.question = question
        self.options = options
        self.maxselections = maxselections
        self.durationhours = durationhours
        self.channel = channel
        self.accountid = accountid
        self.idempotencykey = idempotencykey
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case to
        case question
        case options
        case maxselections = "maxSelections"
        case durationhours = "durationHours"
        case channel
        case accountid = "accountId"
        case idempotencykey = "idempotencyKey"
    }
}

/// 代理请求参数结构体
public struct AgentParams: Codable, Sendable {
    /// 消息内容
    public let message: String
    /// 代理 ID
    public let agentid: String?
    /// 接收者
    public let to: String?
    /// 回复目标
    public let replyto: String?
    /// 会话 ID
    public let sessionid: String?
    /// 会话密钥
    public let sessionkey: String?
    /// 思考内容
    public let thinking: String?
    /// 是否发送
    public let deliver: Bool?
    /// 附件列表
    public let attachments: [AnyCodable]?
    /// 通道
    public let channel: String?
    /// 回复通道
    public let replychannel: String?
    /// 账户 ID
    public let accountid: String?
    /// 回复账户 ID
    public let replyaccountid: String?
    /// 线程 ID
    public let threadid: String?
    /// 群组 ID
    public let groupid: String?
    /// 群组通道
    public let groupchannel: String?
    /// 群组空间
    public let groupspace: String?
    /// 超时时间
    public let timeout: Int?
    /// 通道类型
    public let lane: String?
    /// 额外系统提示
    public let extrasystemprompt: String?
    /// 幂等性键
    public let idempotencykey: String
    /// 标签
    public let label: String?
    /// 由谁生成
    public let spawnedby: String?

    /// 初始化代理请求参数
    public init(
        message: String,
        agentid: String?,
        to: String?,
        replyto: String?,
        sessionid: String?,
        sessionkey: String?,
        thinking: String?,
        deliver: Bool?,
        attachments: [AnyCodable]?,
        channel: String?,
        replychannel: String?,
        accountid: String?,
        replyaccountid: String?,
        threadid: String?,
        groupid: String?,
        groupchannel: String?,
        groupspace: String?,
        timeout: Int?,
        lane: String?,
        extrasystemprompt: String?,
        idempotencykey: String,
        label: String?,
        spawnedby: String?
    ) {
        self.message = message
        self.agentid = agentid
        self.to = to
        self.replyto = replyto
        self.sessionid = sessionid
        self.sessionkey = sessionkey
        self.thinking = thinking
        self.deliver = deliver
        self.attachments = attachments
        self.channel = channel
        self.replychannel = replychannel
        self.accountid = accountid
        self.replyaccountid = replyaccountid
        self.threadid = threadid
        self.groupid = groupid
        self.groupchannel = groupchannel
        self.groupspace = groupspace
        self.timeout = timeout
        self.lane = lane
        self.extrasystemprompt = extrasystemprompt
        self.idempotencykey = idempotencykey
        self.label = label
        self.spawnedby = spawnedby
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case message
        case agentid = "agentId"
        case to
        case replyto = "replyTo"
        case sessionid = "sessionId"
        case sessionkey = "sessionKey"
        case thinking
        case deliver
        case attachments
        case channel
        case replychannel = "replyChannel"
        case accountid = "accountId"
        case replyaccountid = "replyAccountId"
        case threadid = "threadId"
        case groupid = "groupId"
        case groupchannel = "groupChannel"
        case groupspace = "groupSpace"
        case timeout
        case lane
        case extrasystemprompt = "extraSystemPrompt"
        case idempotencykey = "idempotencyKey"
        case label
        case spawnedby = "spawnedBy"
    }
}

/// 代理身份参数结构体
public struct AgentIdentityParams: Codable, Sendable {
    /// 代理 ID
    public let agentid: String?
    /// 会话密钥
    public let sessionkey: String?

    /// 初始化代理身份参数
    public init(
        agentid: String?,
        sessionkey: String?
    ) {
        self.agentid = agentid
        self.sessionkey = sessionkey
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case agentid = "agentId"
        case sessionkey = "sessionKey"
    }
}

/// 代理身份结果结构体
public struct AgentIdentityResult: Codable, Sendable {
    /// 代理 ID
    public let agentid: String
    /// 代理名称
    public let name: String?
    /// 头像 URL
    public let avatar: String?

    /// 初始化代理身份结果
    public init(
        agentid: String,
        name: String?,
        avatar: String?
    ) {
        self.agentid = agentid
        self.name = name
        self.avatar = avatar
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case agentid = "agentId"
        case name
        case avatar
    }
}

/// 代理等待参数结构体
public struct AgentWaitParams: Codable, Sendable {
    /// 运行 ID
    public let runid: String
    /// 超时时间（毫秒）
    public let timeoutms: Int?

    /// 初始化代理等待参数
    public init(
        runid: String,
        timeoutms: Int?
    ) {
        self.runid = runid
        self.timeoutms = timeoutms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case runid = "runId"
        case timeoutms = "timeoutMs"
    }
}

/// 唤醒参数结构体
public struct WakeParams: Codable, Sendable {
    /// 唤醒模式
    public let mode: AnyCodable
    /// 唤醒文本
    public let text: String

    /// 初始化唤醒参数
    public init(
        mode: AnyCodable,
        text: String
    ) {
        self.mode = mode
        self.text = text
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case mode
        case text
    }
}

/// 节点配对请求参数结构体
public struct NodePairRequestParams: Codable, Sendable {
    /// 节点 ID
    public let nodeid: String
    /// 显示名称
    public let displayname: String?
    /// 平台
    public let platform: String?
    /// 版本号
    public let version: String?
    /// 核心版本
    public let coreversion: String?
    /// UI 版本
    public let uiversion: String?
    /// 设备家族
    public let devicefamily: String?
    /// 模型标识符
    public let modelidentifier: String?
    /// 能力列表
    public let caps: [String]?
    /// 命令列表
    public let commands: [String]?
    /// 远程 IP
    public let remoteip: String?
    /// 是否静默
    public let silent: Bool?

    /// 初始化节点配对请求参数
    public init(
        nodeid: String,
        displayname: String?,
        platform: String?,
        version: String?,
        coreversion: String?,
        uiversion: String?,
        devicefamily: String?,
        modelidentifier: String?,
        caps: [String]?,
        commands: [String]?,
        remoteip: String?,
        silent: Bool?
    ) {
        self.nodeid = nodeid
        self.displayname = displayname
        self.platform = platform
        self.version = version
        self.coreversion = coreversion
        self.uiversion = uiversion
        self.devicefamily = devicefamily
        self.modelidentifier = modelidentifier
        self.caps = caps
        self.commands = commands
        self.remoteip = remoteip
        self.silent = silent
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case nodeid = "nodeId"
        case displayname = "displayName"
        case platform
        case version
        case coreversion = "coreVersion"
        case uiversion = "uiVersion"
        case devicefamily = "deviceFamily"
        case modelidentifier = "modelIdentifier"
        case caps
        case commands
        case remoteip = "remoteIp"
        case silent
    }
}

/// 节点配对列表参数结构体
public struct NodePairListParams: Codable, Sendable {
}

/// 节点配对批准参数结构体
public struct NodePairApproveParams: Codable, Sendable {
    /// 请求 ID
    public let requestid: String

    /// 初始化节点配对批准参数
    public init(
        requestid: String
    ) {
        self.requestid = requestid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case requestid = "requestId"
    }
}

/// 节点配对拒绝参数结构体
public struct NodePairRejectParams: Codable, Sendable {
    /// 请求 ID
    public let requestid: String

    /// 初始化节点配对拒绝参数
    public init(
        requestid: String
    ) {
        self.requestid = requestid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case requestid = "requestId"
    }
}

/// 节点配对验证参数结构体
public struct NodePairVerifyParams: Codable, Sendable {
    /// 节点 ID
    public let nodeid: String
    /// 验证令牌
    public let token: String

    /// 初始化节点配对验证参数
    public init(
        nodeid: String,
        token: String
    ) {
        self.nodeid = nodeid
        self.token = token
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case nodeid = "nodeId"
        case token
    }
}

/// 节点重命名参数结构体
public struct NodeRenameParams: Codable, Sendable {
    /// 节点 ID
    public let nodeid: String
    /// 新显示名称
    public let displayname: String

    /// 初始化节点重命名参数
    public init(
        nodeid: String,
        displayname: String
    ) {
        self.nodeid = nodeid
        self.displayname = displayname
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case nodeid = "nodeId"
        case displayname = "displayName"
    }
}

/// 节点列表参数结构体
public struct NodeListParams: Codable, Sendable {
}

/// 节点描述参数结构体
public struct NodeDescribeParams: Codable, Sendable {
    /// 节点 ID
    public let nodeid: String

    /// 初始化节点描述参数
    public init(
        nodeid: String
    ) {
        self.nodeid = nodeid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case nodeid = "nodeId"
    }
}

/// 节点调用参数结构体
public struct NodeInvokeParams: Codable, Sendable {
    /// 节点 ID
    public let nodeid: String
    /// 命令名称
    public let command: String
    /// 命令参数
    public let params: AnyCodable?
    /// 超时时间（毫秒）
    public let timeoutms: Int?
    /// 幂等性键
    public let idempotencykey: String

    /// 初始化节点调用参数
    public init(
        nodeid: String,
        command: String,
        params: AnyCodable?,
        timeoutms: Int?,
        idempotencykey: String
    ) {
        self.nodeid = nodeid
        self.command = command
        self.params = params
        self.timeoutms = timeoutms
        self.idempotencykey = idempotencykey
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case nodeid = "nodeId"
        case command
        case params
        case timeoutms = "timeoutMs"
        case idempotencykey = "idempotencyKey"
    }
}

/// 节点调用结果参数结构体
public struct NodeInvokeResultParams: Codable, Sendable {
    /// 调用 ID
    public let id: String
    /// 节点 ID
    public let nodeid: String
    /// 是否成功
    public let ok: Bool
    /// 返回数据
    public let payload: AnyCodable?
    /// JSON 格式返回数据
    public let payloadjson: String?
    /// 错误信息
    public let error: [String: AnyCodable]?

    /// 初始化节点调用结果参数
    public init(
        id: String,
        nodeid: String,
        ok: Bool,
        payload: AnyCodable?,
        payloadjson: String?,
        error: [String: AnyCodable]?
    ) {
        self.id = id
        self.nodeid = nodeid
        self.ok = ok
        self.payload = payload
        self.payloadjson = payloadjson
        self.error = error
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case nodeid = "nodeId"
        case ok
        case payload
        case payloadjson = "payloadJSON"
        case error
    }
}

/// 节点事件参数结构体
public struct NodeEventParams: Codable, Sendable {
    /// 事件名称
    public let event: String
    /// 事件数据
    public let payload: AnyCodable?
    /// JSON 格式事件数据
    public let payloadjson: String?

    /// 初始化节点事件参数
    public init(
        event: String,
        payload: AnyCodable?,
        payloadjson: String?
    ) {
        self.event = event
        self.payload = payload
        self.payloadjson = payloadjson
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case event
        case payload
        case payloadjson = "payloadJSON"
    }
}

/// 节点调用请求事件结构体
public struct NodeInvokeRequestEvent: Codable, Sendable {
    /// 调用 ID
    public let id: String
    /// 节点 ID
    public let nodeid: String
    /// 命令名称
    public let command: String
    /// JSON 格式命令参数
    public let paramsjson: String?
    /// 超时时间（毫秒）
    public let timeoutms: Int?
    /// 幂等性键
    public let idempotencykey: String?

    /// 初始化节点调用请求事件
    public init(
        id: String,
        nodeid: String,
        command: String,
        paramsjson: String?,
        timeoutms: Int?,
        idempotencykey: String?
    ) {
        self.id = id
        self.nodeid = nodeid
        self.command = command
        self.paramsjson = paramsjson
        self.timeoutms = timeoutms
        self.idempotencykey = idempotencykey
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case nodeid = "nodeId"
        case command
        case paramsjson = "paramsJSON"
        case timeoutms = "timeoutMs"
        case idempotencykey = "idempotencyKey"
    }
}

/// 会话列表参数结构体
public struct SessionsListParams: Codable, Sendable {
    /// 结果数量限制
    public let limit: Int?
    /// 活跃时间（分钟）
    public let activeminutes: Int?
    /// 是否包含全局会话
    public let includeglobal: Bool?
    /// 是否包含未知会话
    public let includeunknown: Bool?
    /// 是否包含派生标题
    public let includederivedtitles: Bool?
    /// 是否包含最后一条消息
    public let includelastmessage: Bool?
    /// 标签
    public let label: String?
    /// 由谁生成
    public let spawnedby: String?
    /// 代理 ID
    public let agentid: String?
    /// 搜索关键词
    public let search: String?

    /// 初始化会话列表参数
    public init(
        limit: Int?,
        activeminutes: Int?,
        includeglobal: Bool?,
        includeunknown: Bool?,
        includederivedtitles: Bool?,
        includelastmessage: Bool?,
        label: String?,
        spawnedby: String?,
        agentid: String?,
        search: String?
    ) {
        self.limit = limit
        self.activeminutes = activeminutes
        self.includeglobal = includeglobal
        self.includeunknown = includeunknown
        self.includederivedtitles = includederivedtitles
        self.includelastmessage = includelastmessage
        self.label = label
        self.spawnedby = spawnedby
        self.agentid = agentid
        self.search = search
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case limit
        case activeminutes = "activeMinutes"
        case includeglobal = "includeGlobal"
        case includeunknown = "includeUnknown"
        case includederivedtitles = "includeDerivedTitles"
        case includelastmessage = "includeLastMessage"
        case label
        case spawnedby = "spawnedBy"
        case agentid = "agentId"
        case search
    }
}

/// 会话预览参数结构体
public struct SessionsPreviewParams: Codable, Sendable {
    /// 会话键列表
    public let keys: [String]
    /// 结果数量限制
    public let limit: Int?
    /// 最大字符数
    public let maxchars: Int?

    /// 初始化会话预览参数
    public init(
        keys: [String],
        limit: Int?,
        maxchars: Int?
    ) {
        self.keys = keys
        self.limit = limit
        self.maxchars = maxchars
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case keys
        case limit
        case maxchars = "maxChars"
    }
}

/// 会话解析参数结构体
public struct SessionsResolveParams: Codable, Sendable {
    /// 会话键
    public let key: String?
    /// 会话 ID
    public let sessionid: String?
    /// 标签
    public let label: String?
    /// 代理 ID
    public let agentid: String?
    /// 由谁生成
    public let spawnedby: String?
    /// 是否包含全局会话
    public let includeglobal: Bool?
    /// 是否包含未知会话
    public let includeunknown: Bool?

    /// 初始化会话解析参数
    public init(
        key: String?,
        sessionid: String?,
        label: String?,
        agentid: String?,
        spawnedby: String?,
        includeglobal: Bool?,
        includeunknown: Bool?
    ) {
        self.key = key
        self.sessionid = sessionid
        self.label = label
        self.agentid = agentid
        self.spawnedby = spawnedby
        self.includeglobal = includeglobal
        self.includeunknown = includeunknown
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case key
        case sessionid = "sessionId"
        case label
        case agentid = "agentId"
        case spawnedby = "spawnedBy"
        case includeglobal = "includeGlobal"
        case includeunknown = "includeUnknown"
    }
}

/// 会话更新参数结构体
public struct SessionsPatchParams: Codable, Sendable {
    /// 会话键
    public let key: String
    /// 标签
    public let label: AnyCodable?
    /// 思考级别
    public let thinkinglevel: AnyCodable?
    /// 详细级别
    public let verboselevel: AnyCodable?
    /// 推理级别
    public let reasoninglevel: AnyCodable?
    /// 响应使用
    public let responseusage: AnyCodable?
    /// 提升级别
    public let elevatedlevel: AnyCodable?
    /// 执行主机
    public let exechost: AnyCodable?
    /// 执行安全
    public let execsecurity: AnyCodable?
    /// 执行询问
    public let execask: AnyCodable?
    /// 执行节点
    public let execnode: AnyCodable?
    /// 模型
    public let model: AnyCodable?
    /// 由谁生成
    public let spawnedby: AnyCodable?
    /// 发送策略
    public let sendpolicy: AnyCodable?
    /// 群组激活
    public let groupactivation: AnyCodable?

    /// 初始化会话更新参数
    public init(
        key: String,
        label: AnyCodable?,
        thinkinglevel: AnyCodable?,
        verboselevel: AnyCodable?,
        reasoninglevel: AnyCodable?,
        responseusage: AnyCodable?,
        elevatedlevel: AnyCodable?,
        exechost: AnyCodable?,
        execsecurity: AnyCodable?,
        execask: AnyCodable?,
        execnode: AnyCodable?,
        model: AnyCodable?,
        spawnedby: AnyCodable?,
        sendpolicy: AnyCodable?,
        groupactivation: AnyCodable?
    ) {
        self.key = key
        self.label = label
        self.thinkinglevel = thinkinglevel
        self.verboselevel = verboselevel
        self.reasoninglevel = reasoninglevel
        self.responseusage = responseusage
        self.elevatedlevel = elevatedlevel
        self.exechost = exechost
        self.execsecurity = execsecurity
        self.execask = execask
        self.execnode = execnode
        self.model = model
        self.spawnedby = spawnedby
        self.sendpolicy = sendpolicy
        self.groupactivation = groupactivation
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case thinkinglevel = "thinkingLevel"
        case verboselevel = "verboseLevel"
        case reasoninglevel = "reasoningLevel"
        case responseusage = "responseUsage"
        case elevatedlevel = "elevatedLevel"
        case exechost = "execHost"
        case execsecurity = "execSecurity"
        case execask = "execAsk"
        case execnode = "execNode"
        case model
        case spawnedby = "spawnedBy"
        case sendpolicy = "sendPolicy"
        case groupactivation = "groupActivation"
    }
}

/// 会话重置参数结构体
public struct SessionsResetParams: Codable, Sendable {
    /// 会话键
    public let key: String

    /// 初始化会话重置参数
    public init(
        key: String
    ) {
        self.key = key
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case key
    }
}

/// 会话删除参数结构体
public struct SessionsDeleteParams: Codable, Sendable {
    /// 会话键
    public let key: String
    /// 是否删除 transcripts
    public let deletetranscript: Bool?

    /// 初始化会话删除参数
    public init(
        key: String,
        deletetranscript: Bool?
    ) {
        self.key = key
        self.deletetranscript = deletetranscript
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case key
        case deletetranscript = "deleteTranscript"
    }
}

/// 会话压缩参数结构体
public struct SessionsCompactParams: Codable, Sendable {
    /// 会话键
    public let key: String
    /// 最大行数
    public let maxlines: Int?

    /// 初始化会话压缩参数
    public init(
        key: String,
        maxlines: Int?
    ) {
        self.key = key
        self.maxlines = maxlines
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case key
        case maxlines = "maxLines"
    }
}

/// 配置获取参数结构体
public struct ConfigGetParams: Codable, Sendable {
}

/// 配置设置参数结构体
public struct ConfigSetParams: Codable, Sendable {
    /// 配置原始内容
    public let raw: String
    /// 基础哈希值
    public let basehash: String?

    /// 初始化配置设置参数
    public init(
        raw: String,
        basehash: String?
    ) {
        self.raw = raw
        self.basehash = basehash
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case raw
        case basehash = "baseHash"
    }
}

/// 配置应用参数结构体
public struct ConfigApplyParams: Codable, Sendable {
    /// 配置原始内容
    public let raw: String
    /// 基础哈希值
    public let basehash: String?
    /// 会话密钥
    public let sessionkey: String?
    /// 备注信息
    public let note: String?
    /// 重启延迟（毫秒）
    public let restartdelayms: Int?

    /// 初始化配置应用参数
    public init(
        raw: String,
        basehash: String?,
        sessionkey: String?,
        note: String?,
        restartdelayms: Int?
    ) {
        self.raw = raw
        self.basehash = basehash
        self.sessionkey = sessionkey
        self.note = note
        self.restartdelayms = restartdelayms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case raw
        case basehash = "baseHash"
        case sessionkey = "sessionKey"
        case note
        case restartdelayms = "restartDelayMs"
    }
}

/// 配置补丁参数结构体
public struct ConfigPatchParams: Codable, Sendable {
    /// 配置原始内容
    public let raw: String
    /// 基础哈希值
    public let basehash: String?
    /// 会话密钥
    public let sessionkey: String?
    /// 备注信息
    public let note: String?
    /// 重启延迟（毫秒）
    public let restartdelayms: Int?

    /// 初始化配置补丁参数
    public init(
        raw: String,
        basehash: String?,
        sessionkey: String?,
        note: String?,
        restartdelayms: Int?
    ) {
        self.raw = raw
        self.basehash = basehash
        self.sessionkey = sessionkey
        self.note = note
        self.restartdelayms = restartdelayms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case raw
        case basehash = "baseHash"
        case sessionkey = "sessionKey"
        case note
        case restartdelayms = "restartDelayMs"
    }
}

/// 配置模式参数结构体
public struct ConfigSchemaParams: Codable, Sendable {
}

/// 配置模式响应结构体
public struct ConfigSchemaResponse: Codable, Sendable {
    /// 模式定义
    public let schema: AnyCodable
    /// UI 提示
    public let uihints: [String: AnyCodable]
    /// 版本号
    public let version: String
    /// 生成时间
    public let generatedat: String

    /// 初始化配置模式响应
    public init(
        schema: AnyCodable,
        uihints: [String: AnyCodable],
        version: String,
        generatedat: String
    ) {
        self.schema = schema
        self.uihints = uihints
        self.version = version
        self.generatedat = generatedat
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case schema
        case uihints = "uiHints"
        case version
        case generatedat = "generatedAt"
    }
}

/// 向导启动参数结构体
public struct WizardStartParams: Codable, Sendable {
    /// 向导模式
    public let mode: AnyCodable?
    /// 工作区
    public let workspace: String?

    /// 初始化向导启动参数
    public init(
        mode: AnyCodable?,
        workspace: String?
    ) {
        self.mode = mode
        self.workspace = workspace
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case mode
        case workspace
    }
}

/// 向导下一步参数结构体
public struct WizardNextParams: Codable, Sendable {
    /// 会话 ID
    public let sessionid: String
    /// 回答内容
    public let answer: [String: AnyCodable]?

    /// 初始化向导下一步参数
    public init(
        sessionid: String,
        answer: [String: AnyCodable]?
    ) {
        self.sessionid = sessionid
        self.answer = answer
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case sessionid = "sessionId"
        case answer
    }
}

/// 向导取消参数结构体
public struct WizardCancelParams: Codable, Sendable {
    /// 会话 ID
    public let sessionid: String

    /// 初始化向导取消参数
    public init(
        sessionid: String
    ) {
        self.sessionid = sessionid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case sessionid = "sessionId"
    }
}

/// 向导状态参数结构体
public struct WizardStatusParams: Codable, Sendable {
    /// 会话 ID
    public let sessionid: String

    /// 初始化向导状态参数
    public init(
        sessionid: String
    ) {
        self.sessionid = sessionid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case sessionid = "sessionId"
    }
}

/// 向导步骤结构体
public struct WizardStep: Codable, Sendable {
    /// 步骤 ID
    public let id: String
    /// 步骤类型
    public let type: AnyCodable
    /// 步骤标题
    public let title: String?
    /// 步骤消息
    public let message: String?
    /// 选项列表
    public let options: [[String: AnyCodable]]?
    /// 初始值
    public let initialvalue: AnyCodable?
    /// 占位符
    public let placeholder: String?
    /// 是否敏感
    public let sensitive: Bool?
    /// 执行器
    public let executor: AnyCodable?

    /// 初始化向导步骤
    public init(
        id: String,
        type: AnyCodable,
        title: String?,
        message: String?,
        options: [[String: AnyCodable]]?,
        initialvalue: AnyCodable?,
        placeholder: String?,
        sensitive: Bool?,
        executor: AnyCodable?
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.options = options
        self.initialvalue = initialvalue
        self.placeholder = placeholder
        self.sensitive = sensitive
        self.executor = executor
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case message
        case options
        case initialvalue = "initialValue"
        case placeholder
        case sensitive
        case executor
    }
}

/// 向导下一步结果结构体
public struct WizardNextResult: Codable, Sendable {
    /// 是否完成
    public let done: Bool
    /// 下一步骤
    public let step: [String: AnyCodable]?
    /// 状态信息
    public let status: AnyCodable?
    /// 错误信息
    public let error: String?

    /// 初始化向导下一步结果
    public init(
        done: Bool,
        step: [String: AnyCodable]?,
        status: AnyCodable?,
        error: String?
    ) {
        self.done = done
        self.step = step
        self.status = status
        self.error = error
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case done
        case step
        case status
        case error
    }
}

/// 向导启动结果结构体
public struct WizardStartResult: Codable, Sendable {
    /// 会话 ID
    public let sessionid: String
    /// 是否完成
    public let done: Bool
    /// 步骤信息
    public let step: [String: AnyCodable]?
    /// 状态信息
    public let status: AnyCodable?
    /// 错误信息
    public let error: String?

    /// 初始化向导启动结果
    public init(
        sessionid: String,
        done: Bool,
        step: [String: AnyCodable]?,
        status: AnyCodable?,
        error: String?
    ) {
        self.sessionid = sessionid
        self.done = done
        self.step = step
        self.status = status
        self.error = error
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case sessionid = "sessionId"
        case done
        case step
        case status
        case error
    }
}

/// 向导状态结果结构体
public struct WizardStatusResult: Codable, Sendable {
    /// 状态信息
    public let status: AnyCodable
    /// 错误信息
    public let error: String?

    /// 初始化向导状态结果
    public init(
        status: AnyCodable,
        error: String?
    ) {
        self.status = status
        self.error = error
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case status
        case error
    }
}

/// 对话模式参数结构体
public struct TalkModeParams: Codable, Sendable {
    /// 是否启用
    public let enabled: Bool
    /// 阶段
    public let phase: String?

    /// 初始化对话模式参数
    public init(
        enabled: Bool,
        phase: String?
    ) {
        self.enabled = enabled
        self.phase = phase
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case enabled
        case phase
    }
}

/// 通道状态参数结构体
public struct ChannelsStatusParams: Codable, Sendable {
    /// 是否探测
    public let probe: Bool?
    /// 超时时间（毫秒）
    public let timeoutms: Int?

    /// 初始化通道状态参数
    public init(
        probe: Bool?,
        timeoutms: Int?
    ) {
        self.probe = probe
        self.timeoutms = timeoutms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case probe
        case timeoutms = "timeoutMs"
    }
}

/// 通道状态结果结构体
public struct ChannelsStatusResult: Codable, Sendable {
    /// 时间戳
    public let ts: Int
    /// 通道顺序
    public let channelorder: [String]
    /// 通道标签
    public let channellabels: [String: AnyCodable]
    /// 通道详细标签
    public let channeldetaillabels: [String: AnyCodable]?
    /// 通道系统图片
    public let channelsystemimages: [String: AnyCodable]?
    /// 通道元数据
    public let channelmeta: [[String: AnyCodable]]?
    /// 通道状态
    public let channels: [String: AnyCodable]
    /// 通道账户
    public let channelaccounts: [String: AnyCodable]
    /// 通道默认账户 ID
    public let channeldefaultaccountid: [String: AnyCodable]

    /// 初始化通道状态结果
    public init(
        ts: Int,
        channelorder: [String],
        channellabels: [String: AnyCodable],
        channeldetaillabels: [String: AnyCodable]?,
        channelsystemimages: [String: AnyCodable]?,
        channelmeta: [[String: AnyCodable]]?,
        channels: [String: AnyCodable],
        channelaccounts: [String: AnyCodable],
        channeldefaultaccountid: [String: AnyCodable]
    ) {
        self.ts = ts
        self.channelorder = channelorder
        self.channellabels = channellabels
        self.channeldetaillabels = channeldetaillabels
        self.channelsystemimages = channelsystemimages
        self.channelmeta = channelmeta
        self.channels = channels
        self.channelaccounts = channelaccounts
        self.channeldefaultaccountid = channeldefaultaccountid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case ts
        case channelorder = "channelOrder"
        case channellabels = "channelLabels"
        case channeldetaillabels = "channelDetailLabels"
        case channelsystemimages = "channelSystemImages"
        case channelmeta = "channelMeta"
        case channels
        case channelaccounts = "channelAccounts"
        case channeldefaultaccountid = "channelDefaultAccountId"
    }
}

/// 通道登出参数结构体
public struct ChannelsLogoutParams: Codable, Sendable {
    /// 通道名称
    public let channel: String
    /// 账户 ID
    public let accountid: String?

    /// 初始化通道登出参数
    public init(
        channel: String,
        accountid: String?
    ) {
        self.channel = channel
        self.accountid = accountid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case channel
        case accountid = "accountId"
    }
}

/// Web 登录启动参数结构体
public struct WebLoginStartParams: Codable, Sendable {
    /// 是否强制登录
    public let force: Bool?
    /// 超时时间（毫秒）
    public let timeoutms: Int?
    /// 是否详细输出
    public let verbose: Bool?
    /// 账户 ID
    public let accountid: String?

    /// 初始化 Web 登录启动参数
    public init(
        force: Bool?,
        timeoutms: Int?,
        verbose: Bool?,
        accountid: String?
    ) {
        self.force = force
        self.timeoutms = timeoutms
        self.verbose = verbose
        self.accountid = accountid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case force
        case timeoutms = "timeoutMs"
        case verbose
        case accountid = "accountId"
    }
}

/// Web 登录等待参数结构体
public struct WebLoginWaitParams: Codable, Sendable {
    /// 超时时间（毫秒）
    public let timeoutms: Int?
    /// 账户 ID
    public let accountid: String?

    /// 初始化 Web 登录等待参数
    public init(
        timeoutms: Int?,
        accountid: String?
    ) {
        self.timeoutms = timeoutms
        self.accountid = accountid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case timeoutms = "timeoutMs"
        case accountid = "accountId"
    }
}

/// 代理摘要结构体
public struct AgentSummary: Codable, Sendable {
    /// 代理 ID
    public let id: String
    /// 代理名称
    public let name: String?
    /// 代理身份信息
    public let identity: [String: AnyCodable]?

    /// 初始化代理摘要
    public init(
        id: String,
        name: String?,
        identity: [String: AnyCodable]?
    ) {
        self.id = id
        self.name = name
        self.identity = identity
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case identity
    }
}

/// 代理列表参数结构体
public struct AgentsListParams: Codable, Sendable {
}

/// 代理列表结果结构体
public struct AgentsListResult: Codable, Sendable {
    /// 默认代理 ID
    public let defaultid: String
    /// 主密钥
    public let mainkey: String
    /// 作用域
    public let scope: AnyCodable
    /// 代理列表
    public let agents: [AgentSummary]

    /// 初始化代理列表结果
    public init(
        defaultid: String,
        mainkey: String,
        scope: AnyCodable,
        agents: [AgentSummary]
    ) {
        self.defaultid = defaultid
        self.mainkey = mainkey
        self.scope = scope
        self.agents = agents
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case defaultid = "defaultId"
        case mainkey = "mainKey"
        case scope
        case agents
    }
}

/// 模型选择结构体
public struct ModelChoice: Codable, Sendable {
    /// 模型 ID
    public let id: String
    /// 模型名称
    public let name: String
    /// 模型提供商
    public let provider: String
    /// 上下文窗口大小
    public let contextwindow: Int?
    /// 是否支持推理
    public let reasoning: Bool?

    /// 初始化模型选择
    public init(
        id: String,
        name: String,
        provider: String,
        contextwindow: Int?,
        reasoning: Bool?
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.contextwindow = contextwindow
        self.reasoning = reasoning
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case contextwindow = "contextWindow"
        case reasoning
    }
}

/// 模型列表参数结构体
public struct ModelsListParams: Codable, Sendable {
}

/// 模型列表结果结构体
public struct ModelsListResult: Codable, Sendable {
    /// 模型列表
    public let models: [ModelChoice]

    /// 初始化模型列表结果
    public init(
        models: [ModelChoice]
    ) {
        self.models = models
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case models
    }
}

/// 技能状态参数结构体
public struct SkillsStatusParams: Codable, Sendable {
}

/// 技能存储库参数结构体
public struct SkillsBinsParams: Codable, Sendable {
}

/// 技能存储库结果结构体
public struct SkillsBinsResult: Codable, Sendable {
    /// 存储库列表
    public let bins: [String]

    /// 初始化技能存储库结果
    public init(
        bins: [String]
    ) {
        self.bins = bins
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case bins
    }
}

/// 技能安装参数结构体
public struct SkillsInstallParams: Codable, Sendable {
    /// 技能名称
    public let name: String
    /// 安装 ID
    public let installid: String
    /// 超时时间（毫秒）
    public let timeoutms: Int?

    /// 初始化技能安装参数
    public init(
        name: String,
        installid: String,
        timeoutms: Int?
    ) {
        self.name = name
        self.installid = installid
        self.timeoutms = timeoutms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case name
        case installid = "installId"
        case timeoutms = "timeoutMs"
    }
}

/// 技能更新参数结构体
public struct SkillsUpdateParams: Codable, Sendable {
    /// 技能键
    public let skillkey: String
    /// 是否启用
    public let enabled: Bool?
    /// API 密钥
    public let apikey: String?
    /// 环境变量
    public let env: [String: AnyCodable]?

    /// 初始化技能更新参数
    public init(
        skillkey: String,
        enabled: Bool?,
        apikey: String?,
        env: [String: AnyCodable]?
    ) {
        self.skillkey = skillkey
        self.enabled = enabled
        self.apikey = apikey
        self.env = env
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case skillkey = "skillKey"
        case enabled
        case apikey = "apiKey"
        case env
    }
}

/// 定时任务结构体
public struct CronJob: Codable, Sendable {
    /// 任务 ID
    public let id: String
    /// 代理 ID
    public let agentid: String?
    /// 任务名称
    public let name: String
    /// 任务描述
    public let description: String?
    /// 是否启用
    public let enabled: Bool
    /// 运行后是否删除
    public let deleteafterrun: Bool?
    /// 创建时间（毫秒）
    public let createdatms: Int
    /// 更新时间（毫秒）
    public let updatedatms: Int
    /// 调度计划
    public let schedule: AnyCodable
    /// 会话目标
    public let sessiontarget: AnyCodable
    /// 唤醒模式
    public let wakemode: AnyCodable
    /// 任务数据
    public let payload: AnyCodable
    /// 隔离设置
    public let isolation: [String: AnyCodable]?
    /// 任务状态
    public let state: [String: AnyCodable]

    /// 初始化定时任务
    public init(
        id: String,
        agentid: String?,
        name: String,
        description: String?,
        enabled: Bool,
        deleteafterrun: Bool?,
        createdatms: Int,
        updatedatms: Int,
        schedule: AnyCodable,
        sessiontarget: AnyCodable,
        wakemode: AnyCodable,
        payload: AnyCodable,
        isolation: [String: AnyCodable]?,
        state: [String: AnyCodable]
    ) {
        self.id = id
        self.agentid = agentid
        self.name = name
        self.description = description
        self.enabled = enabled
        self.deleteafterrun = deleteafterrun
        self.createdatms = createdatms
        self.updatedatms = updatedatms
        self.schedule = schedule
        self.sessiontarget = sessiontarget
        self.wakemode = wakemode
        self.payload = payload
        self.isolation = isolation
        self.state = state
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case agentid = "agentId"
        case name
        case description
        case enabled
        case deleteafterrun = "deleteAfterRun"
        case createdatms = "createdAtMs"
        case updatedatms = "updatedAtMs"
        case schedule
        case sessiontarget = "sessionTarget"
        case wakemode = "wakeMode"
        case payload
        case isolation
        case state
    }
}

/// 定时任务列表参数结构体
public struct CronListParams: Codable, Sendable {
    /// 是否包含禁用的任务
    public let includedisabled: Bool?

    /// 初始化定时任务列表参数
    public init(
        includedisabled: Bool?
    ) {
        self.includedisabled = includedisabled
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case includedisabled = "includeDisabled"
    }
}

/// 定时任务状态参数结构体
public struct CronStatusParams: Codable, Sendable {
}

/// 定时任务添加参数结构体
public struct CronAddParams: Codable, Sendable {
    /// 任务名称
    public let name: String
    /// 代理 ID
    public let agentid: AnyCodable?
    /// 任务描述
    public let description: String?
    /// 是否启用
    public let enabled: Bool?
    /// 运行后是否删除
    public let deleteafterrun: Bool?
    /// 调度计划
    public let schedule: AnyCodable
    /// 会话目标
    public let sessiontarget: AnyCodable
    /// 唤醒模式
    public let wakemode: AnyCodable
    /// 任务数据
    public let payload: AnyCodable
    /// 隔离设置
    public let isolation: [String: AnyCodable]?

    /// 初始化定时任务添加参数
    public init(
        name: String,
        agentid: AnyCodable?,
        description: String?,
        enabled: Bool?,
        deleteafterrun: Bool?,
        schedule: AnyCodable,
        sessiontarget: AnyCodable,
        wakemode: AnyCodable,
        payload: AnyCodable,
        isolation: [String: AnyCodable]?
    ) {
        self.name = name
        self.agentid = agentid
        self.description = description
        self.enabled = enabled
        self.deleteafterrun = deleteafterrun
        self.schedule = schedule
        self.sessiontarget = sessiontarget
        self.wakemode = wakemode
        self.payload = payload
        self.isolation = isolation
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case name
        case agentid = "agentId"
        case description
        case enabled
        case deleteafterrun = "deleteAfterRun"
        case schedule
        case sessiontarget = "sessionTarget"
        case wakemode = "wakeMode"
        case payload
        case isolation
    }
}

/// 定时任务运行日志条目结构体
public struct CronRunLogEntry: Codable, Sendable {
    /// 时间戳
    public let ts: Int
    /// 任务 ID
    public let jobid: String
    /// 操作类型
    public let action: String
    /// 运行状态
    public let status: AnyCodable?
    /// 错误信息
    public let error: String?
    /// 运行摘要
    public let summary: String?
    /// 运行时间（毫秒）
    public let runatms: Int?
    /// 运行时长（毫秒）
    public let durationms: Int?
    /// 下次运行时间（毫秒）
    public let nextrunatms: Int?

    /// 初始化定时任务运行日志条目
    public init(
        ts: Int,
        jobid: String,
        action: String,
        status: AnyCodable?,
        error: String?,
        summary: String?,
        runatms: Int?,
        durationms: Int?,
        nextrunatms: Int?
    ) {
        self.ts = ts
        self.jobid = jobid
        self.action = action
        self.status = status
        self.error = error
        self.summary = summary
        self.runatms = runatms
        self.durationms = durationms
        self.nextrunatms = nextrunatms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case ts
        case jobid = "jobId"
        case action
        case status
        case error
        case summary
        case runatms = "runAtMs"
        case durationms = "durationMs"
        case nextrunatms = "nextRunAtMs"
    }
}

/// 日志尾部参数结构体
public struct LogsTailParams: Codable, Sendable {
    /// 游标位置
    public let cursor: Int?
    /// 结果数量限制
    public let limit: Int?
    /// 最大字节数
    public let maxbytes: Int?

    /// 初始化日志尾部参数
    public init(
        cursor: Int?,
        limit: Int?,
        maxbytes: Int?
    ) {
        self.cursor = cursor
        self.limit = limit
        self.maxbytes = maxbytes
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case cursor
        case limit
        case maxbytes = "maxBytes"
    }
}

/// 日志尾部结果结构体
public struct LogsTailResult: Codable, Sendable {
    /// 日志文件路径
    public let file: String
    /// 游标位置
    public let cursor: Int
    /// 文件大小
    public let size: Int
    /// 日志行列表
    public let lines: [String]
    /// 是否截断
    public let truncated: Bool?
    /// 是否重置
    public let reset: Bool?

    /// 初始化日志尾部结果
    public init(
        file: String,
        cursor: Int,
        size: Int,
        lines: [String],
        truncated: Bool?,
        reset: Bool?
    ) {
        self.file = file
        self.cursor = cursor
        self.size = size
        self.lines = lines
        self.truncated = truncated
        self.reset = reset
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case file
        case cursor
        case size
        case lines
        case truncated
        case reset
    }
}

/// 执行审批获取参数结构体
public struct ExecApprovalsGetParams: Codable, Sendable {
}

/// 执行审批设置参数结构体
public struct ExecApprovalsSetParams: Codable, Sendable {
    /// 审批文件内容
    public let file: [String: AnyCodable]
    /// 基础哈希值
    public let basehash: String?

    /// 初始化执行审批设置参数
    public init(
        file: [String: AnyCodable],
        basehash: String?
    ) {
        self.file = file
        self.basehash = basehash
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case file
        case basehash = "baseHash"
    }
}

/// 节点执行审批获取参数结构体
public struct ExecApprovalsNodeGetParams: Codable, Sendable {
    /// 节点 ID
    public let nodeid: String

    /// 初始化节点执行审批获取参数
    public init(
        nodeid: String
    ) {
        self.nodeid = nodeid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case nodeid = "nodeId"
    }
}

/// 节点执行审批设置参数结构体
public struct ExecApprovalsNodeSetParams: Codable, Sendable {
    /// 节点 ID
    public let nodeid: String
    /// 审批文件内容
    public let file: [String: AnyCodable]
    /// 基础哈希值
    public let basehash: String?

    /// 初始化节点执行审批设置参数
    public init(
        nodeid: String,
        file: [String: AnyCodable],
        basehash: String?
    ) {
        self.nodeid = nodeid
        self.file = file
        self.basehash = basehash
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case nodeid = "nodeId"
        case file
        case basehash = "baseHash"
    }
}

/// 执行审批快照结构体
public struct ExecApprovalsSnapshot: Codable, Sendable {
    /// 文件路径
    public let path: String
    /// 文件是否存在
    public let exists: Bool
    /// 文件哈希值
    public let hash: String
    /// 文件内容
    public let file: [String: AnyCodable]

    /// 初始化执行审批快照
    public init(
        path: String,
        exists: Bool,
        hash: String,
        file: [String: AnyCodable]
    ) {
        self.path = path
        self.exists = exists
        self.hash = hash
        self.file = file
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case path
        case exists
        case hash
        case file
    }
}

/// 执行审批请求参数结构体
public struct ExecApprovalRequestParams: Codable, Sendable {
    /// 请求 ID
    public let id: String?
    /// 命令内容
    public let command: String
    /// 工作目录
    public let cwd: AnyCodable?
    /// 执行主机
    public let host: AnyCodable?
    /// 安全设置
    public let security: AnyCodable?
    /// 询问设置
    public let ask: AnyCodable?
    /// 代理 ID
    public let agentid: AnyCodable?
    /// 解析路径
    public let resolvedpath: AnyCodable?
    /// 会话密钥
    public let sessionkey: AnyCodable?
    /// 超时时间（毫秒）
    public let timeoutms: Int?

    /// 初始化执行审批请求参数
    public init(
        id: String?,
        command: String,
        cwd: AnyCodable?,
        host: AnyCodable?,
        security: AnyCodable?,
        ask: AnyCodable?,
        agentid: AnyCodable?,
        resolvedpath: AnyCodable?,
        sessionkey: AnyCodable?,
        timeoutms: Int?
    ) {
        self.id = id
        self.command = command
        self.cwd = cwd
        self.host = host
        self.security = security
        self.ask = ask
        self.agentid = agentid
        self.resolvedpath = resolvedpath
        self.sessionkey = sessionkey
        self.timeoutms = timeoutms
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case command
        case cwd
        case host
        case security
        case ask
        case agentid = "agentId"
        case resolvedpath = "resolvedPath"
        case sessionkey = "sessionKey"
        case timeoutms = "timeoutMs"
    }
}

/// 执行审批解析参数结构体
public struct ExecApprovalResolveParams: Codable, Sendable {
    /// 请求 ID
    public let id: String
    /// 审批决策
    public let decision: String

    /// 初始化执行审批解析参数
    public init(
        id: String,
        decision: String
    ) {
        self.id = id
        self.decision = decision
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case id
        case decision
    }
}

/// 设备配对列表参数结构体
public struct DevicePairListParams: Codable, Sendable {
}

/// 设备配对批准参数结构体
public struct DevicePairApproveParams: Codable, Sendable {
    /// 请求 ID
    public let requestid: String

    /// 初始化设备配对批准参数
    public init(
        requestid: String
    ) {
        self.requestid = requestid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case requestid = "requestId"
    }
}

/// 设备配对拒绝参数结构体
public struct DevicePairRejectParams: Codable, Sendable {
    /// 请求 ID
    public let requestid: String

    /// 初始化设备配对拒绝参数
    public init(
        requestid: String
    ) {
        self.requestid = requestid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case requestid = "requestId"
    }
}

/// 设备令牌轮换参数结构体
public struct DeviceTokenRotateParams: Codable, Sendable {
    /// 设备 ID
    public let deviceid: String
    /// 角色
    public let role: String
    /// 作用域
    public let scopes: [String]?

    /// 初始化设备令牌轮换参数
    public init(
        deviceid: String,
        role: String,
        scopes: [String]?
    ) {
        self.deviceid = deviceid
        self.role = role
        self.scopes = scopes
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case deviceid = "deviceId"
        case role
        case scopes
    }
}

/// 设备令牌撤销参数结构体
public struct DeviceTokenRevokeParams: Codable, Sendable {
    /// 设备 ID
    public let deviceid: String
    /// 角色
    public let role: String

    /// 初始化设备令牌撤销参数
    public init(
        deviceid: String,
        role: String
    ) {
        self.deviceid = deviceid
        self.role = role
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case deviceid = "deviceId"
        case role
    }
}

/// 设备配对请求事件结构体
public struct DevicePairRequestedEvent: Codable, Sendable {
    /// 请求 ID
    public let requestid: String
    /// 设备 ID
    public let deviceid: String
    /// 公钥
    public let publickey: String
    /// 显示名称
    public let displayname: String?
    /// 平台
    public let platform: String?
    /// 客户端 ID
    public let clientid: String?
    /// 客户端模式
    public let clientmode: String?
    /// 角色
    public let role: String?
    /// 角色列表
    public let roles: [String]?
    /// 作用域列表
    public let scopes: [String]?
    /// 远程 IP
    public let remoteip: String?
    /// 是否静默
    public let silent: Bool?
    /// 是否修复
    public let isrepair: Bool?
    /// 时间戳
    public let ts: Int

    /// 初始化设备配对请求事件
    public init(
        requestid: String,
        deviceid: String,
        publickey: String,
        displayname: String?,
        platform: String?,
        clientid: String?,
        clientmode: String?,
        role: String?,
        roles: [String]?,
        scopes: [String]?,
        remoteip: String?,
        silent: Bool?,
        isrepair: Bool?,
        ts: Int
    ) {
        self.requestid = requestid
        self.deviceid = deviceid
        self.publickey = publickey
        self.displayname = displayname
        self.platform = platform
        self.clientid = clientid
        self.clientmode = clientmode
        self.role = role
        self.roles = roles
        self.scopes = scopes
        self.remoteip = remoteip
        self.silent = silent
        self.isrepair = isrepair
        self.ts = ts
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case requestid = "requestId"
        case deviceid = "deviceId"
        case publickey = "publicKey"
        case displayname = "displayName"
        case platform
        case clientid = "clientId"
        case clientmode = "clientMode"
        case role
        case roles
        case scopes
        case remoteip = "remoteIp"
        case silent
        case isrepair = "isRepair"
        case ts
    }
}

/// 设备配对解析事件结构体
public struct DevicePairResolvedEvent: Codable, Sendable {
    /// 请求 ID
    public let requestid: String
    /// 设备 ID
    public let deviceid: String
    /// 决策结果
    public let decision: String
    /// 时间戳
    public let ts: Int

    /// 初始化设备配对解析事件
    public init(
        requestid: String,
        deviceid: String,
        decision: String,
        ts: Int
    ) {
        self.requestid = requestid
        self.deviceid = deviceid
        self.decision = decision
        self.ts = ts
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case requestid = "requestId"
        case deviceid = "deviceId"
        case decision
        case ts
    }
}

/// 聊天历史参数结构体
public struct ChatHistoryParams: Codable, Sendable {
    /// 会话密钥
    public let sessionkey: String
    /// 结果数量限制
    public let limit: Int?

    /// 初始化聊天历史参数
    public init(
        sessionkey: String,
        limit: Int?
    ) {
        self.sessionkey = sessionkey
        self.limit = limit
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case sessionkey = "sessionKey"
        case limit
    }
}

/// 聊天发送参数结构体
public struct ChatSendParams: Codable, Sendable {
    /// 会话密钥
    public let sessionkey: String
    /// 消息内容
    public let message: String
    /// 思考内容
    public let thinking: String?
    /// 是否发送
    public let deliver: Bool?
    /// 附件列表
    public let attachments: [AnyCodable]?
    /// 超时时间（毫秒）
    public let timeoutms: Int?
    /// 幂等性键
    public let idempotencykey: String

    /// 初始化聊天发送参数
    public init(
        sessionkey: String,
        message: String,
        thinking: String?,
        deliver: Bool?,
        attachments: [AnyCodable]?,
        timeoutms: Int?,
        idempotencykey: String
    ) {
        self.sessionkey = sessionkey
        self.message = message
        self.thinking = thinking
        self.deliver = deliver
        self.attachments = attachments
        self.timeoutms = timeoutms
        self.idempotencykey = idempotencykey
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case sessionkey = "sessionKey"
        case message
        case thinking
        case deliver
        case attachments
        case timeoutms = "timeoutMs"
        case idempotencykey = "idempotencyKey"
    }
}

/// 聊天中止参数结构体
public struct ChatAbortParams: Codable, Sendable {
    /// 会话密钥
    public let sessionkey: String
    /// 运行 ID
    public let runid: String?

    /// 初始化聊天中止参数
    public init(
        sessionkey: String,
        runid: String?
    ) {
        self.sessionkey = sessionkey
        self.runid = runid
    }
    /// 编码键映射
    private enum CodingKeys: String, CodingKey {
        case sessionkey = "sessionKey"
        case runid = "runId"
    }
}

public struct ChatInjectParams: Codable, Sendable {
    public let sessionkey: String
    public let message: String
    public let label: String?

    public init(
        sessionkey: String,
        message: String,
        label: String?
    ) {
        self.sessionkey = sessionkey
        self.message = message
        self.label = label
    }
    private enum CodingKeys: String, CodingKey {
        case sessionkey = "sessionKey"
        case message
        case label
    }
}

public struct ChatEvent: Codable, Sendable {
    public let runid: String
    public let sessionkey: String
    public let seq: Int
    public let state: AnyCodable
    public let message: AnyCodable?
    public let errormessage: String?
    public let usage: AnyCodable?
    public let stopreason: String?

    public init(
        runid: String,
        sessionkey: String,
        seq: Int,
        state: AnyCodable,
        message: AnyCodable?,
        errormessage: String?,
        usage: AnyCodable?,
        stopreason: String?
    ) {
        self.runid = runid
        self.sessionkey = sessionkey
        self.seq = seq
        self.state = state
        self.message = message
        self.errormessage = errormessage
        self.usage = usage
        self.stopreason = stopreason
    }
    private enum CodingKeys: String, CodingKey {
        case runid = "runId"
        case sessionkey = "sessionKey"
        case seq
        case state
        case message
        case errormessage = "errorMessage"
        case usage
        case stopreason = "stopReason"
    }
}

public struct UpdateRunParams: Codable, Sendable {
    public let sessionkey: String?
    public let note: String?
    public let restartdelayms: Int?
    public let timeoutms: Int?

    public init(
        sessionkey: String?,
        note: String?,
        restartdelayms: Int?,
        timeoutms: Int?
    ) {
        self.sessionkey = sessionkey
        self.note = note
        self.restartdelayms = restartdelayms
        self.timeoutms = timeoutms
    }
    private enum CodingKeys: String, CodingKey {
        case sessionkey = "sessionKey"
        case note
        case restartdelayms = "restartDelayMs"
        case timeoutms = "timeoutMs"
    }
}

public struct TickEvent: Codable, Sendable {
    public let ts: Int

    public init(
        ts: Int
    ) {
        self.ts = ts
    }
    private enum CodingKeys: String, CodingKey {
        case ts
    }
}

public struct ShutdownEvent: Codable, Sendable {
    public let reason: String
    public let restartexpectedms: Int?

    public init(
        reason: String,
        restartexpectedms: Int?
    ) {
        self.reason = reason
        self.restartexpectedms = restartexpectedms
    }
    private enum CodingKeys: String, CodingKey {
        case reason
        case restartexpectedms = "restartExpectedMs"
    }
}

public enum GatewayFrame: Codable, Sendable {
    case req(RequestFrame)
    case res(ResponseFrame)
    case event(EventFrame)
    case unknown(type: String, raw: [String: AnyCodable])

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: CodingKeys.self)
        let type = try typeContainer.decode(String.self, forKey: .type)
        switch type {
        case "req":
            self = .req(try RequestFrame(from: decoder))
        case "res":
            self = .res(try ResponseFrame(from: decoder))
        case "event":
            self = .event(try EventFrame(from: decoder))
        default:
            let container = try decoder.singleValueContainer()
            let raw = try container.decode([String: AnyCodable].self)
            self = .unknown(type: type, raw: raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .req(let v): try v.encode(to: encoder)
        case .res(let v): try v.encode(to: encoder)
        case .event(let v): try v.encode(to: encoder)
        case .unknown(_, let raw):
            var container = encoder.singleValueContainer()
            try container.encode(raw)
        }
    }

}
