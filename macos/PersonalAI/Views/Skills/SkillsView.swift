import SwiftUI

struct SkillsView: View {
    var body: some View {
        DetailPage(title: "Skills", subtitle: "Capabilities Personal AI can use to help you.") {
            EmptyStateView(
                icon: "hammer",
                title: "No skills enabled",
                description: "Skills will appear here when capabilities are connected to Personal AI."
            )
        }
    }
}
