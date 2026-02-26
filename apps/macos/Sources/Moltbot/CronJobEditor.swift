import MoltbotProtocol
import Observation
import SwiftUI

/// Cron 作业编辑器
/// 
/// 用于创建和编辑 Cron 作业的 SwiftUI 视图
struct CronJobEditor: View {
    /// 作业（编辑模式下）
    let job: CronJob?
    /// 是否正在保存
    @Binding var isSaving: Bool
    /// 错误信息
    @Binding var error: String?
    /// 通道存储
    @Bindable var channelsStore: ChannelsStore
    /// 取消回调
    let onCancel: () -> Void
    /// 保存回调
    let onSave: ([String: AnyCodable]) -> Void

    /// 标签列宽度
    let labelColumnWidth: CGFloat = 160
    /// 介绍文本
    static let introText =
        "创建一个通过网关唤醒 clawd 的调度。 "
            + "对于代理回合，使用隔离会话，使您的主聊天保持干净。"
    /// 会话目标说明
    static let sessionTargetNote =
        "主作业会将系统事件发布到当前的主会话中。 "
            + "隔离作业在专用会话中运行 clawd，并可以将结果传递到（WhatsApp/Telegram/Discord 等）。"
    /// 调度类型说明
    static let scheduleKindNote =
        """At" 运行一次，"Every" 按持续时间重复，"Cron" 使用 5 字段的 Unix 表达式。"
    /// 隔离有效载荷说明
    static let isolatedPayloadNote =
        "隔离作业始终运行代理回合。结果可以传递到通道， "
            + "简短摘要会发布回您的主聊天。"
    /// 主有效载荷说明
    static let mainPayloadNote =
        "系统事件被注入到当前的主会话中。代理回合需要隔离会话目标。"
    /// 主会话摘要说明
    static let mainSummaryNote =
        "控制将完成摘要发布回主会话时使用的标签。"

    /// 名称
    @State var name: String = ""
    /// 描述
    @State var description: String = ""
    /// 代理 ID
    @State var agentId: String = ""
    /// 是否启用
    @State var enabled: Bool = true
    /// 会话目标
    @State var sessionTarget: CronSessionTarget = .main
    /// 唤醒模式
    @State var wakeMode: CronWakeMode = .nextHeartbeat
    /// 运行后删除
    @State var deleteAfterRun: Bool = false

    /// 调度类型枚举
    enum ScheduleKind: String, CaseIterable, Identifiable { case at, every, cron; var id: String { rawValue } }
    /// 调度类型
    @State var scheduleKind: ScheduleKind = .every
    /// 运行时间
    @State var atDate: Date = .init().addingTimeInterval(60 * 5)
    /// 每隔持续时间
    @State var everyText: String = "1h"
    /// Cron 表达式
    @State var cronExpr: String = "0 9 * * 3"
    /// Cron 时区
    @State var cronTz: String = ""

    /// 有效载荷类型枚举
    enum PayloadKind: String, CaseIterable, Identifiable { case systemEvent, agentTurn; var id: String { rawValue } }
    /// 有效载荷类型
    @State var payloadKind: PayloadKind = .systemEvent
    /// 系统事件文本
    @State var systemEventText: String = ""
    /// 代理消息
    @State var agentMessage: String = ""
    /// 是否传递
    @State var deliver: Bool = false
    /// 通道
    @State var channel: String = "last"
    /// 目标
    @State var to: String = ""
    /// 思考
    @State var thinking: String = ""
    /// 超时秒数
    @State var timeoutSeconds: String = ""
    /// 尽力传递
    @State var bestEffortDeliver: Bool = false
    /// 发布前缀
    @State var postPrefix: String = "Cron"

    /// 通道选项
    var channelOptions: [String] {
        let ordered = self.channelsStore.orderedChannelIds()
        var options = ["last"] + ordered
        let trimmed = self.channel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !options.contains(trimmed) {
            options.append(trimmed)
        }
        var seen = Set<String>()
        return options.filter { seen.insert($0).inserted }
    }

    /// 通道标签
    /// - Parameter id: 通道 ID
    /// - Returns: 通道标签
    func channelLabel(for id: String) -> String {
        if id == "last" { return "last" }
        return self.channelsStore.resolveChannelLabel(id)
    }

    /// 视图主体
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(self.job == nil ? "新建 cron 作业" : "编辑 cron 作业")
                    .font(.title3.weight(.semibold))
                Text(Self.introText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("基础信息") {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                            GridRow {
                                self.gridLabel("名称")
                                TextField("必填（例如 "每日摘要"）", text: self.$name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                self.gridLabel("描述")
                                TextField("可选说明", text: self.$description)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                self.gridLabel("代理 ID")
                                TextField("可选（默认代理）", text: self.$agentId)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                self.gridLabel("启用")
                                Toggle("", isOn: self.$enabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            GridRow {
                                self.gridLabel("会话目标")
                                Picker("", selection: self.$sessionTarget) {
                                    Text("main").tag(CronSessionTarget.main)
                                    Text("isolated").tag(CronSessionTarget.isolated)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            GridRow {
                                self.gridLabel("唤醒模式")
                                Picker("", selection: self.$wakeMode) {
                                    Text("next-heartbeat").tag(CronWakeMode.nextHeartbeat)
                                    Text("now").tag(CronWakeMode.now)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            GridRow {
                                Color.clear
                                    .frame(width: self.labelColumnWidth, height: 1)
                                Text(
                                    Self.sessionTargetNote)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    GroupBox("调度") {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                            GridRow {
                                self.gridLabel("类型")
                                Picker("", selection: self.$scheduleKind) {
                                    Text("at").tag(ScheduleKind.at)
                                    Text("every").tag(ScheduleKind.every)
                                    Text("cron").tag(ScheduleKind.cron)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                Color.clear
                                    .frame(width: self.labelColumnWidth, height: 1)
                                Text(
                                    Self.scheduleKindNote)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            switch self.scheduleKind {
                            case .at:
                                GridRow {
                                    self.gridLabel("时间")
                                    DatePicker(
                                        "",
                                        selection: self.$atDate,
                                        displayedComponents: [.date, .hourAndMinute])
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                GridRow {
                                    self.gridLabel("自动删除")
                                    Toggle("成功运行后删除", isOn: self.$deleteAfterRun)
                                        .toggleStyle(.switch)
                                }
                            case .every:
                                GridRow {
                                    self.gridLabel("每隔")
                                    TextField("10m, 1h, 1d", text: self.$everyText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                            case .cron:
                                GridRow {
                                    self.gridLabel("表达式")
                                    TextField("例如 0 9 * * 3", text: self.$cronExpr)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    self.gridLabel("时区")
                                    TextField("可选（例如 America/Los_Angeles）", text: self.$cronTz)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }

                    GroupBox("有效载荷") {
                        VStack(alignment: .leading, spacing: 10) {
                            if self.sessionTarget == .isolated {
                                Text(Self.isolatedPayloadNote)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                self.agentTurnEditor
                            } else {
                                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                                    GridRow {
                                        self.gridLabel("类型")
                                        Picker("", selection: self.$payloadKind) {
                                            Text("systemEvent").tag(PayloadKind.systemEvent)
                                            Text("agentTurn").tag(PayloadKind.agentTurn)
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.segmented)
                                        .frame(maxWidth: .infinity)
                                    }
                                    GridRow {
                                        Color.clear
                                            .frame(width: self.labelColumnWidth, height: 1)
                                        Text(
                                            Self.mainPayloadNote)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }

                                switch self.payloadKind {
                                case .systemEvent:
                                    TextField("系统事件文本", text: self.$systemEventText, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                        .lineLimit(3...7)
                                        .frame(maxWidth: .infinity)
                                case .agentTurn:
                                    self.agentTurnEditor
                                }
                            }
                        }
                    }

                    if self.sessionTarget == .isolated {
                        GroupBox("主会话摘要") {
                            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                                GridRow {
                                    self.gridLabel("前缀")
                                    TextField("Cron", text: self.$postPrefix)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Color.clear
                                        .frame(width: self.labelColumnWidth, height: 1)
                                    Text(
                                        Self.mainSummaryNote)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("取消") { self.onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                Spacer()
                Button {
                    self.save()
                } label: {
                    if self.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(self.isSaving)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 640)
        .onAppear { self.hydrateFromJob() }
        .onChange(of: self.payloadKind) { _, newValue in
            if newValue == .agentTurn, self.sessionTarget == .main {
                self.sessionTarget = .isolated
            }
        }
        .onChange(of: self.sessionTarget) { _, newValue in
            if newValue == .isolated {
                self.payloadKind = .agentTurn
            } else if newValue == .main, self.payloadKind == .agentTurn {
                self.payloadKind = .systemEvent
            }
        }
    }

    /// 代理回合编辑器
    var agentTurnEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    self.gridLabel("消息")
                    TextField("clawd 应该做什么？", text: self.$agentMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...7)
                        .frame(maxWidth: .infinity)
                }
                GridRow {
                    self.gridLabel("思考")
                    TextField("可选（例如 low）", text: self.$thinking)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
                GridRow {
                    self.gridLabel("超时")
                    TextField("秒数（可选）", text: self.$timeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180, alignment: .leading)
                }
                GridRow {
                    self.gridLabel("传递")
                    Toggle("将结果传递到通道", isOn: self.$deliver)
                        .toggleStyle(.switch)
                }
            }

            if self.deliver {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        self.gridLabel("通道")
                        Picker("", selection: self.$channel) {
                            ForEach(self.channelOptions, id: \.self) { channel in
                                Text(self.channelLabel(for: channel)).tag(channel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        self.gridLabel("目标")
                        TextField("可选覆盖（电话号码 / 聊天 ID / Discord 频道）", text: self.$to)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                    GridRow {
                        self.gridLabel("尽力而为")
                        Toggle("即使传递失败也不要使作业失败", isOn: self.$bestEffortDeliver)
                            .toggleStyle(.switch)
                    }
                }
            }
        }
    }
}
