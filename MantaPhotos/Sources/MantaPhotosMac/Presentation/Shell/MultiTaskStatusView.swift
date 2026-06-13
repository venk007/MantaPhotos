import SwiftUI

/// 顶部右侧多任务状态与控制（液态玻璃弹层）。
///
/// 仅在有分析任务运行时才以一枚独立的液态玻璃胶囊按钮出现（否则渲染为
/// `EmptyView`，顶部不留空壳图标）——点击展开任务详情与进度，可分别
/// 开始 / 暂停 / 继续 / 停止。
struct MultiTaskStatusView: View {
    @Environment(AppState.self) private var appState
    @State private var showsPopover = false

    var body: some View {
        if activeCount > 0 {
            Button {
                showsPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(activeCount)")
                        .font(.caption.monospacedDigit())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.pressableGlass)
            .liquidGlassBackground(material: .hudWindow, in: Capsule())
            .glassHoverHighlight(in: Capsule())
            .overlay {
                Capsule().strokeBorder(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
            .help("分析任务")
            .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
                popoverContent
                    .frame(width: 320)
                    .padding(14)
            }
        }
    }

    private var activeCount: Int { appState.tasks.activeKinds.count }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分析任务")
                .font(.headline)

            ForEach(AnalysisKind.allCases) { kind in
                taskRow(kind)
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ kind: AnalysisKind) -> some View {
        let progress = appState.tasks.progress(for: kind)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: kind.iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(kind.fallbackName)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(statusText(progress))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                controls(kind, progress)
            }
            if progress.isActive, progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func controls(_ kind: AnalysisKind, _ progress: TaskProgress) -> some View {
        HStack(spacing: 6) {
            switch progress.status {
            case .running:
                iconButton("pause.fill") { appState.tasks.pause(kind) }
                iconButton("stop.fill") { appState.tasks.stop(kind) }
            case .paused:
                iconButton("play.fill") { appState.tasks.resume(kind) }
                iconButton("stop.fill") { appState.tasks.stop(kind) }
            case .queued, .stopping:
                iconButton("stop.fill") { appState.tasks.stop(kind) }
            case .idle, .completed, .failed:
                iconButton("play.fill") { appState.tasks.start(kind) }
            }
        }
        .buttonStyle(.borderless)
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
        }
    }

    private func statusText(_ progress: TaskProgress) -> String {
        switch progress.status {
        case .idle: "未开始"
        case .queued: "排队中"
        case .running: "\(progress.completed)/\(progress.total)"
        case .paused: "已暂停 \(progress.completed)/\(progress.total)"
        case .stopping: "停止中"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }
}
