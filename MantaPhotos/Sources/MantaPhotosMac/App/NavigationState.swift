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
    var gridLevel: GridLevel = .columns4
    var badgeMetric: BadgeMetric = .aesthetic
    var isFindOverlayPresented = false
    var isSidebarExpanded = true

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
