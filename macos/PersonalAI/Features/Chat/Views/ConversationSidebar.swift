import SwiftUI

enum SidebarMode: Equatable {
    case expanded
    case compact
}

struct SidebarContainer: View {
    @Binding var mode: SidebarMode
    let conversations: [Conversation]
    @Binding var selectedConversationID: UUID?
    @Binding var destination: AppDestination?
    let onNewChat: () -> Void
    let onRenameConversation: (UUID, String) -> Void
    let onDeleteConversation: (UUID) -> Void

    var body: some View {
        Group {
            if mode == .expanded {
                ConversationSidebar(
                    conversations: conversations,
                    selectedConversationID: $selectedConversationID,
                    destination: $destination,
                    onNewChat: onNewChat,
                    onRenameConversation: onRenameConversation,
                    onDeleteConversation: onDeleteConversation,
                    onCollapse: { mode = .compact }
                )
                .transition(.opacity)
            } else {
                CompactConversationSidebar(
                    destination: $destination,
                    onNewChat: onNewChat,
                    onExpand: { mode = .expanded }
                )
                .transition(.opacity)
            }
        }
        .frame(width: mode == .expanded ? 252 : 60)
        .clipped()
        .background(.thinMaterial)
    }
}

struct ConversationSidebar: View {
    let conversations: [Conversation]
    @Binding var selectedConversationID: UUID?
    @Binding var destination: AppDestination?
    let onNewChat: () -> Void
    let onRenameConversation: (UUID, String) -> Void
    let onDeleteConversation: (UUID) -> Void
    let onCollapse: () -> Void

    @State private var renameConversationID: UUID?
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var deleteConversationID: UUID?
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            identity
            newChatButton

            List(selection: $selectedConversationID) {
                Section("Recent") {
                    if conversations.isEmpty {
                        Text("No recent conversations")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(conversations) { conversation in
                            ConversationRow(
                                title: conversation.title,
                                isSelected: selectedConversationID == conversation.id,
                                onRename: { beginRename(conversation) },
                                onDelete: { beginDelete(conversation) }
                            )
                                .tag(conversation.id)
                                .contextMenu {
                                    Button("Rename") {
                                        beginRename(conversation)
                                    }

                                    Divider()

                                    Button("Delete", role: .destructive) {
                                        beginDelete(conversation)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
                .padding(.horizontal, AppSpacing.medium)

            List(selection: $destination) {
                navigationRow("Profile", systemImage: "person.crop.circle", destination: .profile)
                navigationRow("Memory", systemImage: "brain", destination: .memory)
                navigationRow("Skills", systemImage: "hammer", destination: .skills)
                navigationRow("Settings", systemImage: "gearshape", destination: .settings)
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .frame(height: 146)
            .padding(.vertical, AppSpacing.xSmall)
        }
        .background(.thinMaterial)
        .alert("Rename Conversation", isPresented: $isRenaming) {
            TextField("Conversation name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renameConversationID {
                    onRenameConversation(renameConversationID, renameText)
                }
                renameConversationID = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a new name for this conversation.")
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleteConversationID {
                    onDeleteConversation(deleteConversationID)
                }
                deleteConversationID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This conversation and its messages will be permanently deleted.")
        }
    }

    private var identity: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "sparkle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            Text("Personal AI")
                .font(AppTypography.sidebarTitle)

            Spacer()

            Button(action: onCollapse) {
                Image(systemName: "sidebar.left")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Compact Sidebar")
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.top, AppSpacing.large)
        .padding(.bottom, AppSpacing.medium)
    }

    private var newChatButton: some View {
        Button(action: onNewChat) {
            Label("New Chat", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.bottom, AppSpacing.medium)
    }

    private var deleteConfirmationTitle: String {
        guard let id = deleteConversationID,
              let conversation = conversations.first(where: { $0.id == id }) else {
            return "Delete Conversation?"
        }
        return "Delete “\(conversation.title)”?"
    }

    private func beginRename(_ conversation: Conversation) {
        renameConversationID = conversation.id
        renameText = conversation.title
        isRenaming = true
    }

    private func beginDelete(_ conversation: Conversation) {
        deleteConversationID = conversation.id
        isConfirmingDelete = true
    }

    private func navigationRow(
        _ title: String,
        systemImage: String,
        destination: AppDestination
    ) -> some View {
        Label(title, systemImage: systemImage)
            .tag(destination)
    }
}

private struct CompactConversationSidebar: View {
    @Binding var destination: AppDestination?
    let onNewChat: () -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            Image(systemName: "sparkle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .help("Personal AI")
                .padding(.top, AppSpacing.medium)

            compactButton("Expand Sidebar", icon: "sidebar.right", action: onExpand)
            compactButton("New Chat", icon: "square.and.pencil", action: onNewChat)

            Spacer()

            destinationButton("Profile", icon: "person.crop.circle", destination: .profile)
            destinationButton("Memory", icon: "brain", destination: .memory)
            destinationButton("Skills", icon: "hammer", destination: .skills)
            destinationButton("Settings", icon: "gearshape", destination: .settings)
                .padding(.bottom, AppSpacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
    }

    private func destinationButton(_ title: String, icon: String, destination value: AppDestination) -> some View {
        let selected = destination == value
        return Button {
            destination = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 38, height: 32)
                .background(selected ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
