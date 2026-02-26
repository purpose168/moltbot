import Foundation

/// 向导选项结构体，用于表示向导中的可选项目
public struct WizardOption: Sendable {
    /// 选项的值
    public let value: AnyCodable?
    /// 选项的标签，用于显示
    public let label: String
    /// 选项的提示信息，可选
    public let hint: String?

    /// 初始化向导选项
    /// - Parameters:
    ///   - value: 选项的值
    ///   - label: 选项的标签
    ///   - hint: 选项的提示信息
    public init(value: AnyCodable?, label: String, hint: String?) {
        self.value = value
        self.label = label
        self.hint = hint
    }
}

/// 解码向导步骤
/// - Parameter raw: 原始的向导步骤数据
/// - Returns: 解码后的向导步骤对象，如果解码失败则返回nil
public func decodeWizardStep(_ raw: [String: AnyCodable]?) -> WizardStep? {
    guard let raw else { return nil }
    do {
        let data = try JSONEncoder().encode(raw)
        return try JSONDecoder().decode(WizardStep.self, from: data)
    } catch {
        return nil
    }
}

/// 解析向导选项列表
/// - Parameter raw: 原始的向导选项数据数组
/// - Returns: 解析后的向导选项数组
public func parseWizardOptions(_ raw: [[String: AnyCodable]]?) -> [WizardOption] {
    guard let raw else { return [] }
    return raw.map { entry in
        let value = entry["value"]
        let label = (entry["label"]?.value as? String) ?? ""
        let hint = entry["hint"]?.value as? String
        return WizardOption(value: value, label: label, hint: hint)
    }
}

/// 将向导状态值转换为字符串
/// - Parameter value: 状态值
/// - Returns: 处理后的字符串，去除空白并转为小写
public func wizardStatusString(_ value: AnyCodable?) -> String? {
    (value?.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

/// 获取向导步骤类型
/// - Parameter step: 向导步骤对象
/// - Returns: 步骤类型字符串
public func wizardStepType(_ step: WizardStep) -> String {
    (step.type.value as? String) ?? ""
}

/// 将AnyCodable值转换为字符串
/// - Parameter value: AnyCodable值
/// - Returns: 转换后的字符串
public func anyCodableString(_ value: AnyCodable?) -> String {
    switch value?.value {
    case let string as String:
        string
    case let int as Int:
        String(int)
    case let double as Double:
        String(double)
    case let bool as Bool:
        bool ? "true" : "false"
    default:
        ""
    }
}

/// 将AnyCodable值转换为布尔值
/// - Parameter value: AnyCodable值
/// - Returns: 转换后的布尔值
public func anyCodableBool(_ value: AnyCodable?) -> Bool {
    switch value?.value {
    case let bool as Bool:
        return bool
    case let int as Int:
        return int != 0
    case let double as Double:
        return double != 0
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "true" || trimmed == "1" || trimmed == "yes"
    default:
        return false
    }
}

/// 将AnyCodable值转换为AnyCodable数组
/// - Parameter value: AnyCodable值
/// - Returns: 转换后的AnyCodable数组
public func anyCodableArray(_ value: AnyCodable?) -> [AnyCodable] {
    switch value?.value {
    case let arr as [AnyCodable]:
        return arr
    case let arr as [Any]:
        return arr.map { AnyCodable($0) }
    default:
        return []
    }
}

/// 比较两个AnyCodable值是否相等
/// - Parameters:
///   - lhs: 左侧值
///   - rhs: 右侧值
/// - Returns: 是否相等
public func anyCodableEqual(_ lhs: AnyCodable?, _ rhs: AnyCodable?) -> Bool {
    switch (lhs?.value, rhs?.value) {
    case let (l as String, r as String):
        l == r
    case let (l as Int, r as Int):
        l == r
    case let (l as Double, r as Double):
        l == r
    case let (l as Bool, r as Bool):
        l == r
    case let (l as String, r as Int):
        l == String(r)
    case let (l as Int, r as String):
        String(l) == r
    case let (l as String, r as Double):
        l == String(r)
    case let (l as Double, r as String):
        String(l) == r
    default:
        false
    }
}
