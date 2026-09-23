import SwiftUI

struct ConversationRow: View {
    let title: String
    let isSelected: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isShowingActions = false

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)

            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: AppSpacing.xSmall)

            Button {
                isShowingActions.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isShowingActions ? 1 : 0)
            .allowsHitTesting(isHovered || isShowingActions)
            .help("Conversation actions")
            .accessibilityLabel("Actions for \(title)")
            .popover(isPresented: $isShowingActions, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    actionButton("Rename", systemImage: "pencil") {
                        isShowingActions = false
                        onRename()
                    }

                    actionButton("Delete", systemImage: "trash", role: .destructive) {
                        isShowingActions = false
                        onDelete()
                    }
                }
                .padding(AppSpacing.small)
                .frame(minWidth: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.xSmall)
        .padding(.vertical, AppSpacing.xSmall)
    }
}
