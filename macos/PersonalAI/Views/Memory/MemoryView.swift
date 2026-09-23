import SwiftUI

struct MemoryView: View {
    var body: some View {
        DetailPage(title: "Memory", subtitle: "What Personal AI remembers about you and your work.") {
            EmptyStateView(
                icon: "brain",
                title: "No memories yet",
                description: "Personal AI will show useful information it remembers here."
            )
        }
    }
}
