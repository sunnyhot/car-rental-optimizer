import SwiftUI

struct VehicleReferenceProgressView: View {
    @ObservedObject var loader: VehicleReferenceBatchLoader
    let onRetry: () -> Void

    var body: some View {
        if loader.totalCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("车系资料 \(loader.processedCount)/\(loader.totalCount)")
                        .font(.caption.weight(.semibold))
                    Text("尺寸齐全 \(loader.completeCount) · 部分 \(loader.partialCount) · 暂缺 \(loader.missingCount) · 待重试 \(loader.deferredCount)")
                        .font(.caption2).foregroundStyle(WorkbenchStyle.muted)
                    Spacer()
                    if loader.needsMoreData && !loader.isLoading {
                        Button("重试缺失", action: onRetry).controlSize(.small)
                    }
                }
                if loader.isLoading {
                    ProgressView(value: Double(loader.processedCount), total: Double(loader.totalCount))
                        .accessibilityLabel("车型尺寸补全进度")
                }
                if let retry = loader.retryAfter, loader.deferredCount > 0 {
                    Text("资料源限流，\(AppDateRules.formatRequestDateTime(retry)) 后可重试；已获得的数据已缓存。")
                        .font(.caption2).foregroundStyle(WorkbenchStyle.riskAmber)
                }
                Text(loader.isLoading ? "报价已可查看，正在后台补齐全部结果的车型资料。" : "尺寸齐全指长宽高和轴距；来源未提供的字段不推算，具体年款配置仍需复核。")
                    .font(.caption2).foregroundStyle(WorkbenchStyle.muted)
            }
            .padding(10)
            .background(WorkbenchStyle.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
