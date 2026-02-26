import SwiftUI

/// 菜单使用情况头部视图
/// 显示使用情况统计信息的头部组件
struct MenuUsageHeaderView: View {
    let count: Int

    private let paddingTop: CGFloat = 8
    private let paddingBottom: CGFloat = 6
    private let paddingTrailing: CGFloat = 10
    private let paddingLeading: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("使用情况")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, self.paddingTop)
        .padding(.bottom, self.paddingBottom)
        .padding(.leading, self.paddingLeading)
        .padding(.trailing, self.paddingTrailing)
        .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
        .transaction { txn in txn.animation = nil }
    }

    /// 副标题文本
    private var subtitle: String {
        if self.count == 1 { return "1 个提供商" }
        return "\(self.count) 个提供商"
    }
}
