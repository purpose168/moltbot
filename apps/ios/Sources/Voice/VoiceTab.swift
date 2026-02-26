import SwiftUI

struct VoiceTab: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @AppStorage("voiceWake.enabled") private var voiceWakeEnabled: Bool = false
    @AppStorage("talk.enabled") private var talkEnabled: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("状态") {
                    LabeledContent("语音唤醒", value: self.voiceWakeEnabled ? "已启用" : "已禁用")
                    LabeledContent("监听器", value: self.voiceWake.isListening ? "正在监听" : "空闲")
                    Text(self.voiceWake.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("对话模式", value: self.talkEnabled ? "已启用" : "已禁用")
                }

                Section("说明") {
                    let triggers = self.voiceWake.activeTriggerWords
                    Group {
                        if triggers.isEmpty {
                            Text("在设置中添加唤醒词。")
                        } else if triggers.count == 1 {
                            Text("说“\(triggers[0]) …”来触发。")
                        } else if triggers.count == 2 {
                            Text("说“\(triggers[0]) …”或“\(triggers[1]) …”来触发。")
                        } else {
                            Text("说“\(triggers.joined(separator: " …”，“")) …”来触发。")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("语音")
            .onChange(of: self.voiceWakeEnabled) { _, newValue in
                self.appModel.setVoiceWakeEnabled(newValue)
            }
            .onChange(of: self.talkEnabled) { _, newValue in
                self.appModel.setTalkEnabled(newValue)
            }
        }
    }
}
