import SwiftUI

/// 配置模式表单视图，根据配置模式动态渲染表单控件
struct ConfigSchemaForm: View {
    @Bindable var store: ChannelsStore  // 通道配置存储
    let schema: ConfigSchemaNode        // 配置模式节点
    let path: ConfigPath                // 配置路径

    var body: some View {
        // 渲染配置节点
        self.renderNode(self.schema, path: self.path)
    }

    /// 根据配置模式节点类型渲染对应的表单控件
    private func renderNode(_ schema: ConfigSchemaNode, path: ConfigPath) -> AnyView {
        // 获取存储的配置值
        let storedValue = self.store.configValue(at: path)
        // 使用存储值或默认值
        let value = storedValue ?? schema.explicitDefault
        // 获取标签文本，优先使用UI提示中的标签，否则使用模式标题
        let label = hintForPath(path, hints: store.configUiHints)?.label ?? schema.title
        // 获取帮助文本，优先使用UI提示中的帮助信息，否则使用模式描述
        let help = hintForPath(path, hints: store.configUiHints)?.help ?? schema.description
        // 确定使用的变体数组
        let variants = schema.anyOf.isEmpty ? schema.oneOf : schema.anyOf

        // 处理变体情况
        if !variants.isEmpty {
            // 过滤掉空值模式
            let nonNull = variants.filter { !$0.isNullSchema }
            // 如果只有一个非空变体，直接渲染该变体
            if nonNull.count == 1, let only = nonNull.first {
                return self.renderNode(only, path: path)
            }
            // 提取所有字面量值
            let literals = nonNull.compactMap(\.literalValue)
            // 如果所有变体都是字面量值，渲染为选择器
            if !literals.isEmpty, literals.count == nonNull.count {
                return AnyView(
                    VStack(alignment: .leading, spacing: 6) {
                        // 显示标签
                        if let label { Text(label).font(.callout.weight(.semibold)) }
                        // 显示帮助文本
                        if let help {
                            Text(help)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // 渲染选择器
                        Picker(
                            "",
                            selection: self.enumBinding(
                                path,
                                options: literals,
                                defaultValue: schema.explicitDefault))
                        {
                            Text("Select…").tag(-1)
                            ForEach(literals.indices, id: \ .self) { index in
                                Text(String(describing: literals[index])).tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                    })
            }
        }

        // 根据模式类型渲染不同的表单控件
        switch schema.schemaType {
        case "object":
            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    // 显示标签
                    if let label { Text(label).font(.callout.weight(.semibold)) }
                    // 显示帮助文本
                    if let help {
                        Text(help)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let properties = schema.properties
                    // 对属性按键排序，优先按UI提示中的顺序，其次按字母顺序
                    let sortedKeys = properties.keys.sorted { lhs, rhs in
                        let orderA = hintForPath(path + [.key(lhs)], hints: store.configUiHints)?.order ?? 0
                        let orderB = hintForPath(path + [.key(rhs)], hints: store.configUiHints)?.order ?? 0
                        if orderA != orderB { return orderA < orderB }
                        return lhs < rhs
                    }
                    // 渲染每个属性
                    ForEach(sortedKeys, id: \ .self) { key in
                        if let child = properties[key] {
                            self.renderNode(child, path: path + [.key(key)])
                        }
                    }
                    // 渲染额外属性
                    if schema.allowsAdditionalProperties {
                        self.renderAdditionalProperties(schema, path: path, value: value)
                    }
                })
        case "array":
            // 渲染数组类型
            return AnyView(self.renderArray(schema, path: path, value: value, label: label, help: help))
        case "boolean":
            // 渲染布尔类型（开关）
            return AnyView(
                Toggle(isOn: self.boolBinding(path, defaultValue: schema.explicitDefault as? Bool)) {
                    if let label { Text(label) } else { Text("Enabled") }
                }
                .help(help ?? ""))
        case "number", "integer":
            // 渲染数字类型
            return AnyView(self.renderNumberField(schema, path: path, label: label, help: help))
        case "string":
            // 渲染字符串类型
            return AnyView(self.renderStringField(schema, path: path, label: label, help: help))
        default:
            // 处理不支持的类型
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    if let label { Text(label).font(.callout.weight(.semibold)) }
                    Text("Unsupported field type.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                })
        }
    }

    /// 渲染字符串类型的表单字段
    @ViewBuilder
    private func renderStringField(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        label: String?,
        help: String?) -> some View
    {
        // 获取UI提示
        let hint = hintForPath(path, hints: store.configUiHints)
        // 获取占位符文本
        let placeholder = hint?.placeholder ?? ""
        // 确定是否为敏感字段
        let sensitive = hint?.sensitive ?? isSensitivePath(path)
        // 获取默认值
        let defaultValue = schema.explicitDefault as? String
        VStack(alignment: .leading, spacing: 6) {
            // 显示标签
            if let label { Text(label).font(.callout.weight(.semibold)) }
            // 显示帮助文本
            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // 如果有枚举值，渲染为选择器
            if let options = schema.enumValues {
                Picker("", selection: self.enumBinding(path, options: options, defaultValue: schema.explicitDefault)) {
                    Text("Select…").tag(-1)
                    ForEach(options.indices, id: \ .self) { index in
                        Text(String(describing: options[index])).tag(index)
                    }
                }
                .pickerStyle(.menu)
            } else if sensitive {
                // 敏感字段使用安全文本框
                SecureField(placeholder, text: self.stringBinding(path, defaultValue: defaultValue))
                    .textFieldStyle(.roundedBorder)
            } else {
                // 普通文本字段
                TextField(placeholder, text: self.stringBinding(path, defaultValue: defaultValue))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    /// 渲染数字类型的表单字段
    @ViewBuilder
    private func renderNumberField(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        label: String?,
        help: String?) -> some View
    {
        // 获取默认值，支持Double和Int类型
        let defaultValue = (schema.explicitDefault as? Double)
            ?? (schema.explicitDefault as? Int).map(Double.init)
        VStack(alignment: .leading, spacing: 6) {
            // 显示标签
            if let label { Text(label).font(.callout.weight(.semibold)) }
            // 显示帮助文本
            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // 渲染数字输入框
            TextField(
                "",
                text: self.numberBinding(
                    path,
                    isInteger: schema.schemaType == "integer",
                    defaultValue: defaultValue))
                .textFieldStyle(.roundedBorder)
        }
    }

    /// 渲染数组类型的表单字段
    @ViewBuilder
    private func renderArray(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        value: Any?,
        label: String?,
        help: String?) -> some View
    {
        // 获取数组值
        let items = value as? [Any] ?? []
        // 获取数组元素的模式
        let itemSchema = schema.items
        VStack(alignment: .leading, spacing: 10) {
            // 显示标签
            if let label { Text(label).font(.callout.weight(.semibold)) }
            // 显示帮助文本
            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // 渲染每个数组元素
            ForEach(items.indices, id: \ .self) { index in
                HStack(alignment: .top, spacing: 8) {
                    if let itemSchema {
                        // 渲染数组元素
                        self.renderNode(itemSchema, path: path + [.index(index)])
                    } else {
                        // 简单显示数组元素值
                        Text(String(describing: items[index]))
                    }
                    // 删除按钮
                    Button("Remove") {
                        var next = items
                        next.remove(at: index)
                        self.store.updateConfigValue(path: path, value: next)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            // 添加按钮
            Button("Add") {
                var next = items
                if let itemSchema {
                    // 添加带有默认值的新元素
                    next.append(itemSchema.defaultValue)
                } else {
                    // 添加空字符串作为默认值
                    next.append("")
                }
                self.store.updateConfigValue(path: path, value: next)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// 渲染额外属性的表单字段
    @ViewBuilder
    private func renderAdditionalProperties(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        value: Any?) -> some View
    {
        // 检查是否有额外属性的模式
        if let additionalSchema = schema.additionalProperties {
            // 获取字典值
            let dict = value as? [String: Any] ?? [:]
            // 获取保留的属性键
            let reserved = Set(schema.properties.keys)
            // 过滤出额外的属性键并排序
            let extras = dict.keys.filter { !reserved.contains($0) }.sorted()

            VStack(alignment: .leading, spacing: 8) {
                // 显示标题
                Text("Extra entries")
                    .font(.callout.weight(.semibold))
                // 处理没有额外属性的情况
                if extras.isEmpty {
                    Text("No extra entries yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // 渲染每个额外属性
                    ForEach(extras, id: \ .self) { key in
                        let itemPath: ConfigPath = path + [.key(key)]
                        HStack(alignment: .top, spacing: 8) {
                            // 属性键输入框
                            TextField("Key", text: self.mapKeyBinding(path: path, key: key))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            // 属性值输入框
                            self.renderNode(additionalSchema, path: itemPath)
                            // 删除按钮
                            Button("Remove") {
                                var next = dict
                                next.removeValue(forKey: key)
                                self.store.updateConfigValue(path: path, value: next)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                // 添加按钮
                Button("Add") {
                    var next = dict
                    var index = 1
                    var key = "new-\(index)"
                    // 生成唯一的键名
                    while next[key] != nil {
                        index += 1
                        key = "new-\(index)"
                    }
                    // 添加带有默认值的新属性
                    next[key] = additionalSchema.defaultValue
                    self.store.updateConfigValue(path: path, value: next)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// 创建字符串类型的绑定
    private func stringBinding(_ path: ConfigPath, defaultValue: String?) -> Binding<String> {
        Binding(
            get: {
                // 获取存储的值或默认值
                if let value = store.configValue(at: path) as? String { return value }
                return defaultValue ?? ""
            },
            set: { newValue in
                // 去除首尾空白
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                // 如果为空则设置为nil，否则设置为修剪后的值
                self.store.updateConfigValue(path: path, value: trimmed.isEmpty ? nil : trimmed)
            })
    }

    /// 创建布尔类型的绑定
    private func boolBinding(_ path: ConfigPath, defaultValue: Bool?) -> Binding<Bool> {
        Binding(
            get: {
                // 获取存储的值或默认值
                if let value = store.configValue(at: path) as? Bool { return value }
                return defaultValue ?? false
            },
            set: { newValue in
                // 更新存储的值
                self.store.updateConfigValue(path: path, value: newValue)
            })
    }

    /// 创建数字类型的绑定
    private func numberBinding(
        _ path: ConfigPath,
        isInteger: Bool,
        defaultValue: Double?) -> Binding<String>
    {
        Binding(
            get: {
                // 获取存储的值
                if let value = store.configValue(at: path) { return String(describing: value) }
                // 如果没有存储值，使用默认值
                guard let defaultValue else { return "" }
                // 根据是否为整数类型格式化输出
                return isInteger ? String(Int(defaultValue)) : String(defaultValue)
            },
            set: { newValue in
                // 去除首尾空白
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // 如果为空则设置为nil
                    self.store.updateConfigValue(path: path, value: nil)
                } else if let value = Double(trimmed) {
                    // 根据是否为整数类型转换值
                    self.store.updateConfigValue(path: path, value: isInteger ? Int(value) : value)
                }
            })
    }

    /// 创建枚举类型的绑定
    private func enumBinding(
        _ path: ConfigPath,
        options: [Any],
        defaultValue: Any?) -> Binding<Int>
    {
        Binding(
            get: {
                // 获取存储的值或默认值
                let value = self.store.configValue(at: path) ?? defaultValue
                guard let value else { return -1 }
                // 查找值在选项中的索引
                return options.firstIndex { option in
                    String(describing: option) == String(describing: value)
                } ?? -1
            },
            set: { index in
                // 检查索引是否有效
                guard index >= 0, index < options.count else {
                    // 无效索引则设置为nil
                    self.store.updateConfigValue(path: path, value: nil)
                    return
                }
                // 设置选中的值
                self.store.updateConfigValue(path: path, value: options[index])
            })
    }

    /// 创建映射键的绑定
    private func mapKeyBinding(path: ConfigPath, key: String) -> Binding<String> {
        Binding(
            get: { key },
            set: { newValue in
                // 去除首尾空白
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                // 检查新值是否为空
                guard !trimmed.isEmpty else { return }
                // 检查新值是否与原键相同
                guard trimmed != key else { return }
                // 获取当前字典值
                let current = self.store.configValue(at: path) as? [String: Any] ?? [:]
                // 检查新键是否已存在
                guard current[trimmed] == nil else { return }
                // 创建新字典
                var next = current
                // 复制原键的值到新键
                next[trimmed] = current[key]
                // 删除原键
                next.removeValue(forKey: key)
                // 更新存储的值
                self.store.updateConfigValue(path: path, value: next)
            })
    }
}

/// 通道配置表单视图，为特定通道渲染配置表单
struct ChannelConfigForm: View {
    @Bindable var store: ChannelsStore  // 通道配置存储
    let channelId: String               // 通道ID

    var body: some View {
        if self.store.configSchemaLoading {
            // 配置模式加载中，显示进度指示器
            ProgressView().controlSize(.small)
        } else if let schema = store.channelConfigSchema(for: channelId) {
            // 配置模式加载成功，渲染配置表单
            ConfigSchemaForm(store: self.store, schema: schema, path: [.key("channels"), .key(self.channelId)])
        } else {
            // 配置模式不可用，显示错误信息
            Text("Schema unavailable for this channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
