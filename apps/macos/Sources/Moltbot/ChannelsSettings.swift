import AppKit
import SwiftUI

/// 频道设置视图
/// 用于展示和管理应用中的各种频道设置
struct ChannelsSettings: View {
    /// 频道项目结构体
    /// 符合Identifiable和Hashable协议，用于列表展示和标识
    struct ChannelItem: Identifiable, Hashable {
        let id: String              // 频道唯一标识符
        let title: String           // 频道标题
        let detailTitle: String     // 频道详细标题
        let systemImage: String     // 频道系统图标名称
        let sortOrder: Int          // 频道排序顺序
    }

    @Bindable var store: ChannelsStore     // 频道数据存储，使用Bindable包装以支持双向绑定
    @State var selectedChannel: ChannelItem? // 当前选中的频道项

    /// 初始化方法
    /// - Parameter store: 频道存储实例，默认为共享实例
    init(store: ChannelsStore = .shared) {
        self.store = store
    }
}
