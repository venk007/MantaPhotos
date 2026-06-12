import SwiftUI

/// 右上角多任务状态与控制（液态玻璃弹层）。
/// 同时展示五类分析任务的进度，可分别开始 / 暂停 / 继续 / 停止。
struct MultiTaskStatusView: View {
    @Environment(AppState.self) private var appState
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                if activeCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(activeCount)")
                        .font(.caption.monospacedDigit())
                } else {
                    Image(systemName: "checklist")
                }
            }
        }
        .buttonStyle(.borderless)
        .help("分析任务")
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            popoverContent
                .frame(width: 320)
                .padding(14)
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
