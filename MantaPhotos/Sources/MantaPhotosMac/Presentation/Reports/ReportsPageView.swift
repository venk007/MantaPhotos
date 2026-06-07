import SwiftUI

struct ReportsPageView: View {
    var body: some View {
        ContentUnavailableView(
            "Reports",
            systemImage: "chart.bar.doc.horizontal",
            description: Text("Report shell is ready for P2 statistics.")
        )
    }
}

struct TimelinePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Timeline",
            systemImage: "calendar",
            description: Text("Timeline navigation is reserved in P0.")
        )
    }
}
