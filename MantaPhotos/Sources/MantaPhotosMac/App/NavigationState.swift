import Foundation
import Observation
import SwiftUI

/// 全局导航与外观状态。
///
/// 职责单一：只负责路由、主题、语言、网格密度、角标指标，以及侧栏 / 查找浮层的呈现状态。
/// 从原 `AppState`（God Object）拆出，便于 P2 之后继续扩展时彼此互不干扰。
@MainActor
@Observable
final class NavigationState {
    var route: AppRoute = .photos
    var themeMode: ThemeMode = .system
    var appLanguage: AppLanguage = .system
    var gridLevel: GridLevel = .default
    var badgeMetric: BadgeMetric = .aesthetic
    var isFindOverlayPresented = false
    /// 侧栏当前展开状态：会随用户操作（点击折叠按钮、打开查找浮层等）随时变化。
    /// 初始值在 `AppState.loadSettings()` 中按 `sidebarShownOnLaunch` 设置。
    var isSidebarExpanded = false
    /// 设置项：App 启动时是否默认展开左侧快捷筛选抽屉。默认关闭——
    /// 启动即呈现完整照片网格，筛选是「按需唤出」的工具而非常驻界面。
    var sidebarShownOnLaunch = false
    /// 当前选用的向量模型 key（语义/相似搜索与向量索引任务用）。
    var vectorModelKey: String = EmbeddingProviderRegistry.defaultKey

    func adjustGridLevel(step: Int) {
        let levels = GridLevel.allCases
        guard let currentIndex = levels.firstIndex(of: gridLevel) else { return }
        let nextIndex = max(0, min(levels.count - 1, currentIndex + step))
        gridLevel = levels[nextIndex]
    }

    func localized(_ key: String) -> String {
        AppLocalizer.shared.localized(key, language: appLanguage)
    }
}
